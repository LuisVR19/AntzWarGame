// Package combat resolves engagements between two divisions. The Engine
// interface allows swapping the algorithm without touching the simulation.
package combat

import "gameserver/internal/terrain"

// Stance is the posture a combatant fights with.
type Stance string

const (
	StanceAttacking  Stance = "ATTACKING"
	StanceDefending  Stance = "DEFENDING"  // explicit DEFEND order (entrenched)
	StanceHolding    Stance = "HOLDING"    // standing still without bonus
	StanceRetreating Stance = "RETREATING" // disengaging, fights poorly
)

// Combatant is a read-only snapshot of one side of an engagement.
type Combatant struct {
	UnitCount  int
	Attack     float64
	Defense    float64
	Morale     float64 // 0..100
	Experience float64 // 0..100
	Fatigue    float64 // 0..100
	Terrain    terrain.Modifiers
	Stance     Stance
	// Formation multipliers (0 = no effect). FormationDefense already
	// depends on the side (front, flank, rear) the blow lands on.
	FormationAttack  float64
	FormationDefense float64
	// Frontage caps the soldiers that strike at once (0 = all of them).
	Frontage int
}

// FightingUnits returns the soldiers that can strike at once.
func (c Combatant) FightingUnits() int {
	if c.Frontage > 0 && c.Frontage < c.UnitCount {
		return c.Frontage
	}
	return c.UnitCount
}

// SideResult holds the deltas to apply to one combatant after a round.
type SideResult struct {
	Losses          int
	MoraleDelta     float64
	FatigueDelta    float64
	ExperienceDelta float64
	// Diagnostics, useful for clients and logs.
	EffectiveAttack  float64
	EffectiveDefense float64
}

// RoundResult is the outcome of one combat round between A and B.
type RoundResult struct {
	A, B SideResult
}

// Engine resolves one combat round. Implementations must be pure and
// deterministic given their inputs so the simulation stays reproducible.
type Engine interface {
	ResolveRound(a, b Combatant) RoundResult
	// ResolveVolley resolves a ranged shot: only the target suffers.
	ResolveVolley(shooter, target Combatant) SideResult
}
