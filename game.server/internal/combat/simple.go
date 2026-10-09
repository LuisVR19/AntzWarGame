package combat

import "math"

// Params tunes SimpleEngine. All values are centralized in configuration.
type Params struct {
	// BaseCasualtyRate is the fraction of the attacker's strength inflicted
	// as casualties per round when effective attack equals effective defense.
	BaseCasualtyRate float64 `json:"base_casualty_rate"`
	// MinRatio/MaxRatio clamp the attack/defense ratio.
	MinRatio float64 `json:"min_ratio"`
	MaxRatio float64 `json:"max_ratio"`
	// MoraleLossBase is lost every round by both sides.
	MoraleLossBase float64 `json:"morale_loss_base"`
	// MoraleLossPerLossPct is morale lost per 1% of strength lost in a round.
	MoraleLossPerLossPct float64 `json:"morale_loss_per_loss_pct"`
	FatiguePerRound      float64 `json:"fatigue_per_round"`
	ExperiencePerRound   float64 `json:"experience_per_round"`
	// Stance multipliers.
	DefendDefenseBonus      float64 `json:"defend_defense_bonus"`
	AttackingAttackBonus    float64 `json:"attacking_attack_bonus"`
	RetreatingAttackFactor  float64 `json:"retreating_attack_factor"`
	RetreatingDefenseFactor float64 `json:"retreating_defense_factor"`
	// VolleyCasualtyFactor scales the casualties of a ranged volley.
	VolleyCasualtyFactor float64 `json:"volley_casualty_factor"`
}

// DefaultParams returns the default tuning.
func DefaultParams() Params {
	return Params{
		BaseCasualtyRate:        0.02,
		MinRatio:                0.25,
		MaxRatio:                4.0,
		MoraleLossBase:          0.5,
		MoraleLossPerLossPct:    1.5,
		FatiguePerRound:         1.5,
		ExperiencePerRound:      0.4,
		DefendDefenseBonus:      1.25,
		AttackingAttackBonus:    1.1,
		RetreatingAttackFactor:  0.5,
		RetreatingDefenseFactor: 0.7,
		VolleyCasualtyFactor:    0.6,
	}
}

// SimpleEngine is a deterministic, intentionally simple combat model:
//
//	effective_attack  = attack  × morale_mod × terrain_attack  × experience_mod × fatigue_mod × formation × stance
//	effective_defense = defense × morale_mod × terrain_defense × experience_mod × fatigue_mod × formation × stance
//	losses(B) = fighting(A) × base_rate × clamp(eff_attack(A) / eff_defense(B))
//
// fighting = min(units, frontage): the rest of the division is a reserve.
type SimpleEngine struct {
	P Params
}

func NewSimpleEngine(p Params) *SimpleEngine { return &SimpleEngine{P: p} }

// MoraleModifier maps morale 0..100 to 0.5..1.0.
func MoraleModifier(morale float64) float64 { return 0.5 + 0.5*clamp(morale, 0, 100)/100 }

// ExperienceModifier maps experience 0..100 to 1.0..1.5.
func ExperienceModifier(exp float64) float64 { return 1 + 0.5*clamp(exp, 0, 100)/100 }

// FatigueModifier maps fatigue 0..100 to 1.0..0.7.
func FatigueModifier(fatigue float64) float64 { return 1 - 0.3*clamp(fatigue, 0, 100)/100 }

func (e *SimpleEngine) EffectiveAttack(c Combatant) float64 {
	v := c.Attack * MoraleModifier(c.Morale) * c.Terrain.Attack * ExperienceModifier(c.Experience) * FatigueModifier(c.Fatigue)
	v *= orOne(c.FormationAttack)
	switch c.Stance {
	case StanceAttacking:
		v *= e.P.AttackingAttackBonus
	case StanceRetreating:
		v *= e.P.RetreatingAttackFactor
	}
	return v
}

func (e *SimpleEngine) EffectiveDefense(c Combatant) float64 {
	v := c.Defense * MoraleModifier(c.Morale) * c.Terrain.Defense * ExperienceModifier(c.Experience) * FatigueModifier(c.Fatigue)
	v *= orOne(c.FormationDefense)
	switch c.Stance {
	case StanceDefending:
		v *= e.P.DefendDefenseBonus
	case StanceRetreating:
		v *= e.P.RetreatingDefenseFactor
	}
	return v
}

// ResolveRound implements Engine. Both sides strike simultaneously.
func (e *SimpleEngine) ResolveRound(a, b Combatant) RoundResult {
	atkA, defA := e.EffectiveAttack(a), e.EffectiveDefense(a)
	atkB, defB := e.EffectiveAttack(b), e.EffectiveDefense(b)
	lossB := e.casualties(a.FightingUnits(), atkA, defB, b.UnitCount)
	lossA := e.casualties(b.FightingUnits(), atkB, defA, a.UnitCount)
	return RoundResult{
		A: e.side(a, lossA, atkA, defA),
		B: e.side(b, lossB, atkB, defB),
	}
}

// ResolveVolley implements Engine: casualties are scaled by
// VolleyCasualtyFactor and the target gains no fatigue or experience.
func (e *SimpleEngine) ResolveVolley(shooter, target Combatant) SideResult {
	atk, def := e.EffectiveAttack(shooter), e.EffectiveDefense(target)
	losses := e.casualties(shooter.FightingUnits(), atk*e.P.VolleyCasualtyFactor, def, target.UnitCount)
	r := e.side(target, losses, atk, def)
	r.FatigueDelta, r.ExperienceDelta = 0, 0
	return r
}

func (e *SimpleEngine) casualties(attackerUnits int, atk, def float64, defenderUnits int) int {
	if attackerUnits <= 0 || defenderUnits <= 0 || atk <= 0 {
		return 0
	}
	ratio := e.P.MaxRatio
	if def > 0 {
		ratio = clamp(atk/def, e.P.MinRatio, e.P.MaxRatio)
	}
	l := int(math.Round(float64(attackerUnits) * e.P.BaseCasualtyRate * ratio))
	if l < 1 {
		l = 1
	}
	if l > defenderUnits {
		l = defenderUnits
	}
	return l
}

func (e *SimpleEngine) side(c Combatant, losses int, atk, def float64) SideResult {
	lossPct := 0.0
	if c.UnitCount > 0 {
		lossPct = 100 * float64(losses) / float64(c.UnitCount)
	}
	return SideResult{
		Losses:           losses,
		MoraleDelta:      -(e.P.MoraleLossBase + e.P.MoraleLossPerLossPct*lossPct),
		FatigueDelta:     e.P.FatiguePerRound,
		ExperienceDelta:  e.P.ExperiencePerRound,
		EffectiveAttack:  atk,
		EffectiveDefense: def,
	}
}

func orOne(v float64) float64 {
	if v == 0 {
		return 1
	}
	return v
}

func clamp(v, lo, hi float64) float64 { return math.Max(lo, math.Min(hi, v)) }
