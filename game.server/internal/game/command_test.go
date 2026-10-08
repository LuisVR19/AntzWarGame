package game

import (
	"testing"

	"gameserver/internal/player"
)

// Default army per player (see DefaultRules):
//   0 "1st Infantry" hosts Infantry Command and reports to it
//   1 "2nd Infantry" reports to Infantry Command (hosts nothing)
//   2 "1st Armored"  hosts the general (reports to the general)
// At spawn the 2nd Infantry is 300 from its commander (comm radius 350).

func commandGame(t *testing.T) *testGame {
	t.Helper()
	return newRunningGame(t, defaultMap(t), DefaultRules())
}

func (tg *testGame) unitOf(t *testing.T, d *Division) *CommandUnit {
	t.Helper()
	for _, u := range tg.CommandUnits() {
		if u.HostDivisionID == d.ID {
			return u
		}
	}
	t.Fatalf("division %s hosts no command unit", d.ID)
	return nil
}

// moveAway places a division out of every comm radius (instantly, test only).
func moveAway(d *Division) { d.Position = Position{X: 700, Y: 600} }

func messengerEvents(events []GameEvent, status MessengerStatus) []MessengerUpdated {
	var out []MessengerUpdated
	for _, e := range events {
		if m, ok := e.(MessengerUpdated); ok && m.Status == status {
			out = append(out, m)
		}
	}
	return out
}

func TestCommandDeployment(t *testing.T) {
	tg := commandGame(t)
	if len(tg.CommandUnits()) != 4 {
		t.Fatalf("expected a general and a commander per army, got %d units", len(tg.CommandUnits()))
	}
	for _, pid := range []player.ID{tg.p1, tg.p2} {
		inf1, inf2, arm := tg.div(t, pid, 0), tg.div(t, pid, 1), tg.div(t, pid, 2)
		gen, ok := tg.General(pid)
		if !ok || gen.Role != RoleGeneral || gen.Status != CommandActive || gen.HostDivisionID != arm.ID ||
			gen.CommRadius != tg.Rules.Command.GeneralCommRadius || gen.InfluenceRadius != tg.Rules.Command.GeneralInfluenceRadius {
			t.Fatalf("general of %s: %+v", pid, gen)
		}
		cmd := tg.unitOf(t, inf1)
		if cmd.Role != RoleCommander || cmd.PlayerID != pid || cmd.CommRadius != tg.Rules.Command.CommanderCommRadius ||
			cmd.InfluenceRadius != tg.Rules.Command.CommanderInfluenceRadius {
			t.Fatalf("commander of %s: %+v", pid, cmd)
		}
		if inf1.CommanderID != cmd.ID || inf2.CommanderID != cmd.ID || arm.CommanderID != "" {
			t.Fatalf("assignments: inf1=%s inf2=%s arm=%q", inf1.CommanderID, inf2.CommanderID, arm.CommanderID)
		}
		if tg.UnitPosition(cmd) != inf1.Position {
			t.Fatal("a command unit is where its host division is")
		}
	}
}

func TestOrderInRangeIsImmediate(t *testing.T) {
	tg := commandGame(t)
	inf2 := tg.div(t, tg.p1, 1)
	if link := tg.CommandLinkOf(inf2.ID); link != LinkInRange {
		t.Fatalf("link at spawn: %s", link)
	}
	o := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderHold})
	if o.Delivery != DeliveryImmediate || o.MessengerID != "" {
		t.Fatalf("delivery %+v", o)
	}
	tg.Tick()
	if inf2.CurrentOrder != o || len(tg.Messengers()) != 0 {
		t.Fatal("an in-range order applies on the next tick, without messenger")
	}
	// The general's own division always gets its orders at once.
	arm := tg.div(t, tg.p1, 2)
	arm.Position = Position{X: 1500, Y: 600}
	if o := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: arm.ID, Type: OrderHold}); o.Delivery != DeliveryImmediate {
		t.Fatal("the general rides with this division")
	}
}

