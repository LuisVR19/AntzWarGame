package game

import (
	"strings"
	"testing"
	"time"

	"gameserver/internal/combat"
	"gameserver/internal/player"
	"gameserver/internal/terrain"
	"gameserver/pkg/geom"
)

var fixedNow = time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)

// plainMap returns a 40x24 map of 50-unit plain tiles (2000x1200).
func plainMap(t *testing.T) *terrain.Map {
	t.Helper()
	rows := make([]string, 24)
	for i := range rows {
		rows[i] = strings.Repeat("P", 40)
	}
	m, err := terrain.NewMap(rows, 50, terrain.DefaultTable(), terrain.DefaultSpawns())
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func defaultMap(t *testing.T) *terrain.Map {
	t.Helper()
	m, err := terrain.DefaultMap(terrain.DefaultTable())
	if err != nil {
		t.Fatal(err)
	}
	return m
}

// oneDivisionRules gives each player a single infantry division and no countdown.
func oneDivisionRules() Rules {
	r := DefaultRules()
	r.StartCountdownTicks = 0
	r.Army = []DivisionTemplate{
		{Name: "Infantry", UnitCount: 3000, Attack: 10, Defense: 10, Speed: 30, Morale: 80, Experience: 0},
	}
	return r
}

type testGame struct {
	*Game
	p1, p2 player.ID
}

// newRunningGame creates a game with two ready players and ticks it into RUNNING.
func newRunningGame(t *testing.T, m *terrain.Map, rules Rules) *testGame {
	t.Helper()
	g, err := New("test", m, rules, combat.NewSimpleEngine(rules.Combat), WithClock(func() time.Time { return fixedNow }))
	if err != nil {
		t.Fatal(err)
	}
	a, err := g.AddPlayer("alice", "tok-a")
	if err != nil {
		t.Fatal(err)
	}
	b, err := g.AddPlayer("bob", "tok-b")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := g.SetReady(a.ID, true); err != nil {
		t.Fatal(err)
	}
	started, err := g.SetReady(b.ID, true)
	if err != nil || !started {
		t.Fatalf("game did not start: started=%v err=%v", started, err)
	}
	for i := 0; g.Status != StatusRunning; i++ {
		if i > rules.StartCountdownTicks+1 {
			t.Fatal("game never reached RUNNING")
		}
		g.Tick()
	}
	return &testGame{Game: g, p1: a.ID, p2: b.ID}
}

// div returns the n-th division (0-based) of a player.
func (tg *testGame) div(t *testing.T, pid player.ID, n int) *Division {
	t.Helper()
	army, ok := tg.Army(pid)
	if !ok || n >= len(army.DivisionIDs) {
		t.Fatalf("player %s has no division #%d", pid, n)
	}
	d, _ := tg.Division(army.DivisionIDs[n])
	return d
}

func (tg *testGame) order(t *testing.T, req OrderRequest) *Order {
	t.Helper()
	o, err := tg.SubmitOrder(req)
	if err != nil {
		t.Fatalf("order %+v rejected: %v", req, err)
	}
	return o
}

// run ticks n times and returns all events.
func (tg *testGame) run(n int) []GameEvent {
	var all []GameEvent
	for i := 0; i < n && tg.Status == StatusRunning; i++ {
		all = append(all, tg.Tick()...)
	}
	return all
}

// runUntil ticks until cond holds or max ticks elapse.
func (tg *testGame) runUntil(t *testing.T, max int, cond func() bool) []GameEvent {
	t.Helper()
	var all []GameEvent
	for i := 0; i < max; i++ {
		if cond() {
			return all
		}
		if tg.Status != StatusRunning {
			break
		}
		all = append(all, tg.Tick()...)
	}
	if !cond() {
		t.Fatalf("condition not met after %d ticks (tick=%d status=%s)", max, tg.CurrentTick, tg.Status)
	}
	return all
}

func pos(x, y float64) *Position { p := geom.V(x, y); return &p }

func countEvents[T GameEvent](events []GameEvent) int {
	n := 0
	for _, e := range events {
		if _, ok := e.(T); ok {
			n++
		}
	}
	return n
}
