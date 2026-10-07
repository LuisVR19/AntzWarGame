package combat

import (
	"testing"

	"gameserver/internal/terrain"
)

var plain = terrain.DefaultTable().Get(terrain.Plain)

func base() Combatant {
	return Combatant{UnitCount: 3000, Attack: 10, Defense: 10, Morale: 100, Experience: 0, Fatigue: 0, Terrain: plain, Stance: StanceHolding}
}

func TestModifiers(t *testing.T) {
	if MoraleModifier(100) != 1 || MoraleModifier(0) != 0.5 {
		t.Error("morale modifier range")
	}
	if ExperienceModifier(0) != 1 || ExperienceModifier(100) != 1.5 {
		t.Error("experience modifier range")
	}
	if FatigueModifier(0) != 1 || FatigueModifier(100) != 0.7 {
		t.Error("fatigue modifier range")
	}
	if MoraleModifier(250) != 1 || MoraleModifier(-5) != 0.5 {
		t.Error("morale modifier must clamp")
	}
}

func TestEqualForcesTakeEqualLosses(t *testing.T) {
	e := NewSimpleEngine(DefaultParams())
	r := e.ResolveRound(base(), base())
	if r.A.Losses != r.B.Losses || r.A.Losses != 60 { // 3000 * 0.02 * 1
		t.Fatalf("losses A=%d B=%d, want 60/60", r.A.Losses, r.B.Losses)
	}
	if r.A.MoraleDelta >= 0 || r.A.FatigueDelta <= 0 || r.A.ExperienceDelta <= 0 {
		t.Fatalf("unexpected deltas %+v", r.A)
	}
}

func TestDeterministic(t *testing.T) {
	e := NewSimpleEngine(DefaultParams())
	a, b := base(), base()
	b.Attack = 13
	if e.ResolveRound(a, b) != e.ResolveRound(a, b) {
		t.Fatal("same inputs produced different results")
	}
}

func TestTerrainDefenseReducesLosses(t *testing.T) {
	e := NewSimpleEngine(DefaultParams())
	a, b := base(), base()
	b.Terrain = terrain.DefaultTable().Get(terrain.Hill)
	r := e.ResolveRound(a, b)
	if r.B.Losses >= r.A.Losses {
		t.Fatalf("defender on hill should lose less: A=%d B=%d", r.A.Losses, r.B.Losses)
	}
	forest := base()
	forest.Terrain = terrain.DefaultTable().Get(terrain.Forest)
	if e.EffectiveAttack(forest) >= e.EffectiveAttack(base()) {
		t.Error("forest must reduce attack")
	}
}

func TestStances(t *testing.T) {
	e := NewSimpleEngine(DefaultParams())
	def := base()
	def.Stance = StanceDefending
	if e.EffectiveDefense(def) <= e.EffectiveDefense(base()) {
		t.Error("DEFEND must increase defense")
	}
	ret := base()
	ret.Stance = StanceRetreating
	if e.EffectiveAttack(ret) >= e.EffectiveAttack(base()) || e.EffectiveDefense(ret) >= e.EffectiveDefense(base()) {
		t.Error("retreating must fight worse")
	}
	atk := base()
	atk.Stance = StanceAttacking
	if e.EffectiveAttack(atk) <= e.EffectiveAttack(base()) {
		t.Error("attacking stance must increase attack")
	}
}

func TestLowMoraleFightsWorse(t *testing.T) {
	e := NewSimpleEngine(DefaultParams())
	a, b := base(), base()
	b.Morale = 20
	r := e.ResolveRound(a, b)
	if r.B.Losses <= r.A.Losses {
		t.Fatalf("demoralized side should suffer more: A=%d B=%d", r.A.Losses, r.B.Losses)
	}
}

func TestLossesClampedAndRatioBounded(t *testing.T) {
	e := NewSimpleEngine(DefaultParams())
	a, b := base(), base()
	a.Attack = 1000
	b.UnitCount = 50
	r := e.ResolveRound(a, b)
	if r.B.Losses != 50 {
		t.Fatalf("losses must not exceed defender units, got %d", r.B.Losses)
	}
	b.UnitCount = 3000
	r = e.ResolveRound(a, b)
	if want := int(3000 * 0.02 * 4); r.B.Losses != want {
		t.Fatalf("ratio must be capped at 4: got %d want %d", r.B.Losses, want)
	}
	if lossPct := 100 * float64(r.B.Losses) / 3000; r.B.MoraleDelta != -(0.5 + 1.5*lossPct) {
		t.Fatalf("morale delta %.3f", r.B.MoraleDelta)
	}
}

func TestEngineIsReplaceable(t *testing.T) {
	var _ Engine = (*SimpleEngine)(nil)
}
