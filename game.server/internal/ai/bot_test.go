package ai

import (
	"reflect"
	"testing"

	"gameserver/internal/game"
	"gameserver/internal/player"
	"gameserver/pkg/geom"
)

const (
	botID   player.ID = "bot-1"
	humanID player.ID = "player-2"
)

var base = geom.V(1800, 600)

func newBot() *Bot { return New(botID, base, DefaultConfig(), nil) }

func division(id string, owner player.ID, x, y float64) game.DivisionView {
	return game.DivisionView{
		ID: game.DivisionID(id), PlayerID: owner, Position: geom.V(x, y),
		UnitCount: 3000, MaxUnitCount: 3000, Attack: 10, Defense: 10, Speed: 30,
		Morale: 80, State: game.StateIdle,
	}
}

func running(tick int64, divs ...game.DivisionView) game.GameView {
	return game.GameView{Status: game.StatusRunning, Tick: tick, Divisions: divs}
}

func attacking(d game.DivisionView, target string) game.DivisionView {
	d.Order = &game.OrderView{ID: "order-x", Type: game.OrderAttack, TargetDivisionID: game.DivisionID(target)}
	d.State = game.StateAttacking
	return d
}

func withOrder(d game.DivisionView, t game.OrderType) game.DivisionView {
	d.Order = &game.OrderView{ID: "order-x", Type: t}
	return d
}

// orders indexes the decisions by division.
func orders(t *testing.T, decs []Decision) map[game.DivisionID]game.OrderRequest {
	t.Helper()
	out := map[game.DivisionID]game.OrderRequest{}
	for _, d := range decs {
		if d.Assign != nil {
			continue
		}
		if d.Order.PlayerID != botID {
			t.Fatalf("order for another player: %+v", d.Order)
		}
		if d.Reason == "" {
			t.Fatalf("decision without reason: %+v", d)
		}
		if _, dup := out[d.Order.DivisionID]; dup {
			t.Fatalf("two orders for %s in one evaluation", d.Order.DivisionID)
		}
		out[d.Order.DivisionID] = d.Order
	}
	return out
}

func TestAttacksVisibleEnemy(t *testing.T) {
	b := newBot()
	got := orders(t, b.Decide(running(10, division("d1", botID, 1500, 600), division("e1", humanID, 500, 600))))
	o, ok := got["d1"]
	if !ok || o.Type != game.OrderAttack || o.TargetDivisionID != "e1" {
		t.Fatalf("want ATTACK e1, got %+v", got)
	}
	if _, ok := got["e1"]; ok {
		t.Fatal("the bot must never order enemy divisions")
	}
}

func TestDoesNotRepeatOrders(t *testing.T) {
	b := newBot()
	me, enemy := division("d1", botID, 1500, 600), division("e1", humanID, 500, 600)
	if len(b.Decide(running(10, me, enemy))) != 1 {
		t.Fatal("expected the first ATTACK")
	}
	// The division is executing the order: nothing new.
	if decs := b.Decide(running(20, attacking(me, "e1"), enemy)); len(decs) != 0 {
		t.Fatalf("order in progress was repeated: %+v", decs)
	}
	// The order is not visible yet (pending or rejected): wait for the cooldown.
	if decs := b.Decide(running(30, me, enemy)); len(decs) != 0 {
		t.Fatalf("order repeated before the cooldown: %+v", decs)
	}
	if decs := b.Decide(running(10+int64(DefaultConfig().ReissueCooldownTicks), me, enemy)); len(decs) != 1 {
		t.Fatalf("order must be retried after the cooldown, got %+v", decs)
	}
}

func TestDefendsBaseBeforeAttacking(t *testing.T) {
	b := newBot()
	got := orders(t, b.Decide(running(10,
		division("d1", botID, 1000, 600), // closer to the far enemy
		division("d2", botID, 1700, 300), // closer to the threat
		division("far", humanID, 600, 600),
		division("threat", humanID, 1600, 700),
	)))
	if got["d2"].TargetDivisionID != "threat" {
		t.Fatalf("closest division must defend the base: %+v", got)
	}
	if got["d1"].TargetDivisionID != "far" {
		t.Fatalf("one defender matches the threat, the other keeps attacking: %+v", got)
	}

	// A threat stronger than one division draws both.
	b = newBot()
	big := division("threat", humanID, 1600, 700)
	big.UnitCount, big.MaxUnitCount = 5000, 5000
	got = orders(t, b.Decide(running(10, division("d1", botID, 1000, 600), division("d2", botID, 1700, 300), division("far", humanID, 600, 600), big)))
	if got["d1"].TargetDivisionID != "threat" || got["d2"].TargetDivisionID != "threat" {
		t.Fatalf("both divisions must defend against a stronger threat: %+v", got)
	}
}