func TestOutOfRangeOrderTravelsByMessenger(t *testing.T) {
	tg := commandGame(t)
	inf2 := tg.div(t, tg.p1, 1)
	previous := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderHold})
	tg.Tick()
	moveAway(inf2)
	if link := tg.CommandLinkOf(inf2.ID); link != LinkOutOfRange {
		t.Fatalf("link far from the commander: %s", link)
	}

	o := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderDefend})
	if o.Delivery != DeliveryMessenger || o.MessengerID == "" || o.ETATicks <= 0 {
		t.Fatalf("expected a messenger: %+v", o)
	}
	m, ok := tg.PendingOrder(inf2.ID)
	if !ok || m.Order != o || m.SenderID != inf2.CommanderID || m.SentTick != tg.CurrentTick || m.Status != MessagePending {
		t.Fatalf("pending message: %+v", m)
	}
	eta := o.ETATicks
	var events []GameEvent
	for i := int64(0); i < eta+10 && len(messengerEvents(events, MessageDelivered)) == 0; i++ {
		events = append(events, tg.Tick()...)
		if len(messengerEvents(events, MessageDelivered)) == 0 && inf2.CurrentOrder != previous {
			t.Fatalf("tick %d: the division must keep its previous order while the messenger travels", tg.CurrentTick)
		}
	}
	delivered := messengerEvents(events, MessageDelivered)
	if len(delivered) != 1 || delivered[0].MessengerID != m.ID {
		t.Fatalf("delivery events: %+v", delivered)
	}
	if took := tg.CurrentTick - m.SentTick; took < eta-2 || took > eta+2 {
		t.Fatalf("delivered after %d ticks, estimated %d", took, eta)
	}
	if inf2.CurrentOrder == o {
		t.Fatal("a delivered order takes effect on the next tick, like any order")
	}
	tg.Tick()
	if inf2.CurrentOrder != o || inf2.State != StateDefending || len(tg.Messengers()) != 0 {
		t.Fatalf("after delivery: order=%v state=%s messengers=%d", inf2.CurrentOrder, inf2.State, len(tg.Messengers()))
	}
}

func TestNewOrderReplacesPendingAndDuplicatesAreIgnored(t *testing.T) {
	tg := commandGame(t)
	inf2 := tg.div(t, tg.p1, 1)
	moveAway(inf2)
	first := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderMove, TargetPosition: pos(700, 400)})
	again := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderMove, TargetPosition: pos(700, 400)})
	if again != first || len(tg.Messengers()) != 1 {
		t.Fatalf("an identical order must not send another messenger (messengers=%d)", len(tg.Messengers()))
	}
	second := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderDefend})
	cancelled := messengerEvents(tg.DrainEvents(), MessageCancelled)
	if len(cancelled) != 1 || cancelled[0].MessengerID != first.MessengerID || cancelled[0].Reason != "superseded" {
		t.Fatalf("the first message must be cancelled: %+v", cancelled)
	}
	if m, _ := tg.PendingOrder(inf2.ID); len(tg.Messengers()) != 1 || m.Order != second {
		t.Fatal("only the new order travels")
	}

	// RETREAT without destination means "home": not a duplicate of a
	// retreat elsewhere, but a duplicate of itself.
	elsewhere := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderRetreat, TargetPosition: pos(700, 400)})
	home := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderRetreat})
	if home == elsewhere || !home.TargetPosition.Equal(inf2.Home()) {
		t.Fatalf("retreat home treated as the retreat in transit: %+v", home)
	}
	if again := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderRetreat}); again != home {
		t.Fatal("a repeated retreat home must not send another messenger")
	}

	// Back in range: an immediate order cancels the message in transit.
	inf2.Position = tg.div(t, tg.p1, 0).Position.Add(Position{Y: 100})
	third := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderHold})
	if third.Delivery != DeliveryImmediate || len(tg.Messengers()) != 0 {
		t.Fatalf("immediate order must cancel the pending message: delivery=%s messengers=%d", third.Delivery, len(tg.Messengers()))
	}
}

func TestDeliveryIsValidatedAgain(t *testing.T) {
	tg := commandGame(t)
	inf2, enemy := tg.div(t, tg.p1, 1), tg.div(t, tg.p2, 0)
	moveAway(inf2)
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderAttack, TargetDivisionID: enemy.ID})
	tg.destroy(enemy, "")
	events := tg.runUntil(t, 300, func() bool { return len(tg.Messengers()) == 0 })
	cancelled := messengerEvents(events, MessageCancelled)
	if len(cancelled) != 1 || cancelled[0].Reason != string(CodeTargetDestroyed) {
		t.Fatalf("an order that became invalid on the way must be cancelled: %+v", cancelled)
	}
	if inf2.CurrentOrder != nil && inf2.CurrentOrder.Type == OrderAttack {
		t.Fatal("invalid order applied")
	}

	tg = commandGame(t)
	inf2 = tg.div(t, tg.p1, 1)
	moveAway(inf2)
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderHold})
	tg.destroy(inf2, "")
	if c := messengerEvents(tg.Tick(), MessageCancelled); len(c) != 1 || c[0].Reason != "recipient_destroyed" {
		t.Fatalf("recipient destroyed: %+v", c)
	}
}

