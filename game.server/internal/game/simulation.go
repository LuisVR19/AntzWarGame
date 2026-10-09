package game

import (
	"math"

	"gameserver/internal/movement"
	"gameserver/internal/player"
)

// Tick advances the simulation by one fixed step and returns the events
// produced. Sending updates to clients (step 8) is the application layer's
// responsibility.
//
//  1. process orders and formation changes
//  2. update movement
//  3. detect encounters
//  4. update battles, facing (formations) and ranged volleys
//  5. update morale / fatigue
//  6. chain of command (command units, succession) and messengers
//  7. check victory conditions
//  8. emit events
func (g *Game) Tick() []GameEvent {
	switch g.Status {
	case StatusStarting:
		if g.countdown > 0 {
			g.countdown--
		}
		if g.countdown == 0 {
			g.Status = StatusRunning
			g.StartedAt = g.now()
			g.emit(GameStarted{At: g.CurrentTick})
			g.log.Info("game started", "game_id", g.ID)
		}
		return g.DrainEvents()
	case StatusRunning:
	default:
		return g.DrainEvents()
	}

	g.CurrentTick++
	g.processOrders()
	g.applyFormations()
	g.updateMovement()
	g.detectEncounters()
	g.updateBattles()
	g.updateFacing()
	g.updateVolleys()
	g.updateMoraleFatigue()
	g.updateCommand()
	g.updateMessengers()
	g.checkVictory()
	return g.DrainEvents()
}

// processOrders applies the orders validated since the previous tick.
func (g *Game) processOrders() {
	for _, po := range g.pending {
		o := po.order
		d := g.divisions[o.DivisionID]
		if d == nil || !d.Alive() || (d.Routed && o.Type != OrderRetreat) {
			continue
		}
		d.CurrentOrder = o
		d.path = po.path
		d.lastRepath = g.CurrentTick
		switch {
		case o.Type == OrderAttack:
			d.pathTarget = g.divisions[o.TargetDivisionID].Position
		case o.TargetPosition != nil:
			d.pathTarget = *o.TargetPosition
		}
		g.log.Info("order applied", "game_id", g.ID, "order_id", o.ID, "division_id", d.ID, "type", o.Type, "tick", g.CurrentTick)
		g.refreshState(d, "order", true)
	}
	g.pending = g.pending[:0]
}

// speedMultiplier aggregates non-terrain speed effects.
func (g *Game) speedMultiplier(d *Division) float64 {
	minF := g.Rules.MinFatigueSpeedFactor
	m := 1 - (1-minF)*clamp(d.Fatigue, 0, 100)/100
	if d.State == StateRetreating {
		m *= g.Rules.RetreatSpeedMultiplier
	}
	m *= g.Rules.formation(d.Formation).Speed
	if d.Reforming() {
		m *= g.Rules.FormationRules.ReformSpeedFactor
	}
	return m
}

// updateMovement moves every division following its order. Divisions in
// combat stay put unless they are retreating.
func (g *Game) updateMovement() {
	dt := g.Rules.DT()
	for _, d := range g.divisionOrder {
		d.movedTick = 0
		if !d.Alive() || d.CurrentOrder == nil {
			continue
		}
		if g.engaged(d.ID) && d.State != StateRetreating {
			continue
		}
		switch d.CurrentOrder.Type {
		case OrderDefend, OrderHold:
			continue
		case OrderAttack:
			t := g.divisions[d.CurrentOrder.TargetDivisionID]
			if t == nil || !t.Alive() {
				g.completeOrder(d, "target_destroyed")
				continue
			}
			// Ranged divisions stop as soon as the target is within range.
			reach := g.Rules.EngagementRange * 0.9
			if r := g.ranged(d); r != nil {
				reach = r.Range * 0.9
			}
			if d.Position.Dist(t.Position) <= reach {
				d.path = nil
				continue
			}
			// Chase: recompute the path when the target moved noticeably.
			if (len(d.path) == 0 || t.Position.Dist(d.pathTarget) > g.Map.CellSize/2) &&
				g.CurrentTick-d.lastRepath >= int64(g.Rules.PathRecomputeTicks) {
				if path, err := movement.FindPath(g.Map, d.Position, t.Position); err == nil {
					d.path, d.pathTarget, d.lastRepath = path, t.Position, g.CurrentTick
				}
			}
			if len(d.path) == 0 {
				continue
			}
		}

		res := movement.Step(g.Map, movement.StepInput{
			Position:   d.Position,
			Waypoints:  d.path,
			Speed:      d.Speed,
			Multiplier: g.speedMultiplier(d),
			DT:         dt,
		})
		if res.Moved > 0 {
			// The front looks where it marches.
			d.Facing = math.Atan2(res.Position.Y-d.Position.Y, res.Position.X-d.Position.X)
		}
		d.Position, d.path, d.movedTick = res.Position, res.Waypoints, res.Moved
		switch {
		case res.Blocked:
			g.completeOrder(d, "blocked")
		case res.Arrived && d.CurrentOrder.Type != OrderAttack:
			g.completeOrder(d, "arrived")
		}
	}
}

