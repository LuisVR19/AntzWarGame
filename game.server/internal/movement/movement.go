package movement

import (
	"gameserver/internal/terrain"
	"gameserver/pkg/geom"
)

// StepInput describes one integration step for a moving unit.
type StepInput struct {
	Position  geom.Vec2
	Waypoints []geom.Vec2
	// Speed is the base speed in world units per second.
	Speed float64
	// Multiplier aggregates non-terrain effects (fatigue, retreat, ...).
	Multiplier float64
	// DT is the simulated time of the step in seconds.
	DT float64
}

// StepResult is the outcome of Step.
type StepResult struct {
	Position  geom.Vec2
	Waypoints []geom.Vec2
	Moved     float64
	Arrived   bool // all waypoints reached
	Blocked   bool // next position would be impassable
}

// EffectiveSpeed returns the speed (units/s) at position p.
func EffectiveSpeed(m *terrain.Map, p geom.Vec2, speed, multiplier float64) float64 {
	return speed * multiplier * m.ModifiersAt(p).Movement
}

// Step advances a unit along its waypoints. The terrain modifier is sampled
// at the unit's current position at the start of the step. The unit never
// leaves the map nor enters impassable terrain.
func Step(m *terrain.Map, in StepInput) StepResult {
	res := StepResult{Position: in.Position, Waypoints: in.Waypoints}
	if len(in.Waypoints) == 0 {
		res.Arrived = true
		return res
	}
	budget := EffectiveSpeed(m, in.Position, in.Speed, in.Multiplier) * in.DT
	if budget <= 0 {
		res.Blocked = !m.ModifiersAt(in.Position).Passable()
		return res
	}
	pos := in.Position
	wps := in.Waypoints
	// Sub-steps no longer than a quarter tile, so a fast unit can never
	// jump over a thin impassable strip.
	maxSub := m.CellSize / 4
	for budget > 1e-9 && len(wps) > 0 {
		next := pos.MoveTowards(wps[0], min(budget, maxSub))
		next = m.Clamp(next)
		if !m.Passable(next) {
			res.Blocked = true
			break
		}
		step := pos.Dist(next)
		budget -= step
		res.Moved += step
		pos = next
		if pos.Dist(wps[0]) < 1e-6 {
			wps = wps[1:]
		} else if step < 1e-9 {
			break
		}
	}
	res.Position = pos
	res.Waypoints = wps
	res.Arrived = len(wps) == 0
	return res
}
