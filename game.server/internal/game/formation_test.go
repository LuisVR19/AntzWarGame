package game

import (
	"math"
	"testing"

	"gameserver/pkg/geom"
)

func TestDeployUsesUnitTypeStatsAndDefaultFormation(t *testing.T) {
	rules := DefaultRules()
	rules.StartCountdownTicks = 0
	rules.Army = []DivisionTemplate{
		{Name: "Tanks", Type: "tank", UnitCount: 2000},
		{Name: "Fast wedge", Type: UnitScout, Formation: "wedge", UnitCount: 1000, Offset: geom.V(0, 150), Attack: 20},
	}
	tg := newRunningGame(t, plainMap(t), rules)

	tank := tg.div(t, tg.p1, 0)
	base := DefaultUnitTypes()[UnitTank]
	if tank.UnitType != UnitTank || tank.Formation != FormationLine {
		t.Fatalf("type/formation = %s/%s, want TANK/LINE", tank.UnitType, tank.Formation)
	}
	if tank.Attack != base.Attack || tank.Defense != base.Defense || tank.Speed != base.Speed || tank.Morale != base.Morale {
		t.Fatalf("tank stats %+v must come from its type %+v", tank, base)
	}
	scout := tg.div(t, tg.p1, 1)
	if scout.Formation != FormationWedge || scout.Attack != 20 || scout.Speed != DefaultUnitTypes()[UnitScout].Speed {
		t.Fatalf("template overrides and formation not applied: %+v", scout)
	}
	if tg.div(t, tg.p1, 0).Facing != 0 || tg.div(t, tg.p2, 0).Facing != math.Pi {
		t.Fatal("each side must start facing the enemy base")
	}
	if dv, _ := tg.DivisionViewFor(tg.p2, scout.ID); dv.UnitType != UnitScout || dv.Formation != FormationWedge {
		t.Fatalf("the opponent must see type and formation: %+v", dv)
	}
}

func TestRulesRejectUnknownTypeOrFormation(t *testing.T) {
	for name, mutate := range map[string]func(*Rules){
		"unknown type":       func(r *Rules) { r.Army[0].Type = "DRAGON" },
		"unknown formation":  func(r *Rules) { r.Army[0].Formation = "BLOB" },
		"bad default":        func(r *Rules) { r.FormationRules.Default = "BLOB" },
		"zero frontage":      func(r *Rules) { f := r.Formations[FormationLine]; f.Frontage = 0; r.Formations[FormationLine] = f },
		"no formations":      func(r *Rules) { r.Formations = nil },
		"broken ranged type": func(r *Rules) { r.UnitTypes[UnitArcher] = UnitType{Speed: 1, Ranged: &Ranged{}} },
	} {
		t.Run(name, func(t *testing.T) {
			r := DefaultRules()
			mutate(&r)
			if err := r.Validate(); err == nil {
				t.Fatal("expected a validation error")
			}
		})
	}
}

func TestSetFormationReorganizesAndThenIsReady(t *testing.T) {
	rules := oneDivisionRules()
	tg := newRunningGame(t, plainMap(t), rules)
	d := tg.div(t, tg.p1, 0)

	for name, c := range map[string]struct {
		id        DivisionID
		formation string
		code      ErrorCode
	}{
		"unknown":   {d.ID, "blob", CodeInvalidFormation},
		"same":      {d.ID, "line", CodeSameFormation},
		"not owner": {tg.div(t, tg.p2, 0).ID, "wedge", CodeNotOwner},
		"missing":   {"division-99", "wedge", CodeDivisionNotFound},
	} {
		if err := tg.SetFormation(tg.p1, c.id, c.formation); CodeOf(err) != c.code {
			t.Errorf("%s: got %v, want %s", name, err, c.code)
		}
	}

	if err := tg.SetFormation(tg.p1, d.ID, "shield_wall"); err != nil {
		t.Fatal(err)
	}
	if d.Formation != FormationLine {
		t.Fatal("the change must wait for the next tick")
	}
	events := tg.run(1)
	if d.Formation != FormationShieldWall || !d.Reforming() || !hasUpdate(events, d.ID, "formation_changed") {
		t.Fatalf("formation=%s reforming=%v events=%v", d.Formation, d.Reforming(), events)
	}
	changeTicks := int(rules.FormationRules.ChangeSeconds) * rules.TickRate
	events = tg.run(changeTicks)
	if d.Reforming() || !hasUpdate(events, d.ID, "formation_ready") {
		t.Fatal("the division must finish reorganizing after change_seconds")
	}
}