func TestLeadershipBonusIsNeverStored(t *testing.T) {
	tg := commandGame(t)
	inf2 := tg.div(t, tg.p1, 1)
	morale := inf2.Morale
	bonus := tg.Rules.Command.LeadershipMoraleBonus
	for i := 0; i < 3; i++ {
		if got := tg.combatMorale(inf2); got != morale+bonus {
			t.Fatalf("led combat morale %.1f, want %.1f", got, morale+bonus)
		}
	}
	if inf2.Morale != morale {
		t.Fatal("the bonus must not be written to the division")
	}
	moveAway(inf2)
	if tg.led(inf2) || tg.combatMorale(inf2) != morale {
		t.Fatal("outside every influence radius there is no bonus")
	}
}

func TestCommanderDeath(t *testing.T) {
	tg := commandGame(t)
	inf1, inf2, arm := tg.div(t, tg.p1, 0), tg.div(t, tg.p1, 1), tg.div(t, tg.p1, 2)
	cmd := tg.unitOf(t, inf1)
	gen, _ := tg.General(tg.p1)

	tg.destroy(inf1, "")
	var eliminated bool
	for _, e := range tg.Tick() {
		if c, ok := e.(CommandUpdated); ok && c.UnitID == cmd.ID && c.Status == CommandEliminated && c.Reason == "host_destroyed" {
			eliminated = true
		}
	}
	if !eliminated || cmd.Status != CommandEliminated {
		t.Fatal("the commander dies with its host division")
	}
	if src, ok := tg.orderSource(inf2); !ok || src != gen {
		t.Fatalf("its divisions fall back to the general, got %+v", src)
	}
	if !inf2.Alive() || !arm.Alive() || tg.Status != StatusRunning {
		t.Fatal("other divisions are not affected")
	}
	moveAway(inf2)
	if tg.led(inf2) {
		t.Fatal("without its commander nearby the division loses the leadership bonus")
	}

	cases := []struct {
		pid  player.ID
		div  DivisionID
		unit CommandUnitID
		want ErrorCode
	}{
		{tg.p1, inf2.ID, cmd.ID, CodeCommanderInactive},
		{tg.p1, inf2.ID, "commander-99", CodeCommanderNotFound},
		{tg.p2, tg.div(t, tg.p2, 1).ID, gen.ID, CodeCommanderNotFound},
		{tg.p2, inf2.ID, gen.ID, CodeNotOwner},
		{tg.p1, inf2.ID, gen.ID, CodeCommanderOutOfRange}, // cannot skip the messenger
	}
	for _, c := range cases {
		if err := tg.AssignCommander(c.pid, c.div, c.unit); CodeOf(err) != c.want {
			t.Errorf("assign %s -> %s by %s: %v, want %s", c.div, c.unit, c.pid, err, c.want)
		}
	}
	inf2.Position = arm.Position.Add(Position{Y: 100})
	if err := tg.AssignCommander(tg.p1, inf2.ID, gen.ID); err != nil || inf2.CommanderID != gen.ID {
		t.Fatalf("assign within range: %v", err)
	}
	if events := tg.DrainEvents(); len(events) == 0 || tg.EventVisibleTo(events[len(events)-1], tg.p2) {
		t.Fatal("a reassignment is notified to its owner only")
	}
}

func TestCommanderHostCannotBeReassigned(t *testing.T) {
	tg := commandGame(t)
	inf1 := tg.div(t, tg.p1, 0)
	gen, _ := tg.General(tg.p1)
	inf1.Position = tg.div(t, tg.p1, 2).Position.Add(Position{Y: -100}) // in the general's range
	if err := tg.AssignCommander(tg.p1, inf1.ID, gen.ID); CodeOf(err) != CodeInvalidAssignment {
		t.Fatalf("host reassignment: %v", err)
	}
}

func TestGeneralDeathAndSuccession(t *testing.T) {
	r := DefaultRules()
	r.Command.SuccessionDelayTicks = 20
	tg := newRunningGame(t, defaultMap(t), r)
	inf1, inf2, arm := tg.div(t, tg.p1, 0), tg.div(t, tg.p1, 1), tg.div(t, tg.p1, 2)
	gen, _ := tg.General(tg.p1)
	cmd := tg.unitOf(t, inf1)
	tg.destroy(arm, "")
	tg.Tick()
	if gen.Status != CommandEliminated || !inf1.Alive() || !inf2.Alive() || tg.Status != StatusRunning {
		t.Fatal("the general's death must not remove the rest of the army nor end the game")
	}
	if cmd.Status != CommandActive || cmd.Role != RoleCommander {
		t.Fatal("the commander keeps commanding while the succession is pending")
	}
	tg.run(19)
	if g2, _ := tg.General(tg.p1); g2 != gen {
		t.Fatal("succession must wait for the delay")
	}
	var promoted bool
	for _, e := range tg.run(2) {
		if c, ok := e.(CommandUpdated); ok && c.Reason == "promoted" && c.UnitID == cmd.ID {
			promoted = true
		}
	}
	successor, _ := tg.General(tg.p1)
	if !promoted || successor != cmd || cmd.Role != RoleGeneral || cmd.CommRadius != tg.Rules.Command.GeneralCommRadius {
		t.Fatalf("successor: %+v", successor)
	}
	if inf2.CommanderID != cmd.ID {
		t.Fatal("the successor keeps its divisions")
	}
}

