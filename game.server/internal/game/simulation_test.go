package game

import (
	"math"
	"testing"

	"gameserver/internal/terrain"
)

func TestMoveOrderMovesAtServerSpeed(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	d := tg.div(t, tg.p1, 0)
	start := d.Position
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: d.ID, Type: OrderMove, TargetPosition: pos(start.X+300, start.Y)})

	tg.run(10) // one simulated second at 10 ticks/s
	moved := d.Position.Dist(start)
	// 30 units/s, slightly reduced by accumulated fatigue.
	if moved < 29 || moved > 30.0001 {
		t.Fatalf("moved %.3f in 1s, want ~30", moved)
	}
	if d.Fatigue <= 0 {
		t.Fatal("moving must accumulate fatigue")
	}

	events := tg.runUntil(t, 200, func() bool { return d.State == StateIdle })
	if !d.Position.Equal(geom2(start.X+300, start.Y)) {
		t.Fatalf("final position %v", d.Position)
	}
	if d.CurrentOrder != nil {
		t.Fatal("order must be cleared on arrival")
	}
	found := false
	for _, e := range events {
		if du, ok := e.(DivisionUpdated); ok && du.Reason == "arrived" {
			found = true
		}
	}
	if !found {
		t.Fatal("missing division_updated(arrived)")
	}
}

func geom2(x, y float64) Position { return *pos(x, y) }

func TestTerrainSlowsDivision(t *testing.T) {
	rows := make([]string, 24)
	for i := range rows {
		rows[i] = "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
	}
	rows[2] = "PPPPPPPPPPFFFFFFFFFFFFFFFFFFFFPPPPPPPPPP"
	m, err := terrain.NewMap(rows, 50, terrain.DefaultTable(), terrain.DefaultSpawns())
	if err != nil {
		t.Fatal(err)
	}
	tg := newRunningGame(t, m, oneDivisionRules())
	d := tg.div(t, tg.p1, 0)
	d.Position = *pos(600, 125) // inside the forest row
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: d.ID, Type: OrderMove, TargetPosition: pos(1300, 125)})
	tg.run(10)
	moved := d.Position.X - 600
	if math.Abs(moved-21) > 0.5 { // 30 * 0.7
		t.Fatalf("moved %.3f in forest, want ~21", moved)
	}
}

func TestDivisionNeverLeavesMapOrEntersWater(t *testing.T) {
	tg := newRunningGame(t, defaultMap(t), DefaultRules())
	d := tg.div(t, tg.p1, 2)
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: d.ID, Type: OrderMove, TargetPosition: pos(1990, 1190)})
	for i := 0; i < 2000 && (i == 0 || d.State == StateMoving); i++ {
		tg.Tick()
		if !tg.Map.Passable(d.Position) {
			t.Fatalf("tick %d: division on impassable terrain at %v", tg.CurrentTick, d.Position)
		}
	}
	if !d.Position.Equal(geom2(1990, 1190)) {
		t.Fatalf("did not arrive: %v state=%s", d.Position, d.State)
	}
}

