package game

import (
	"reflect"
	"testing"

	"gameserver/internal/player"
)

// playScripted runs a full match on the default map: player 1 keeps sending
// its idle divisions to attack the nearest enemy while player 2 defends.
func playScripted(t *testing.T) (*testGame, []GameEvent) {
	t.Helper()
	tg := newRunningGame(t, defaultMap(t), DefaultRules())
	for _, d := range tg.Divisions() {
		if d.PlayerID == tg.p2 {
			tg.order(t, OrderRequest{PlayerID: tg.p2, DivisionID: d.ID, Type: OrderDefend})
		}
	}
	var events []GameEvent
	for i := 0; tg.Status == StatusRunning; i++ {
		if i > int(tg.Rules.MaxDurationTicks)+1 {
			t.Fatal("game did not end")
		}
		if i%20 == 0 {
			for _, d := range tg.Divisions() {
				// Divisions left without any command (no commander, general nor
				// successor) cannot receive orders: they keep their last one.
				if d.PlayerID != tg.p1 || !d.Alive() || d.Routed || d.CurrentOrder != nil || tg.engaged(d.ID) ||
					tg.CommandLinkOf(d.ID) == LinkNoCommand {
					continue
				}
				if target := nearestEnemy(tg, d); target != nil {
					tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: d.ID, Type: OrderAttack, TargetDivisionID: target.ID})
				}
			}
		}
		events = append(events, tg.Tick()...)
	}
	return tg, events
}

func nearestEnemy(tg *testGame, d *Division) *Division {
	var best *Division
	for _, e := range tg.Divisions() {
		if e.PlayerID == d.PlayerID || !e.Alive() {
			continue
		}
		if best == nil || d.Position.Dist(e.Position) < d.Position.Dist(best.Position) {
			best = e
		}
	}
	return best
}

func TestGameLoopFullMatch(t *testing.T) {
	tg, events := playScripted(t)

	if tg.Status != StatusFinished {
		t.Fatalf("status %s", tg.Status)
	}
	if _, ok := events[len(events)-1].(GameFinished); !ok {
		t.Fatalf("last event must be game_finished, got %T", events[len(events)-1])
	}
	if countEvents[GameFinished](events) != 1 {
		t.Fatal("game_finished must be emitted exactly once")
	}
	if countEvents[BattleStarted](events) == 0 || countEvents[BattleUpdated](events) == 0 {
		t.Fatal("a full match must include combat")
	}

	// Event stream consistency.
	started := map[string]bool{}
	ended := map[string]bool{}
	destroyed := map[DivisionID]int{}
	var lastTick int64
	for _, e := range events {
		if e.Tick() < lastTick {
			t.Fatalf("events out of order: %T at tick %d after %d", e, e.Tick(), lastTick)
		}
		lastTick = e.Tick()
		switch ev := e.(type) {
		case BattleStarted:
			started[ev.BattleID] = true
		case BattleUpdated:
			if !started[ev.BattleID] || ended[ev.BattleID] {
				t.Fatalf("battle_updated for battle %s not in progress", ev.BattleID)
			}
		case BattleEnded:
			if !started[ev.BattleID] || ended[ev.BattleID] {
				t.Fatalf("battle %s ended twice or never started", ev.BattleID)
			}
			ended[ev.BattleID] = true
		case DivisionDestroyed:
			destroyed[ev.DivisionID]++
		}
	}
	for id, n := range destroyed {
		if n != 1 {
			t.Fatalf("division %s destroyed %d times", id, n)
		}
		if d, _ := tg.Division(id); d.Alive() || d.UnitCount != 0 {
			t.Fatalf("destroyed division %s still alive", id)
		}
	}

	// Invariants on the final state.
	for _, d := range tg.Divisions() {
		if d.UnitCount < 0 || d.UnitCount > d.MaxUnitCount {
			t.Fatalf("%s unit_count %d out of range", d.ID, d.UnitCount)
		}
		if d.Morale < 0 || d.Morale > tg.Rules.MaxMorale || d.Fatigue < 0 || d.Fatigue > 100 {
			t.Fatalf("%s morale/fatigue out of range: %.1f/%.1f", d.ID, d.Morale, d.Fatigue)
		}
		if !tg.Map.Passable(d.Position) {
			t.Fatalf("%s ended on impassable terrain", d.ID)
		}
	}
	t.Logf("finished at tick %d: winner=%s reason=%s battles=%d destroyed=%d",
		tg.CurrentTick, tg.WinnerID, tg.FinishReason, len(started), len(destroyed))
}

func TestGameLoopIsDeterministic(t *testing.T) {
	a, evA := playScripted(t)
	b, evB := playScripted(t)
	if a.CurrentTick != b.CurrentTick || a.WinnerID != b.WinnerID || len(evA) != len(evB) {
		t.Fatalf("runs diverged: ticks %d/%d winners %s/%s events %d/%d",
			a.CurrentTick, b.CurrentTick, a.WinnerID, b.WinnerID, len(evA), len(evB))
	}
	if !reflect.DeepEqual(a.ViewFor(Spectator).Divisions, b.ViewFor(Spectator).Divisions) {
		t.Fatal("final states differ")
	}
}

func TestViewHidesOpponentOrders(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	d := tg.div(t, tg.p1, 0)
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: d.ID, Type: OrderMove, TargetPosition: pos(800, 800)})
	tg.Tick()

	own, ok := tg.DivisionViewFor(tg.p1, d.ID)
	if !ok || own.Order == nil || len(own.Path) == 0 {
		t.Fatalf("owner must see order and path: %+v", own)
	}
	enemy, ok := tg.DivisionViewFor(tg.p2, d.ID)
	if !ok || enemy.Order != nil || enemy.Path != nil {
		t.Fatalf("opponent must not see orders: %+v", enemy)
	}
	if v := tg.ViewFor(tg.p2); len(v.Divisions) != 2 {
		t.Fatalf("without fog of war both divisions are visible, got %d", len(v.Divisions))
	}
}

// hideEnemies is a minimal fog-of-war policy used to prove the extension point.
type hideEnemies struct{}

func (hideEnemies) CanSee(_ *Game, viewer player.ID, d *Division) bool { return d.PlayerID == viewer }

func TestVisibilityPolicyFiltersState(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	tg.visibility = hideEnemies{}
	enemy := tg.div(t, tg.p2, 0)
	if v := tg.ViewFor(tg.p1); len(v.Divisions) != 1 {
		t.Fatalf("p1 should only see its own division, got %d", len(v.Divisions))
	}
	if tg.EventVisibleTo(DivisionUpdated{DivisionID: enemy.ID}, tg.p1) {
		t.Fatal("event about hidden division leaked")
	}
	_, err := tg.ValidateOrder(OrderRequest{PlayerID: tg.p1, DivisionID: tg.div(t, tg.p1, 0).ID, Type: OrderAttack, TargetDivisionID: enemy.ID})
	if CodeOf(err) != CodeTargetNotFound {
		t.Fatalf("attacking an unseen division must look like a missing target, got %v", err)
	}
}