func TestIncapacitationAndNoCommand(t *testing.T) {
	tg := commandGame(t)
	inf1, inf2, arm := tg.div(t, tg.p1, 0), tg.div(t, tg.p1, 1), tg.div(t, tg.p1, 2)
	cmd := tg.unitOf(t, inf1)
	gen, _ := tg.General(tg.p1)

	// Routed host: the commander is incapacitated until it rallies.
	inf1.Morale = 10
	tg.rout(inf1)
	tg.Tick()
	if cmd.Status != CommandIncapacitated {
		t.Fatalf("routed host: %s", cmd.Status)
	}
	if src, _ := tg.orderSource(inf2); src != gen {
		t.Fatal("orders go through the general while the commander is incapacitated")
	}
	inf1.Morale = tg.Rules.RallyMoraleThreshold
	tg.Tick()
	if cmd.Status != CommandActive {
		t.Fatalf("rallied host: %s", cmd.Status)
	}

	// No commander and no general (and no successor): orders cannot reach it.
	last := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderHold})
	tg.Tick()
	tg.destroy(inf1, "")
	tg.destroy(arm, "")
	tg.run(tg.Rules.Command.SuccessionDelayTicks + 2)
	if _, err := tg.SubmitOrder(OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderDefend}); CodeOf(err) != CodeNoCommand {
		t.Fatalf("order without command: %v", err)
	}
	if inf2.CurrentOrder != last || tg.CommandLinkOf(inf2.ID) != LinkNoCommand || !inf2.Alive() {
		t.Fatal("the division keeps its last order")
	}
}

func TestCommandInformationIsPrivate(t *testing.T) {
	tg := commandGame(t)
	inf2 := tg.div(t, tg.p1, 1)
	moveAway(inf2)
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: inf2.ID, Type: OrderHold})
	events := tg.DrainEvents()
	mine, theirs := tg.ViewFor(tg.p1), tg.ViewFor(tg.p2)
	if len(mine.Messengers) != 1 || len(theirs.Messengers) != 0 {
		t.Fatalf("messengers: mine=%d theirs=%d", len(mine.Messengers), len(theirs.Messengers))
	}
	if len(theirs.CommandUnits) != 4 {
		t.Fatal("command units ride with visible divisions and are visible")
	}
	dv, _ := tg.DivisionViewFor(tg.p2, inf2.ID)
	if dv.PendingOrder != nil || dv.CommandLink != LinkNone || dv.CommanderID != "" {
		t.Fatalf("the opponent must not see command details: %+v", dv)
	}
	own, _ := tg.DivisionViewFor(tg.p1, inf2.ID)
	if own.PendingOrder == nil || own.CommandLink != LinkOutOfRange || own.CommanderID == "" {
		t.Fatalf("the owner sees its command details: %+v", own)
	}
	for _, e := range events {
		if _, ok := e.(MessengerUpdated); ok && tg.EventVisibleTo(e, tg.p2) {
			t.Fatal("messenger events are private")
		}
	}
}

func TestArmyWithoutCommandIsUnchanged(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	d := tg.div(t, tg.p1, 0)
	d.Position = Position{X: 1500, Y: 600}
	o := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: d.ID, Type: OrderHold})
	if o.Delivery != DeliveryImmediate || len(tg.CommandUnits()) != 0 || tg.CommandLinkOf(d.ID) != LinkNone || tg.led(d) {
		t.Fatal("an army without leaders has no chain of command")
	}
}

func TestChainOfCommandValidation(t *testing.T) {
	cases := map[string]func(r *Rules){
		"unknown commander":          func(r *Rules) { r.Army[1].Commander = "Ghost Command" },
		"two hosts for one unit":     func(r *Rules) { r.Army[1].Leads = "Infantry Command" },
		"commanders without general": func(r *Rules) { r.Army[2].Leads = "" },
		"host reports elsewhere": func(r *Rules) {
			r.Army[1].Leads, r.Army[1].Commander = "Second Command", "Second Command"
			r.Army[0].Commander = "Second Command"
		},
		"messenger speed 0": func(r *Rules) { r.Command.MessengerSpeed = 0 },
	}
	for name, mutate := range cases {
		r := DefaultRules()
		mutate(&r)
		if r.Validate() == nil {
			t.Errorf("%s accepted", name)
		}
	}
	if err := DefaultRules().Validate(); err != nil {
		t.Fatal(err)
	}
}
