package network

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"

	"gameserver/internal/app"
	"gameserver/internal/combat"
	"gameserver/internal/config"
	"gameserver/internal/game"
	"gameserver/internal/matchmaking"
	"gameserver/internal/terrain"
	"gameserver/pkg/geom"
)

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	cfg := config.Default()
	cfg.Game.TickRate = 50 // fast simulation for tests
	cfg.Game.StartCountdownTicks = 2
	cfg.Game.DisconnectGraceTicks = 10
	// Compact armies: the armored divisions start 200 units apart next to
	// the northern ford so combat happens quickly.
	cfg.Game.Army = []game.DivisionTemplate{
		{Name: "Infantry", Offset: geom.V(0, -150), UnitCount: 3000, Attack: 10, Defense: 12, Speed: 30, Morale: 80},
		{Name: "Armored", Offset: geom.V(700, -300), UnitCount: 2000, Attack: 16, Defense: 8, Speed: 45, Morale: 85},
	}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	m, err := terrain.DefaultMap(cfg.Terrain)
	if err != nil {
		t.Fatal(err)
	}
	engine := combat.NewSimpleEngine(cfg.Game.Combat)
	reg := matchmaking.NewRegistry(func() app.RoomConfig {
		return app.RoomConfig{Rules: cfg.Game, Map: m, Engine: engine, SnapshotEveryTicks: 5, FinishedRetention: time.Minute, Logger: log}
	}, 10, log)
	srv := httptest.NewServer(NewServer(reg, cfg.Server, cfg.Game.TickRate, log).Handler())
	t.Cleanup(func() { reg.Shutdown(); srv.Close() })
	return srv
}

type wsClient struct {
	t    *testing.T
	conn *websocket.Conn
}

func dial(t *testing.T, srv *httptest.Server) *wsClient {
	t.Helper()
	url := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return &wsClient{t: t, conn: conn}
}

func (c *wsClient) send(msg any) {
	c.t.Helper()
	if err := c.conn.WriteJSON(msg); err != nil {
		c.t.Fatal(err)
	}
}

// waitFor reads messages until one of the given type arrives and decodes it.
func (c *wsClient) waitFor(typ string, into any) {
	c.t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		_ = c.conn.SetReadDeadline(deadline)
		_, data, err := c.conn.ReadMessage()
		if err != nil {
			c.t.Fatalf("waiting for %s: %v", typ, err)
		}
		var env Envelope
		if err := json.Unmarshal(data, &env); err != nil {
			c.t.Fatalf("invalid JSON from server: %s", data)
		}
		if env.Type == typ {
			if into != nil {
				if err := json.Unmarshal(data, into); err != nil {
					c.t.Fatal(err)
				}
			}
			return
		}
		if env.Type == MsgError && typ != MsgError {
			c.t.Fatalf("unexpected error while waiting for %s: %s", typ, data)
		}
	}
}

func TestHTTPEndpoints(t *testing.T) {
	srv := newTestServer(t)

	resp, err := http.Get(srv.URL + "/health")
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("health: %v %v", resp, err)
	}
	resp.Body.Close()

	resp, err = http.Post(srv.URL+"/games", "application/json", nil)
	if err != nil || resp.StatusCode != http.StatusCreated {
		t.Fatalf("create: %v %v", resp, err)
	}
	var created CreateGameResponse
	_ = json.NewDecoder(resp.Body).Decode(&created)
	resp.Body.Close()

	resp, err = http.Get(srv.URL + "/games/" + created.GameID)
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("get: %v %v", resp, err)
	}
	var info GameInfoResponse
	_ = json.NewDecoder(resp.Body).Decode(&info)
	resp.Body.Close()
	if info.ID != created.GameID || info.Status != "waiting" {
		t.Fatalf("info %+v", info)
	}

	resp, _ = http.Get(srv.URL + "/games/nope")
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("missing game status %d", resp.StatusCode)
	}
	resp.Body.Close()
}

