package game

import (
	"math"
	"testing"

	"gameserver/internal/combat"
)

func TestOrderValidation(t *testing.T) {
	tg := newRunningGame(t, defaultMap(t), DefaultRules())
	own := tg.div(t, tg.p1, 0)
	own2 := tg.div(t, tg.p1, 1)
	enemy := tg.div(t, tg.p2, 0)
	dead := tg.div(t, tg.p2, 1)
	dead.State = StateDestroyed

	cases := []struct {
		name string
		req  OrderRequest
		want ErrorCode // "" = accepted
	}{
		{"move ok", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderMove, TargetPosition: pos(400, 600)}, ""},
		{"unknown type", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: "FLY"}, CodeInvalidOrderType},
		{"unknown player", OrderRequest{PlayerID: "ghost", DivisionID: own.ID, Type: OrderHold}, CodePlayerNotFound},
		{"unknown division", OrderRequest{PlayerID: tg.p1, DivisionID: "nope", Type: OrderHold}, CodeDivisionNotFound},
		{"not owner", OrderRequest{PlayerID: tg.p2, DivisionID: own.ID, Type: OrderHold}, CodeNotOwner},
		{"own destroyed", OrderRequest{PlayerID: tg.p2, DivisionID: dead.ID, Type: OrderHold}, CodeDivisionDestroyed},
		{"move without target", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderMove}, CodeTargetRequired},
		{"move outside map", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderMove, TargetPosition: pos(-10, 50)}, CodeInvalidPosition},
		{"move NaN", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderMove, TargetPosition: pos(math.NaN(), 50)}, CodeInvalidPosition},
		{"move into water", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderMove, TargetPosition: pos(975, 500)}, CodeImpassable},
		{"move across river via ford", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderMove, TargetPosition: pos(1500, 600)}, ""},
		{"attack without target", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderAttack}, CodeTargetRequired},
		{"attack missing target", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderAttack, TargetDivisionID: "nope"}, CodeTargetNotFound},
		{"attack friendly", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderAttack, TargetDivisionID: own2.ID}, CodeTargetFriendly},
		{"attack self", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderAttack, TargetDivisionID: own.ID}, CodeTargetFriendly},
		{"attack destroyed", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderAttack, TargetDivisionID: dead.ID}, CodeTargetDestroyed},
		{"attack ok", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderAttack, TargetDivisionID: enemy.ID}, ""},
		{"defend ok", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderDefend}, ""},
		{"hold ok", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderHold}, ""},
		{"retreat home ok", OrderRequest{PlayerID: tg.p1, DivisionID: own.ID, Type: OrderRetreat}, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := tg.ValidateOrder(c.req)
			if got := codeOrEmpty(err); got != c.want {
				t.Fatalf("got %q (%v), want %q", got, err, c.want)
			}
		})
	}
}

func codeOrEmpty(err error) ErrorCode {
	if err == nil {
		return ""
	}
	return CodeOf(err)
}

func TestOrdersRejectedWhenNotRunning(t *testing.T) {
	m := plainMap(t)
	r := oneDivisionRules()
	g, err := New("g", m, r, combat.NewSimpleEngine(r.Combat))
	if err != nil {
		t.Fatal(err)
	}
	p, _ := g.AddPlayer("a", "t")
	_, err = g.SubmitOrder(OrderRequest{PlayerID: p.ID, DivisionID: "division-1", Type: OrderHold})
	if CodeOf(err) != CodeGameNotRunning {
		t.Fatalf("got %v", err)
	}
}

func TestEngagedAndRoutedRestrictions(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	a, b := tg.div(t, tg.p1, 0), tg.div(t, tg.p2, 0)
	a.Position = *pos(1000, 600)
	b.Position = *pos(1040, 600)
	tg.Tick() // battle starts

	if !tg.engaged(a.ID) {
		t.Fatal("divisions in contact must be engaged")
	}
	if _, err := tg.ValidateOrder(OrderRequest{PlayerID: tg.p1, DivisionID: a.ID, Type: OrderMove, TargetPosition: pos(500, 500)}); CodeOf(err) != CodeDivisionEngaged {
		t.Fatalf("MOVE while engaged: %v", err)
	}
	for _, typ := range []OrderType{OrderRetreat, OrderDefend, OrderHold} {
		if _, err := tg.ValidateOrder(OrderRequest{PlayerID: tg.p1, DivisionID: a.ID, Type: typ}); err != nil {
			t.Fatalf("%s while engaged rejected: %v", typ, err)
		}
	}

	a.Routed = true
	if _, err := tg.ValidateOrder(OrderRequest{PlayerID: tg.p1, DivisionID: a.ID, Type: OrderDefend}); CodeOf(err) != CodeDivisionRouted {
		t.Fatalf("routed DEFEND: %v", err)
	}
	if _, err := tg.ValidateOrder(OrderRequest{PlayerID: tg.p1, DivisionID: a.ID, Type: OrderRetreat}); err != nil {
		t.Fatalf("routed RETREAT rejected: %v", err)
	}
}

func TestOrderAppliedOnNextTickAndLastWins(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	d := tg.div(t, tg.p1, 0)
	tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: d.ID, Type: OrderMove, TargetPosition: pos(600, 200)})
	last := tg.order(t, OrderRequest{PlayerID: tg.p1, DivisionID: d.ID, Type: OrderMove, TargetPosition: pos(600, 1000)})

	if d.CurrentOrder != nil || d.State != StateIdle {
		t.Fatal("order must not take effect before the next tick")
	}
	events := tg.Tick()
	if d.CurrentOrder == nil || d.CurrentOrder.ID != last.ID {
		t.Fatalf("expected last order %s to be current, got %+v", last.ID, d.CurrentOrder)
	}
	if d.State != StateMoving {
		t.Fatalf("state = %s, want MOVING", d.State)
	}
	if countEvents[DivisionUpdated](events) == 0 {
		t.Fatal("expected a division_updated event")
	}
}