func TestWeakDivisionsRetreatAndGuard(t *testing.T) {
	b := newBot()
	enemy := division("e1", humanID, 500, 600)
	weak := division("d1", botID, 900, 600)
	weak.UnitCount = 500
	if o := orders(t, b.Decide(running(10, weak, enemy)))["d1"]; o.Type != game.OrderRetreat {
		t.Fatalf("weak division must retreat, got %+v", o)
	}
	// Already retreating: nothing new.
	if decs := b.Decide(running(20, withOrder(weak, game.OrderRetreat), enemy)); len(decs) != 0 {
		t.Fatalf("retreat repeated: %+v", decs)
	}
	// Retreat finished (order cleared): guard instead of retreating again.
	if o := orders(t, b.Decide(running(30, weak, enemy)))["d1"]; o.Type != game.OrderDefend {
		t.Fatalf("after retreating the division guards, got %+v", o)
	}

	// Engaged and weak: disengage.
	b = newBot()
	engaged := weak
	engaged.InBattle = true
	if o := orders(t, b.Decide(running(10, engaged, enemy)))["d1"]; o.Type != game.OrderRetreat {
		t.Fatalf("engaged weak division must retreat, got %+v", o)
	}

	// Weak but already at home: defend there.
	b = newBot()
	home := division("d1", botID, base.X, base.Y)
	home.UnitCount = 500
	if o := orders(t, b.Decide(running(10, home, enemy)))["d1"]; o.Type != game.OrderDefend {
		t.Fatalf("weak division at home must defend, got %+v", o)
	}
}

func TestLowMoraleHysteresis(t *testing.T) {
	b := newBot()
	enemy := division("e1", humanID, 500, 600)
	d := division("d1", botID, 900, 600)
	d.Morale = 25
	if o := orders(t, b.Decide(running(10, d, enemy)))["d1"]; o.Type != game.OrderRetreat {
		t.Fatalf("low morale must retreat, got %+v", o)
	}
	d.Morale = 45 // above retreat_morale but below recover_morale
	if o, ok := orders(t, b.Decide(running(100, withOrder(d, game.OrderRetreat), enemy)))["d1"]; ok {
		t.Fatalf("recovering division must not attack yet, got %+v", o)
	}
	d.Morale = 65
	if o := orders(t, b.Decide(running(200, d, enemy)))["d1"]; o.Type != game.OrderAttack {
		t.Fatalf("recovered division must attack again, got %+v", o)
	}
}

func TestRegroupsWhenOutmatched(t *testing.T) {
	b := newBot()
	strong := division("e1", humanID, 300, 600)
	strong.UnitCount, strong.MaxUnitCount = 9000, 9000
	got := orders(t, b.Decide(running(10, division("d1", botID, 1000, 200), division("d2", botID, 1300, 1000), strong)))
	o := got["d1"]
	if o.Type != game.OrderMove || o.TargetPosition == nil || !o.TargetPosition.Equal(geom.V(1300, 1000)) {
		t.Fatalf("isolated division must regroup with the ally closer to the base, got %+v", got)
	}
	if got["d2"].Type != game.OrderDefend {
		t.Fatalf("the ally closest to the base waits for the group, got %+v", got)
	}

	// Alone and outmatched: hold.
	b = newBot()
	got = orders(t, b.Decide(running(10, division("d1", botID, 1000, 200), strong)))
	if got["d1"].Type != game.OrderDefend {
		t.Fatalf("lonely outmatched division must hold, got %+v", got)
	}

	// Together the group has the odds: attack.
	b = newBot()
	medium := strong
	medium.UnitCount, medium.MaxUnitCount = 5000, 5000
	got = orders(t, b.Decide(running(10, division("d1", botID, 1000, 500), division("d2", botID, 1000, 700), medium)))
	if got["d1"].Type != game.OrderAttack || got["d2"].Type != game.OrderAttack {
		t.Fatalf("grouped divisions must attack together, got %+v", got)
	}
}