func TestEncounterStartsBattleAndCombatChangesStats(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	a, b := tg.div(t, tg.p1, 0), tg.div(t, tg.p2, 0)
	a.Position = *pos(900, 600)
	b.Position = *pos(1100, 600)
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: a.ID, Type: OrderMove, TargetPosition: pos(1300, 600)})

	events := tg.runUntil(t, 200, func() bool { return len(tg.Battles()) == 1 })
	if countEvents[BattleStarted](events) != 1 {
		t.Fatal("expected one battle_started")
	}
	bt := tg.Battles()[0]
	if bt.AttackerID != a.ID || bt.DefenderID != b.ID {
		t.Fatalf("moving division must be the attacker: %+v", bt)
	}
	if a.State != StateAttacking || b.State != StateDefending {
		t.Fatalf("states a=%s b=%s", a.State, b.State)
	}
	if d := a.Position.Dist(b.Position); d > tg.Rules.EngagementRange {
		t.Fatalf("battle started at distance %.1f", d)
	}
	stopped := a.Position

	unitsA, unitsB, moraleB := a.UnitCount, b.UnitCount, b.Morale
	events = tg.run(tg.Rules.CombatRoundTicks)
	if countEvents[BattleUpdated](events) != 1 {
		t.Fatalf("expected one combat round per %d ticks", tg.Rules.CombatRoundTicks)
	}
	if !a.Position.Equal(stopped) {
		t.Fatal("engaged division must not keep moving")
	}
	if a.UnitCount >= unitsA || b.UnitCount >= unitsB || b.Morale >= moraleB {
		t.Fatalf("combat did not modify stats: a=%d b=%d moraleB=%.1f", a.UnitCount, b.UnitCount, b.Morale)
	}
	if a.Experience <= 0 {
		t.Fatal("combat must grant experience")
	}
}

func TestAttackOrderChasesTarget(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	a, b := tg.div(t, tg.p1, 0), tg.div(t, tg.p2, 0)
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: a.ID, Type: OrderAttack, TargetDivisionID: b.ID})
	// Target walks away; attacker must follow and catch it (same speed,
	// but the target stops).
	tg.order(t, OrderRequest{PlayerID: tg.p2, DivisionID: b.ID, Type: OrderMove, TargetPosition: pos(1800, 300)})
	tg.runUntil(t, 3000, func() bool { return len(tg.Battles()) > 0 })
	bt := tg.Battles()[0]
	if bt.AttackerID != a.ID {
		t.Fatalf("attacker = %s, want %s", bt.AttackerID, a.ID)
	}
	if a.State != StateAttacking {
		t.Fatalf("state = %s", a.State)
	}
}

func TestDefendStanceReducesLosses(t *testing.T) {
	losses := func(defend bool) int {
		tg := newRunningGame(t, plainMap(t), oneDivisionRules())
		a, b := tg.div(t, tg.p1, 0), tg.div(t, tg.p2, 0)
		a.Position, b.Position = *pos(1000, 600), *pos(1050, 600)
		tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: a.ID, Type: OrderAttack, TargetDivisionID: b.ID})
		if defend {
			tg.order(t, OrderRequest{PlayerID: tg.p2, DivisionID: b.ID, Type: OrderDefend})
		}
		tg.run(tg.Rules.CombatRoundTicks * 3)
		return b.MaxUnitCount - b.UnitCount
	}
	if held, defended := losses(false), losses(true); defended >= held {
		t.Fatalf("DEFEND losses %d should be lower than HOLD losses %d", defended, held)
	}
}

func TestHillDefenderWins(t *testing.T) {
	rows := make([]string, 24)
	for i := range rows {
		rows[i] = "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
	}
	rows[12] = "PPPPPPPPPPPPPPPPPPPPPHHHHPPPPPPPPPPPPPPP"
	m, err := terrain.NewMap(rows, 50, terrain.DefaultTable(), terrain.DefaultSpawns())
	if err != nil {
		t.Fatal(err)
	}
	tg := newRunningGame(t, m, oneDivisionRules())
	a, b := tg.div(t, tg.p1, 0), tg.div(t, tg.p2, 0)
	a.Position, b.Position = *pos(1010, 625), *pos(1060, 625) // b on hill
	if tg.Map.TypeAt(b.Position) != terrain.Hill || tg.Map.TypeAt(a.Position) != terrain.Plain {
		t.Fatal("bad test setup")
	}
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: a.ID, Type: OrderAttack, TargetDivisionID: b.ID})
	tg.run(tg.Rules.CombatRoundTicks * 5)
	if lossA, lossB := a.MaxUnitCount-a.UnitCount, b.MaxUnitCount-b.UnitCount; lossB >= lossA {
		t.Fatalf("defender on hill lost %d, attacker on plain lost %d", lossB, lossA)
	}
}

