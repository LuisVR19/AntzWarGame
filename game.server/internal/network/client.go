package network

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/gorilla/websocket"

	"gameserver/internal/app"
	"gameserver/internal/game"
	"gameserver/internal/matchmaking"
	"gameserver/internal/player"
)

const maxPlayerNameLen = 32

// client is one WebSocket connection. It runs two goroutines:
//   - readLoop: decodes messages and calls the Room (owns room/playerID)
//   - writeLoop: the only writer to the socket
//
// Rooms push outputs through Deliver, which never blocks: if the client
// cannot keep up its queue fills and the connection is dropped.
type client struct {
	srv    *Server
	conn   *websocket.Conn
	send   chan []byte
	closed chan struct{}
	once   sync.Once
	log    *slog.Logger

	// Accessed only by readLoop.
	room     *app.Room
	playerID player.ID
}

func newClient(srv *Server, conn *websocket.Conn, log *slog.Logger) *client {
	return &client{
		srv:    srv,
		conn:   conn,
		send:   make(chan []byte, srv.cfg.SendQueueSize),
		closed: make(chan struct{}),
		log:    log,
	}
}

// Deliver implements app.Subscriber. Called from the Room goroutine.
func (c *client) Deliver(out app.Output) {
	if msg := encodeOutput(out, c.srv.tickRate); msg != nil {
		c.enqueue(msg)
	}
}

func (c *client) enqueue(msg any) {
	data, err := json.Marshal(msg)
	if err != nil {
		c.log.Error("encode message failed", "err", err)
		return
	}
	select {
	case <-c.closed:
	case c.send <- data:
	default:
		c.log.Warn("send queue full, dropping slow client")
		c.close()
	}
}

func (c *client) close() { c.once.Do(func() { close(c.closed) }) }

func (c *client) run() {
	go c.writeLoop()
	c.readLoop()
}

func (c *client) writeLoop() {
	ping := time.NewTicker(c.srv.cfg.PongTimeout() * 9 / 10)
	defer func() {
		ping.Stop()
		_ = c.conn.Close()
	}()
	wt := c.srv.cfg.WriteTimeout()
	for {
		select {
		case data := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(wt))
			if err := c.conn.WriteMessage(websocket.TextMessage, data); err != nil {
				c.close()
				return
			}
		case <-ping.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(wt))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				c.close()
				return
			}
		case <-c.closed:
			// Flush what is already queued, then say goodbye.
			for {
				select {
				case data := <-c.send:
					_ = c.conn.SetWriteDeadline(time.Now().Add(wt))
					if c.conn.WriteMessage(websocket.TextMessage, data) != nil {
						return
					}
					continue
				default:
				}
				break
			}
			_ = c.conn.WriteControl(websocket.CloseMessage,
				websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""), time.Now().Add(time.Second))
			return
		}
	}
}

func (c *client) readLoop() {
	defer func() {
		if c.room != nil {
			c.room.Disconnect(c.playerID, c)
		}
		c.close()
		c.log.Info("client disconnected", "game_id", c.gameID(), "player_id", c.playerID)
	}()
	c.conn.SetReadLimit(c.srv.cfg.MaxMessageBytes)
	pong := c.srv.cfg.PongTimeout()
	_ = c.conn.SetReadDeadline(time.Now().Add(pong))
	c.conn.SetPongHandler(func(string) error { return c.conn.SetReadDeadline(time.Now().Add(pong)) })
	for {
		typ, data, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway, websocket.CloseNoStatusReceived) {
				c.log.Info("read error", "err", err)
			}
			return
		}
		_ = c.conn.SetReadDeadline(time.Now().Add(pong))
		if typ != websocket.TextMessage {
			c.sendError("", "bad_request", "only text JSON messages are supported")
			continue
		}
		c.dispatch(data)
		select {
		case <-c.closed:
			return
		default:
		}
	}
}

func (c *client) gameID() string {
	if c.room == nil {
		return ""
	}
	return c.room.ID()
}

func (c *client) sendError(requestID, code, msg string) {
	c.enqueue(ErrorMessage{Type: MsgError, RequestID: requestID, Code: code, Message: msg})
}