func TestCommittedAttackHysteresis(t *testing.T) {
	b := newBot()
	enemy := division("e1", humanID, 600, 600)
	enemy.UnitCount, enemy.MaxUnitCount = 4500, 4500 // odds 0.67 for a lone division
	me := division("d1", botID, 1000, 600)
	if got := orders(t, b.Decide(running(10, me, enemy))); got["d1"].Type == game.OrderAttack {
		t.Fatalf("odds below min_attack_odds must not start an attack, got %+v", got)
	}
	b = newBot()
	if decs := b.Decide(running(10, attacking(me, "e1"), enemy)); len(decs) != 0 {
		t.Fatalf("an attack in progress continues while odds stay above keep_attack_odds: %+v", decs)
	}
	enemy.UnitCount, enemy.MaxUnitCount = 9000, 9000 // odds 0.33
	if got := orders(t, b.Decide(running(20, attacking(me, "e1"), enemy))); got["d1"].Type == game.OrderAttack || len(got) == 0 {
		t.Fatalf("hopeless attack must be abandoned, got %+v", got)
	}
}

func TestSpreadsAttackers(t *testing.T) {
	b := newBot()
	got := orders(t, b.Decide(running(10,
		division("d1", botID, 1000, 500), division("d2", botID, 1000, 600), division("d3", botID, 1000, 700),
		division("e1", humanID, 600, 600), division("e2", humanID, 600, 900),
	)))
	count := map[game.DivisionID]int{}
	for _, o := range got {
		count[o.TargetDivisionID]++
	}
	if len(count) != 2 || count["e1"] > 2 || count["e2"] > 2 {
		t.Fatalf("attackers must be spread (max 2 per target): %+v", count)
	}
}

func TestKeepsTargetUnlessClearlyBetter(t *testing.T) {
	b := newBot()
	me := attacking(division("d1", botID, 1000, 600), "e1")
	e1, e2 := division("e1", humanID, 500, 600), division("e2", humanID, 600, 600)
	if decs := b.Decide(running(10, me, e1, e2)); len(decs) != 0 {
		t.Fatalf("slightly better target must not cause a switch: %+v", decs)
	}
	e2.UnitCount = 600 // much weaker: clearly better
	got := orders(t, b.Decide(running(20, me, e1, e2)))
	if got["d1"].TargetDivisionID != "e2" {
		t.Fatalf("clearly better target must be chosen, got %+v", got)
	}
}

func TestOnlyUsesVisibleInformation(t *testing.T) {
	b := newBot()
	// No visible enemy: hold the position once, then nothing.
	me := division("d1", botID, 1500, 600)
	got := orders(t, b.Decide(running(10, me)))
	if got["d1"].Type != game.OrderDefend {
		t.Fatalf("without visible enemies the division holds, got %+v", got)
	}
	if decs := b.Decide(running(20, withOrder(me, game.OrderDefend))); len(decs) != 0 {
		t.Fatalf("holding division got new orders: %+v", decs)
	}
}

func TestLeavesRoutedAndEngagedDivisionsAlone(t *testing.T) {
	b := newBot()
	routed := division("d1", botID, 1000, 600)
	routed.Routed = true
	engaged := attacking(division("d2", botID, 600, 600), "e1")
	engaged.InBattle = true
	if decs := b.Decide(running(10, routed, engaged, division("e1", humanID, 560, 600))); len(decs) != 0 {
		t.Fatalf("routed/engaged divisions must not get orders: %+v", decs)
	}
}

func TestStopsWhenGameIsNotRunning(t *testing.T) {
	b := newBot()
	v := running(10, division("d1", botID, 1500, 600), division("e1", humanID, 500, 600))
	for _, st := range []game.Status{game.StatusWaiting, game.StatusStarting, game.StatusFinished} {
		v.Status = st
		if decs := b.Decide(v); decs != nil {
			t.Fatalf("decisions while %s: %+v", st, decs)
		}
	}
}

func TestDueAndDeterminism(t *testing.T) {
	b := newBot()
	if !b.Due(0) {
		t.Fatal("first evaluation must be due")
	}
	v := running(100,
		division("d1", botID, 1000, 500), division("d2", botID, 1000, 600), division("d3", botID, 1700, 600),
		division("e1", humanID, 600, 600), division("e2", humanID, 1550, 650),
	)
	first := b.Decide(v)
	if b.Due(105) || !b.Due(110) {
		t.Fatal("evaluations must follow decision_interval_ticks")
	}
	if second := newBot().Decide(v); !reflect.DeepEqual(first, second) {
		t.Fatalf("same view, different decisions:\n%+v\n%+v", first, second)
	}
}

