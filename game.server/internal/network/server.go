package network

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"slices"
	"strings"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"

	"gameserver/internal/config"
	"gameserver/internal/game"
	"gameserver/internal/matchmaking"
)

// Server wires HTTP and WebSocket endpoints to the matchmaking registry.
type Server struct {
	reg      *matchmaking.Registry
	cfg      config.Server
	tickRate int
	log      *slog.Logger
	upgrader websocket.Upgrader
	connSeq  atomic.Int64
}

// NewServer creates the network server.
func NewServer(reg *matchmaking.Registry, cfg config.Server, tickRate int, log *slog.Logger) *Server {
	s := &Server{reg: reg, cfg: cfg, tickRate: tickRate, log: log}
	s.upgrader = websocket.Upgrader{
		ReadBufferSize:  4096,
		WriteBufferSize: 4096,
		CheckOrigin:     s.checkOrigin,
	}
	return s
}

// Handler returns the HTTP routes:
//
//	GET  /health      liveness + number of games
//	POST /games       create an empty game (players join over WebSocket)
//	GET  /games/{id}  game summary
//	GET  /ws          WebSocket endpoint for real-time play
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("POST /games", s.handleCreateGame)
	mux.HandleFunc("GET /games/{id}", s.handleGetGame)
	mux.HandleFunc("GET /ws", s.handleWS)
	return s.logRequests(mux)
}

func (s *Server) checkOrigin(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" || len(s.cfg.AllowedOrigins) == 0 {
		return true
	}
	return slices.ContainsFunc(s.cfg.AllowedOrigins, func(o string) bool { return strings.EqualFold(o, origin) })
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, HealthResponse{Status: "ok", Games: s.reg.Count()})
}

func (s *Server) handleCreateGame(w http.ResponseWriter, _ *http.Request) {
	room, err := s.reg.CreateGame()
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, ErrorMessage{Type: MsgError, Code: "create_failed", Message: err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, CreateGameResponse{GameID: room.ID()})
}

func (s *Server) handleGetGame(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	room, err := s.reg.Get(id)
	if errors.Is(err, matchmaking.ErrGameNotFound) {
		writeJSON(w, http.StatusNotFound, ErrorMessage{Type: MsgError, Code: "game_not_found", Message: "game " + id + " does not exist"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), s.cfg.RequestTimeout())
	defer cancel()
	v, err := room.Snapshot(ctx)
	if err != nil {
		writeJSON(w, http.StatusNotFound, ErrorMessage{Type: MsgError, Code: "game_closed", Message: err.Error()})
		return
	}
	// Only a summary: full state is sent per player over WebSocket so that
	// fog of war can be enforced later.
	resp := GameInfoResponse{
		ID: v.ID, Status: wire(v.Status), Tick: v.Tick,
		CreatedAt: v.CreatedAt.UTC().Format(time.RFC3339),
		Players:   toPlayers(&v), Battles: len(v.Battles),
		WinnerID: string(v.WinnerID), FinishReason: v.FinishReason,
	}
	if !v.StartedAt.IsZero() {
		resp.StartedAt = v.StartedAt.UTC().Format(time.RFC3339)
	}
	for _, d := range v.Divisions {
		if d.State != game.StateDestroyed {
			resp.Divisions++
		}
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		s.log.Warn("websocket upgrade failed", "remote", r.RemoteAddr, "err", err)
		return
	}
	connID := s.connSeq.Add(1)
	log := s.log.With("conn_id", connID, "remote", r.RemoteAddr)
	log.Info("client connected")
	newClient(s, conn, log).run()
}

func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/ws" {
			s.log.Debug("http request", "method", r.Method, "path", r.URL.Path, "remote", r.RemoteAddr)
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