func (c *client) dispatch(data []byte) {
	var env Envelope
	if err := json.Unmarshal(data, &env); err != nil || env.Type == "" {
		c.sendError("", "bad_request", "message must be a JSON object with a \"type\" field")
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), c.srv.cfg.RequestTimeout())
	defer cancel()

	switch env.Type {
	case MsgCreateGame:
		var m CreateGameRequest
		if c.decode(data, &m, env) {
			c.handleCreate(ctx, m)
		}
	case MsgJoinGame:
		var m JoinGameRequest
		if c.decode(data, &m, env) {
			c.handleJoin(ctx, m)
		}
	case MsgReady:
		var m ReadyRequest
		if c.decode(data, &m, env) && c.requireGame(env) {
			ready := m.Ready == nil || *m.Ready
			if err := c.room.Ready(ctx, c.playerID, ready); err != nil {
				c.replyErr(env.RequestID, err)
			}
		}
	case MsgMoveDivision:
		var m MoveDivisionRequest
		if c.decode(data, &m, env) && c.requireGame(env) {
			if m.X == nil || m.Y == nil {
				c.sendError(env.RequestID, string(game.CodeTargetRequired), "move_division requires x and y")
				return
			}
			c.order(ctx, env, game.OrderRequest{DivisionID: game.DivisionID(m.DivisionID), Type: game.OrderMove, TargetPosition: &game.Position{X: *m.X, Y: *m.Y}})
		}
	case MsgAttackDivision:
		var m AttackDivisionRequest
		if c.decode(data, &m, env) && c.requireGame(env) {
			c.order(ctx, env, game.OrderRequest{DivisionID: game.DivisionID(m.DivisionID), Type: game.OrderAttack, TargetDivisionID: game.DivisionID(m.TargetDivisionID)})
		}
	case MsgDefendDivision:
		var m DefendDivisionRequest
		if c.decode(data, &m, env) && c.requireGame(env) {
			c.order(ctx, env, game.OrderRequest{DivisionID: game.DivisionID(m.DivisionID), Type: game.OrderDefend})
		}
	case MsgRetreatDivision:
		var m RetreatDivisionRequest
		if c.decode(data, &m, env) && c.requireGame(env) {
			req := game.OrderRequest{DivisionID: game.DivisionID(m.DivisionID), Type: game.OrderRetreat}
			if m.X != nil && m.Y != nil {
				req.TargetPosition = &game.Position{X: *m.X, Y: *m.Y}
			}
			c.order(ctx, env, req)
		}
	case MsgHoldDivision:
		var m HoldDivisionRequest
		if c.decode(data, &m, env) && c.requireGame(env) {
			c.order(ctx, env, game.OrderRequest{DivisionID: game.DivisionID(m.DivisionID), Type: game.OrderHold})
		}
	default:
		c.sendError(env.RequestID, "unknown_message_type", "unknown message type "+env.Type)
	}
}

func (c *client) decode(data []byte, v any, env Envelope) bool {
	if err := json.Unmarshal(data, v); err != nil {
		c.sendError(env.RequestID, "bad_request", "invalid "+env.Type+" payload: "+err.Error())
		return false
	}
	return true
}

func (c *client) requireGame(env Envelope) bool {
	if c.room == nil {
		c.sendError(env.RequestID, "not_in_game", "create or join a game first")
		return false
	}
	return true
}

func (c *client) replyErr(requestID string, err error) {
	switch {
	case errors.Is(err, app.ErrRoomClosed):
		c.sendError(requestID, "game_closed", err.Error())
	case errors.Is(err, context.DeadlineExceeded):
		c.sendError(requestID, "timeout", "the server did not answer in time")
	default:
		c.enqueue(errorMessage(requestID, err))
	}
}

func sanitizeName(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		return "Player"
	}
	if utf8.RuneCountInString(name) > maxPlayerNameLen {
		name = string([]rune(name)[:maxPlayerNameLen])
	}
	return name
}

func (c *client) handleCreate(ctx context.Context, m CreateGameRequest) {
	if c.room != nil {
		c.sendError(m.RequestID, "already_in_game", "this connection is already in a game")
		return
	}
	room, err := c.srv.reg.CreateGame()
	if err != nil {
		c.sendError(m.RequestID, "create_failed", err.Error())
		return
	}
	pid, err := room.Join(ctx, sanitizeName(m.PlayerName), "", m.RequestID, true, c)
	if err != nil {
		room.Close()
		c.replyErr(m.RequestID, err)
		return
	}
	c.room, c.playerID = room, pid
	c.log.Info("game created by client", "game_id", room.ID(), "player_id", pid)
}

func (c *client) handleJoin(ctx context.Context, m JoinGameRequest) {
	if c.room != nil {
		c.sendError(m.RequestID, "already_in_game", "this connection is already in a game")
		return
	}
	room, err := c.srv.reg.Get(m.GameID)
	if errors.Is(err, matchmaking.ErrGameNotFound) {
		c.sendError(m.RequestID, "game_not_found", "game "+m.GameID+" does not exist")
		return
	}
	pid, err := room.Join(ctx, sanitizeName(m.PlayerName), m.SessionToken, m.RequestID, false, c)
	if err != nil {
		c.replyErr(m.RequestID, err)
		return
	}
	c.room, c.playerID = room, pid
	c.log.Info("client joined game", "game_id", room.ID(), "player_id", pid, "reconnect", m.SessionToken != "")
}

func (c *client) order(ctx context.Context, env Envelope, req game.OrderRequest) {
	req.PlayerID = c.playerID
	o, err := c.room.SubmitOrder(ctx, req)
	if err != nil {
		c.replyErr(env.RequestID, err)
		return
	}
	dto := OrderDTO{ID: o.ID, Type: wire(o.Type), TargetDivisionID: string(o.TargetDivisionID)}
	if o.TargetPosition != nil {
		p := toPosition(*o.TargetPosition)
		dto.TargetPosition = &p
	}
	c.enqueue(OrderAcceptedMessage{Type: MsgOrderAccepted, RequestID: env.RequestID, DivisionID: string(o.DivisionID), Order: dto})
}