func TestConfigValidate(t *testing.T) {
	if err := DefaultConfig().Validate(); err != nil {
		t.Fatal(err)
	}
	c := DefaultConfig()
	c.DecisionIntervalTicks = 0
	if c.Validate() == nil {
		t.Fatal("decision_interval_ticks 0 accepted")
	}
	c = DefaultConfig()
	c.RecoverMorale = c.RetreatMorale - 1
	if c.Validate() == nil {
		t.Fatal("recover_morale < retreat_morale accepted")
	}
}

func TestRespectsChainOfCommand(t *testing.T) {
	enemy := division("e1", humanID, 500, 600)
	enemy2 := division("e2", humanID, 600, 600)
	enemy2.UnitCount = 600 // a clearly better target

	// Out of range with an order: a non-urgent change would cost a messenger.
	b := newBot()
	far := attacking(division("d1", botID, 1000, 600), "e1")
	far.CommandLink = game.LinkOutOfRange
	if decs := b.Decide(running(10, far, enemy, enemy2)); len(decs) != 0 {
		t.Fatalf("out-of-range division must keep its order: %+v", decs)
	}
	// In range, the same situation changes target.
	b = newBot()
	near := far
	near.CommandLink = game.LinkInRange
	if got := orders(t, b.Decide(running(10, near, enemy, enemy2))); got["d1"].TargetDivisionID != "e2" {
		t.Fatalf("in-range division retargets: %+v", got)
	}
	// Urgent orders (retreat) still go out by messenger.
	b = newBot()
	weak := far
	weak.UnitCount = 500
	if got := orders(t, b.Decide(running(10, weak, enemy))); got["d1"].Type != game.OrderRetreat {
		t.Fatalf("weak out-of-range division must still retreat: %+v", got)
	}
	// No command: nobody can transmit orders to it.
	b = newBot()
	lost := division("d1", botID, 1000, 600)
	lost.CommandLink = game.LinkNoCommand
	if decs := b.Decide(running(10, lost, enemy)); len(decs) != 0 {
		t.Fatalf("division without command got orders: %+v", decs)
	}
	// An order carried by a messenger is not sent again.
	b = newBot()
	waiting := division("d1", botID, 1000, 600)
	waiting.CommandLink = game.LinkOutOfRange
	waiting.PendingOrder = &game.PendingOrderView{MessengerID: "messenger-1", Order: game.OrderView{Type: game.OrderAttack, TargetDivisionID: "e1"}, ETATicks: 80}
	if decs := b.Decide(running(10, waiting, enemy)); len(decs) != 0 {
		t.Fatalf("pending order repeated: %+v", decs)
	}
}

func TestReassignsDivisionsOfEliminatedCommander(t *testing.T) {
	b := newBot()
	orphan := division("d1", botID, 1000, 600)
	orphan.CommanderID = "commander-1"
	units := []game.CommandUnitView{
		{ID: "commander-1", PlayerID: botID, Role: game.RoleCommander, HostDivisionID: "dead", Status: game.CommandEliminated},
		{ID: "commander-2", PlayerID: botID, Role: game.RoleCommander, HostDivisionID: "d2", Position: geom.V(1100, 600), Status: game.CommandActive, CommRadius: 350},
		{ID: "commander-3", PlayerID: botID, Role: game.RoleCommander, HostDivisionID: "d3", Position: geom.V(1700, 600), Status: game.CommandActive, CommRadius: 350},
		{ID: "commander-9", PlayerID: humanID, Role: game.RoleCommander, HostDivisionID: "e1", Position: geom.V(1000, 650), Status: game.CommandActive, CommRadius: 350},
	}
	v := running(10, orphan, division("d2", botID, 1100, 600), division("d3", botID, 1700, 600), division("e1", humanID, 300, 600))
	v.CommandUnits = units
	var assign *Assignment
	for _, d := range b.Decide(v) {
		if d.Assign != nil {
			assign = d.Assign
		}
	}
	if assign == nil || assign.DivisionID != "d1" || assign.CommanderID != "commander-2" {
		t.Fatalf("orphan must go to the nearest own active commander: %+v", assign)
	}
	v.Tick = 20
	for _, d := range b.Decide(v) {
		if d.Assign != nil {
			t.Fatal("reassignment repeated")
		}
	}
	// No commander within range: nothing (it reports to the general).
	b = newBot()
	v.Divisions[0].Position = geom.V(300, 600)
	for _, d := range b.Decide(v) {
		if d.Assign != nil {
			t.Fatalf("reassignment to an out-of-range commander: %+v", d.Assign)
		}
	}
}