// TestWebSocketMatch walks the MVP flow end to end over real sockets.
func TestWebSocketMatch(t *testing.T) {
	srv := newTestServer(t)
	c1, c2 := dial(t, srv), dial(t, srv)

	// 1-2. Connect both players.
	c1.send(map[string]any{"type": "create_game", "request_id": "r1", "player_name": "Alice"})
	var created GameJoinedMessage
	c1.waitFor(MsgGameCreated, &created)
	if created.GameID == "" || created.SessionToken == "" || created.Map.Cols == 0 || created.RequestID != "r1" {
		t.Fatalf("game_created incomplete: %+v", created)
	}

	c2.send(map[string]any{"type": "join_game", "game_id": created.GameID, "player_name": "Bob"})
	var joined GameJoinedMessage
	c2.waitFor(MsgGameJoined, &joined)
	if joined.Side != 1 || joined.PlayerID == created.PlayerID {
		t.Fatalf("game_joined: %+v", joined)
	}

	// Orders before start are refused.
	c1.send(map[string]any{"type": "hold_division", "request_id": "early", "division_id": "division-1"})
	var early ErrorMessage
	c1.waitFor(MsgError, &early)
	if early.Code != "game_not_running" || early.RequestID != "early" {
		t.Fatalf("early order error %+v", early)
	}

	// 3-4. Start and receive the initial state.
	c1.send(map[string]any{"type": "ready"})
	c2.send(map[string]any{"type": "ready"})
	var started GameStartedMessage
	c1.waitFor(MsgGameStarted, &started)
	c2.waitFor(MsgGameStarted, nil)
	if len(started.State.Divisions) != 4 || started.State.Status != "running" {
		t.Fatalf("initial state: %+v", started.State)
	}
	var mine, theirs DivisionDTO
	for _, d := range started.State.Divisions {
		if d.PlayerID == created.PlayerID && mine.ID == "" {
			mine = d
		}
		if d.PlayerID == joined.PlayerID && theirs.ID == "" {
			theirs = d
		}
	}

	// 5-7. Select a division, MOVE it and see it move.
	c1.send(map[string]any{"type": "move_division", "request_id": "m1", "division_id": mine.ID, "x": mine.X + 100, "y": mine.Y})
	var acc OrderAcceptedMessage
	c1.waitFor(MsgOrderAccepted, &acc)
	if acc.Order.Type != "move" || acc.RequestID != "m1" {
		t.Fatalf("order_accepted %+v", acc)
	}
	var upd DivisionUpdatedMessage
	c1.waitFor(MsgDivisionUpdated, &upd)
	if upd.Division.ID != mine.ID || upd.Division.State != "moving" || upd.Division.Order == nil {
		t.Fatalf("division_updated %+v", upd)
	}
	var st GameStateMessage
	for moved := false; !moved; {
		c1.waitFor(MsgGameState, &st)
		for _, d := range st.Divisions {
			if d.ID == mine.ID && d.X > mine.X+1 {
				moved = true
			}
		}
	}

	// Server validation: cannot command the enemy's division.
	c1.send(map[string]any{"type": "hold_division", "request_id": "bad", "division_id": theirs.ID})
	var e ErrorMessage
	c1.waitFor(MsgError, &e)
	if e.Code != "not_owner" {
		t.Fatalf("expected not_owner, got %+v", e)
	}

	// 8-10. ATTACK: the armored division crosses the map and engages.
	var armored, enemyArmored DivisionDTO
	for _, d := range started.State.Divisions {
		if d.Name == "Armored" && d.PlayerID == created.PlayerID {
			armored = d
		} else if d.Name == "Armored" {
			enemyArmored = d
		}
	}
	c1.send(map[string]any{"type": "attack_division", "division_id": armored.ID, "target_division_id": enemyArmored.ID})
	c1.waitFor(MsgOrderAccepted, nil)
	var bs BattleStartedMessage
	c2.waitFor(MsgBattleStarted, &bs)
	var bu BattleUpdatedMessage
	c2.waitFor(MsgBattleUpdated, &bu)
	if bu.Attacker.Losses == 0 && bu.Defender.Losses == 0 {
		t.Fatalf("combat round without effect: %+v", bu)
	}

	// 11. Keep giving orders: defender digs in.
	c2.send(map[string]any{"type": "defend_division", "division_id": enemyArmored.ID})
	c2.waitFor(MsgOrderAccepted, nil)

	// 12. Player 2 leaves; after the grace period player 1 wins.
	c2.conn.Close()
	var lobby LobbyUpdatedMessage
	for {
		c1.waitFor(MsgLobbyUpdated, &lobby)
		if !lobby.Players[1].Connected {
			break
		}
	}
	var fin GameFinishedMessage
	c1.waitFor(MsgGameFinished, &fin)
	if fin.Result != "victory" || fin.WinnerPlayerID != created.PlayerID || fin.Reason != "opponent_disconnected" {
		t.Fatalf("game_finished %+v", fin)
	}
}

func TestWebSocketProtocolErrors(t *testing.T) {
	srv := newTestServer(t)
	c := dial(t, srv)
	var e ErrorMessage

	c.send(map[string]any{"type": "teleport"})
	c.waitFor(MsgError, &e)
	if e.Code != "unknown_message_type" {
		t.Fatalf("got %+v", e)
	}
	if err := c.conn.WriteMessage(websocket.TextMessage, []byte("{not json")); err != nil {
		t.Fatal(err)
	}
	c.waitFor(MsgError, &e)
	if e.Code != "bad_request" {
		t.Fatalf("got %+v", e)
	}
	c.send(map[string]any{"type": "ready"})
	c.waitFor(MsgError, &e)
	if e.Code != "not_in_game" {
		t.Fatalf("got %+v", e)
	}
	c.send(map[string]any{"type": "join_game", "game_id": "game-missing"})
	c.waitFor(MsgError, &e)
	if e.Code != "game_not_found" {
		t.Fatalf("got %+v", e)
	}
}