func TestRetreatDisengages(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	a, b := tg.div(t, tg.p1, 0), tg.div(t, tg.p2, 0)
	a.Position, b.Position = *pos(1000, 600), *pos(1050, 600)
	tg.Tick()
	if len(tg.Battles()) != 1 {
		t.Fatal("expected a battle")
	}
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: a.ID, Type: OrderRetreat})
	events := tg.runUntil(t, 300, func() bool { return len(tg.Battles()) == 0 })
	var ended *BattleEnded
	for _, e := range events {
		if be, ok := e.(BattleEnded); ok {
			ended = &be
		}
	}
	if ended == nil || ended.Reason != "disengaged" || ended.WinnerDivisionID != b.ID {
		t.Fatalf("unexpected battle end: %+v", ended)
	}
	if a.State != StateRetreating {
		t.Fatalf("state = %s", a.State)
	}
	if b.State != StateIdle {
		t.Fatalf("defender should go back to IDLE, got %s", b.State)
	}
}

func TestMoraleRoutAndRally(t *testing.T) {
	r := oneDivisionRules()
	r.MoraleRecoveryPerSecond = 10
	tg := newRunningGame(t, plainMap(t), r)
	a, b := tg.div(t, tg.p1, 0), tg.div(t, tg.p2, 0)
	b.Attack = 40 // overwhelming enemy
	a.Position, b.Position = *pos(1000, 600), *pos(1050, 600)

	events := tg.runUntil(t, 2000, func() bool { return a.Routed })
	if a.State != StateRetreating || a.CurrentOrder == nil || a.CurrentOrder.Type != OrderRetreat {
		t.Fatalf("routed division must retreat: state=%s order=%+v", a.State, a.CurrentOrder)
	}
	if a.Morale > r.RoutMoraleThreshold {
		t.Fatalf("routed with morale %.1f", a.Morale)
	}
	routedEvent := false
	for _, e := range events {
		if du, ok := e.(DivisionUpdated); ok && du.DivisionID == a.ID && du.Reason == "routed" {
			routedEvent = true
		}
	}
	if !routedEvent {
		t.Fatal("missing division_updated(routed)")
	}
	tg.runUntil(t, 3000, func() bool { return !a.Routed || !a.Alive() })
	if !a.Alive() {
		t.Skip("division was destroyed before rallying")
	}
	if a.Morale < r.RallyMoraleThreshold {
		t.Fatalf("rallied with morale %.1f", a.Morale)
	}
	if _, err := tg.ValidateOrder(OrderRequest{PlayerID: tg.p1, DivisionID: a.ID, Type: OrderHold}); err != nil {
		t.Fatalf("rallied division must accept orders: %v", err)
	}
}

func TestMoraleAndFatigueRecoverAtRest(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	d := tg.div(t, tg.p1, 0)
	d.Morale, d.Fatigue = 50, 50
	tg.run(tg.Rules.TickRate * 5)
	if want := 50 + 5*tg.Rules.MoraleRecoveryPerSecond; math.Abs(d.Morale-want) > 1e-6 {
		t.Fatalf("morale %.3f, want %.3f", d.Morale, want)
	}
	if want := 50 - 5*tg.Rules.FatigueRecoveryPerSecond; math.Abs(d.Fatigue-want) > 1e-6 {
		t.Fatalf("fatigue %.3f, want %.3f", d.Fatigue, want)
	}
	d.Morale = tg.Rules.MaxMorale
	tg.run(10)
	if d.Morale > tg.Rules.MaxMorale {
		t.Fatal("morale exceeded max")
	}
}

func TestStartingCountdown(t *testing.T) {
	r := oneDivisionRules()
	r.StartCountdownTicks = 5
	tg := newRunningGame(t, plainMap(t), r)
	if tg.CurrentTick != 0 || tg.StartedAt.IsZero() {
		t.Fatalf("tick=%d startedAt=%v", tg.CurrentTick, tg.StartedAt)
	}
}