// completeOrder clears the current order and notifies the state change.
func (g *Game) completeOrder(d *Division, reason string) {
	d.CurrentOrder = nil
	d.path = nil
	g.refreshState(d, reason, true)
}

// updateMoraleFatigue applies per-second recovery and wear outside combat.
func (g *Game) updateMoraleFatigue() {
	dt := g.Rules.DT()
	for _, d := range g.divisionOrder {
		if !d.Alive() {
			continue
		}
		engaged := g.engaged(d.ID)
		switch {
		case d.movedTick > 0:
			d.Fatigue += g.Rules.FatigueMovePerSecond * dt
		case !engaged:
			d.Fatigue -= g.Rules.FatigueRecoveryPerSecond * dt
		}
		d.Fatigue = clamp(d.Fatigue, 0, 100)
		if !engaged {
			rate := g.Rules.MoraleRecoveryPerSecond
			if g.led(d) {
				rate *= g.Rules.Command.LeadershipRecoveryFactor
			}
			d.Morale = clamp(d.Morale+rate*dt, 0, g.Rules.MaxMorale)
		}
		if d.Routed && d.Morale >= g.Rules.RallyMoraleThreshold {
			d.Routed = false
			if len(d.path) == 0 {
				d.CurrentOrder = nil
			}
			g.log.Info("division rallied", "game_id", g.ID, "division_id", d.ID)
			g.refreshState(d, "rallied", true)
		}
	}
}

// checkVictory ends the game on annihilation, time limit or abandonment.
func (g *Game) checkVictory() {
	if g.Status != StatusRunning {
		return
	}
	if g.Rules.DisconnectGraceTicks > 0 {
		for _, pid := range g.playerOrder {
			if at, ok := g.disconnectedAt[pid]; ok && g.CurrentTick-at >= g.Rules.DisconnectGraceTicks {
				g.finish(g.opponentOf(pid), "opponent_disconnected")
				return
			}
		}
	}
	alive := map[player.ID]int{}
	strength := map[player.ID]int{}
	for _, d := range g.divisionOrder {
		if d.Alive() {
			alive[d.PlayerID]++
			strength[d.PlayerID] += d.UnitCount
		}
	}
	if len(g.playerOrder) < MaxPlayers {
		return
	}
	p0, p1 := g.playerOrder[0], g.playerOrder[1]
	a0, a1 := alive[p0], alive[p1]
	switch {
	case a0 == 0 && a1 == 0:
		g.finish("", "mutual_annihilation")
		return
	case a0 == 0:
		g.finish(p1, "annihilation")
		return
	case a1 == 0:
		g.finish(p0, "annihilation")
		return
	}
	if g.Rules.MaxDurationTicks > 0 && g.CurrentTick >= g.Rules.MaxDurationTicks {
		s0, s1 := strength[p0], strength[p1]
		switch {
		case s0 > s1:
			g.finish(p0, "time_limit")
		case s1 > s0:
			g.finish(p1, "time_limit")
		default:
			g.finish("", "time_limit")
		}
	}
}

// deriveState computes the state of a division from its order and combat.
func (g *Game) deriveState(d *Division) DivisionState {
	if !d.Alive() {
		return StateDestroyed
	}
	ot := d.orderType()
	if d.Routed || ot == OrderRetreat {
		return StateRetreating
	}
	if g.engaged(d.ID) {
		switch {
		case ot == OrderAttack || g.initiatedBattle(d.ID):
			return StateAttacking
		default:
			return StateDefending
		}
	}
	switch ot {
	case OrderAttack:
		return StateAttacking
	case OrderDefend:
		return StateDefending
	case OrderMove:
		return StateMoving
	}
	return StateIdle
}

// refreshState recomputes the state and emits DivisionUpdated if it changed
// (or always, when force is set).
func (g *Game) refreshState(d *Division, reason string, force bool) {
	s := g.deriveState(d)
	if s == d.State && !force {
		return
	}
	d.State = s
	g.emit(DivisionUpdated{At: g.CurrentTick, DivisionID: d.ID, Reason: reason})
}