func TestFormationAndReorganizationChangeSpeed(t *testing.T) {
	marched := func(formation string, waitReady bool) float64 {
		tg := newRunningGame(t, plainMap(t), oneDivisionRules())
		d := tg.div(t, tg.p1, 0)
		if formation != FormationLine {
			if err := tg.SetFormation(tg.p1, d.ID, formation); err != nil {
				t.Fatal(err)
			}
			tg.run(1)
			if waitReady {
				tg.runUntil(t, 100, func() bool { return !d.Reforming() })
			}
		}
		start := d.Position
		tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: d.ID, Type: OrderMove, TargetPosition: pos(start.X, start.Y+500)})
		tg.run(10)
		return d.Position.Dist(start)
	}
	line, column, wall := marched(FormationLine, true), marched(FormationColumn, true), marched(FormationShieldWall, true)
	if !(column > line && line > wall) {
		t.Fatalf("speed order must be column > line > shield wall: %.1f %.1f %.1f", column, line, wall)
	}
	if reforming := marched(FormationColumn, false); reforming >= column {
		t.Fatalf("a reorganizing division must be slower: %.1f >= %.1f", reforming, column)
	}
}

func TestExposureDependsOnFacing(t *testing.T) {
	cases := []struct {
		facing float64
		from   Position
		want   Exposure
	}{
		{0, geom.V(10, 0), ExposureFront},
		{0, geom.V(10, 10), ExposureFront}, // 45 degrees
		{0, geom.V(0, 10), ExposureFlank},
		{0, geom.V(-10, 0), ExposureRear},
		{math.Pi, geom.V(-10, 0), ExposureFront},
		{math.Pi, geom.V(10, 1), ExposureRear}, // across the -pi/pi seam
		{0, geom.V(0, 0), ExposureFront},
	}
	for _, c := range cases {
		if got := exposureOf(c.facing, c.from); got != c.want {
			t.Errorf("exposureOf(%.2f, %+v) = %s, want %s", c.facing, c.from, got, c.want)
		}
	}
}

// contact places p2's division at the center looking west, in `formation`,
// and p1's division touching it from `from` (relative offset).
func contact(t *testing.T, formation string, from Position) (tg *testGame, a, b *Division) {
	t.Helper()
	tg = newRunningGame(t, plainMap(t), oneDivisionRules())
	a, b = tg.div(t, tg.p1, 0), tg.div(t, tg.p2, 0)
	b.Formation = formation
	b.Position, b.Facing = geom.V(1000, 600), math.Pi
	a.Position = b.Position.Add(from)
	return tg, a, b
}

// firstRoundLosses returns what p2's division loses in the first combat round.
func firstRoundLosses(t *testing.T, formation string, from Position) int {
	t.Helper()
	tg, _, b := contact(t, formation, from)
	before := b.UnitCount
	tg.runUntil(t, 3*tg.Rules.CombatRoundTicks, func() bool { return b.UnitCount < before })
	return before - b.UnitCount
}

func TestFlankAndRearAttacksHurtMore(t *testing.T) {
	// A shield wall turns slowly (20 deg/s), so it is still caught on the
	// flank or the rear at the first round; a line would already face it.
	front := firstRoundLosses(t, FormationShieldWall, geom.V(-40, 0))
	flank := firstRoundLosses(t, FormationShieldWall, geom.V(0, 40))
	rear := firstRoundLosses(t, FormationShieldWall, geom.V(40, 0))
	if !(rear > flank && flank > front) {
		t.Fatalf("losses must grow front < flank < rear: %d %d %d", front, flank, rear)
	}
}

