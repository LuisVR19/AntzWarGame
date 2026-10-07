package app

import (
	"context"
	"io"
	"log/slog"
	"sync"
	"testing"

	"gameserver/internal/combat"
	"gameserver/internal/game"
	"gameserver/internal/terrain"
)

type recorder struct {
	mu  sync.Mutex
	out []Output
}

func (r *recorder) Deliver(o Output) {
	r.mu.Lock()
	r.out = append(r.out, o)
	r.mu.Unlock()
}

func (r *recorder) take() []Output {
	r.mu.Lock()
	defer r.mu.Unlock()
	o := r.out
	r.out = nil
	return o
}

func (r *recorder) has(kind OutputKind) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, o := range r.out {
		if o.Kind == kind {
			return true
		}
	}
	return false
}

func newTestRoom(t *testing.T) *Room {
	t.Helper()
	rules := game.DefaultRules()
	rules.StartCountdownTicks = 3
	m, err := terrain.DefaultMap(terrain.DefaultTable())
	if err != nil {
		t.Fatal(err)
	}
	r, err := NewRoom("game-test", RoomConfig{
		Rules: rules, Map: m, Engine: combat.NewSimpleEngine(rules.Combat),
		SnapshotEveryTicks: 1, ManualClock: true,
		Logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(r.Close)
	return r
}

func TestRoomLifecycle(t *testing.T) {
	ctx := context.Background()
	r := newTestRoom(t)
	s1, s2 := &recorder{}, &recorder{}

	p1, err := r.Join(ctx, "alice", "", "req-1", true, s1)
	if err != nil {
		t.Fatal(err)
	}
	out := s1.take()
	if len(out) < 2 || out[0].Kind != OutJoined || !out[0].Join.Created || out[0].RequestID != "req-1" {
		t.Fatalf("join confirmation must come first: %+v", out)
	}
	token1 := out[0].Join.SessionToken

	p2, err := r.Join(ctx, "bob", "", "", false, s2)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := r.Join(ctx, "carol", "", "", false, &recorder{}); game.CodeOf(err) != game.CodeGameFull {
		t.Fatalf("third player: %v", err)
	}
	if !s1.has(OutLobby) {
		t.Fatal("player 1 must be notified when player 2 joins")
	}

	// Orders before the game starts are rejected.
	if _, err := r.SubmitOrder(ctx, game.OrderRequest{PlayerID: p1, DivisionID: "division-1", Type: game.OrderHold}); game.CodeOf(err) != game.CodeGameNotRunning {
		t.Fatalf("early order: %v", err)
	}

	if err := r.Ready(ctx, p1, true); err != nil {
		t.Fatal(err)
	}
	if err := r.Ready(ctx, p2, true); err != nil {
		t.Fatal(err)
	}
	s1.take()
	for i := 0; i < 3; i++ {
		if err := r.Step(ctx); err != nil {
			t.Fatal(err)
		}
	}
	if !s1.has(OutGameStarted) || !s2.has(OutGameStarted) {
		t.Fatal("both players must receive game_started")
	}

	o, err := r.SubmitOrder(ctx, game.OrderRequest{PlayerID: p1, DivisionID: "division-1", Type: game.OrderMove, TargetPosition: &game.Position{X: 400, Y: 450}})
	if err != nil {
		t.Fatal(err)
	}
	if o.ID == "" {
		t.Fatal("order without ID")
	}
	s1.take()
	s2.take()
	if err := r.Step(ctx); err != nil {
		t.Fatal(err)
	}
	var sawUpdate, sawSnapshot bool
	for _, out := range s2.take() {
		switch out.Kind {
		case OutEvent:
			if du, ok := out.Event.(game.DivisionUpdated); ok && du.DivisionID == "division-1" {
				sawUpdate = true
				if out.Division.Order != nil {
					t.Fatal("opponent received the order details")
				}
			}
		case OutSnapshot:
			sawSnapshot = true
			if out.Viewer != p2 {
				t.Fatalf("snapshot for wrong viewer %s", out.Viewer)
			}
		}
	}
	if !sawUpdate || !sawSnapshot {
		t.Fatalf("opponent missing outputs: update=%v snapshot=%v", sawUpdate, sawSnapshot)
	}

	// Disconnect + reconnect with the session token.
	r.Disconnect(p1, s1)
	s1b := &recorder{}
	again, err := r.Join(ctx, "", token1, "", false, s1b)
	if err != nil || again != p1 {
		t.Fatalf("reconnect: id=%s err=%v", again, err)
	}
	if out := s1b.take(); out[0].Kind != OutJoined || !out[0].Join.Reconnected {
		t.Fatalf("reconnect confirmation: %+v", out[0])
	}
	// A stale disconnect from the old connection is ignored.
	r.Disconnect(p1, s1)
	var connected bool
	_ = r.Inspect(ctx, func(g *game.Game) { p, _ := g.Player(p1); connected = p.Connected })
	if !connected {
		t.Fatal("stale disconnect must not affect the reconnected player")
	}
	if _, err := r.Join(ctx, "", "bad-token", "", false, &recorder{}); game.CodeOf(err) != game.CodePlayerNotFound {
		t.Fatalf("bad token: %v", err)
	}

	// Both leave: the game is aborted.
	r.Disconnect(p1, s1b)
	r.Disconnect(p2, s2)
	var status game.Status
	_ = r.Inspect(ctx, func(g *game.Game) { status = g.Status })
	if status != game.StatusFinished {
		t.Fatalf("abandoned game status %s", status)
	}
}

func TestRoomClosesEmptyLobby(t *testing.T) {
	ctx := context.Background()
	r := newTestRoom(t)
	s := &recorder{}
	p, err := r.Join(ctx, "alice", "", "", true, s)
	if err != nil {
		t.Fatal(err)
	}
	r.Disconnect(p, s)
	<-r.Done()
	if _, err := r.Snapshot(ctx); err != ErrRoomClosed {
		t.Fatalf("closed room: %v", err)
	}
}