func TestShieldWallHoldsTheFrontButNotTheRear(t *testing.T) {
	lineFront := firstRoundLosses(t, FormationLine, geom.V(-40, 0))
	wallFront := firstRoundLosses(t, FormationShieldWall, geom.V(-40, 0))
	wallRear := firstRoundLosses(t, FormationShieldWall, geom.V(40, 0))
	if wallFront >= lineFront {
		t.Fatalf("a shield wall must lose less than a line from the front: %d >= %d", wallFront, lineFront)
	}
	if wallRear <= lineFront {
		t.Fatalf("a shield wall hit from behind must suffer: %d <= %d", wallRear, lineFront)
	}
}

func TestBattleEventsReportExposure(t *testing.T) {
	tg, _, b := contact(t, FormationLine, geom.V(40, 0)) // behind b
	var started BattleStarted
	var updated BattleUpdated
	for _, e := range tg.run(tg.Rules.CombatRoundTicks + 1) {
		switch ev := e.(type) {
		case BattleStarted:
			started = ev
		case BattleUpdated:
			updated = ev
		}
	}
	side := started.DefenderExposure
	if started.AttackerID == b.ID {
		side = started.AttackerExposure
	}
	if side != ExposureRear {
		t.Fatalf("b's exposure = %s, want rear (%+v)", side, started)
	}
	if updated.Attacker.Exposure == "" || updated.Defender.Exposure == "" {
		t.Fatalf("battle_updated sides must carry exposure: %+v", updated)
	}
}

func TestEngagedDivisionTurnsAtItsFormationRate(t *testing.T) {
	tg, _, b := contact(t, FormationShieldWall, geom.V(40, 0)) // behind b
	tg.run(1)
	turned := math.Abs(angleDiff(math.Pi, b.Facing))
	maxTurn := tg.Rules.Formations[FormationShieldWall].TurnRate * math.Pi / 180 * tg.Rules.DT()
	if turned <= 0 || turned > maxTurn+1e-9 {
		t.Fatalf("turned %.4f rad in one tick, want (0, %.4f]", turned, maxTurn)
	}
	tg.run(10 * tg.Rules.TickRate)
	if math.Abs(angleDiff(b.Facing, 0)) > 0.01 {
		t.Fatalf("b must end up facing its attacker, facing=%.3f", b.Facing)
	}
}

func TestArchersShootFromRangeWithoutMelee(t *testing.T) {
	rules := DefaultRules()
	rules.StartCountdownTicks = 0
	rules.Army = []DivisionTemplate{{Name: "Archers", Type: UnitArcher, UnitCount: 1500}}
	tg := newRunningGame(t, plainMap(t), rules)
	archer, target := tg.div(t, tg.p1, 0), tg.div(t, tg.p2, 0)
	archer.Position = geom.V(800, 600)
	target.Position = geom.V(1000, 600) // 200 < range 220, far from melee
	before := target.UnitCount

	events := tg.run(2 * tg.Rules.CombatRoundTicks)
	if n := countEvents[Volley](events); n < 2 {
		t.Fatalf("expected one volley per combat round, got %d", n)
	}
	if target.UnitCount >= before || countEvents[BattleStarted](events) != 0 {
		t.Fatalf("volleys must cause losses without melee: units %d->%d", before, target.UnitCount)
	}
	if archer.Facing != 0 {
		t.Fatalf("the archers must face their target, facing=%.2f", archer.Facing)
	}

	// An ATTACK order stops the archers at range instead of closing in.
	target.Position = geom.V(1500, 600)
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: archer.ID, Type: OrderAttack, TargetDivisionID: target.ID})
	tg.runUntil(t, 400, func() bool { return archer.Position.Dist(target.Position) <= 220 })
	tg.run(20)
	if d := archer.Position.Dist(target.Position); d < 150 {
		t.Fatalf("archers closed in to %.0f instead of shooting from range", d)
	}
}

func hasUpdate(events []GameEvent, id DivisionID, reason string) bool {
	for _, e := range events {
		if u, ok := e.(DivisionUpdated); ok && u.DivisionID == id && u.Reason == reason {
			return true
		}
	}
	return false
}
