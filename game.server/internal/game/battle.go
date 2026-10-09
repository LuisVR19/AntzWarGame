package game

import (
	"fmt"

	"gameserver/internal/combat"
	"gameserver/internal/movement"
)

// Battle is an engagement between two enemy divisions. The attacker is the
// division that initiated contact (or the first one found if neither did).
type Battle struct {
	ID             string
	AttackerID     DivisionID
	DefenderID     DivisionID
	Position       Position
	StartedTick    int64
	Rounds         int
	AttackerLosses int
	DefenderLosses int
	Active         bool
	EndedTick      int64
	EndReason      string
}

// Involves reports whether id takes part in the battle.
func (b *Battle) Involves(id DivisionID) bool { return b.AttackerID == id || b.DefenderID == id }

func (b *Battle) opponent(id DivisionID) DivisionID {
	if b.AttackerID == id {
		return b.DefenderID
	}
	return b.AttackerID
}

// engaged reports whether a division participates in any active battle.
func (g *Game) engaged(id DivisionID) bool {
	for _, b := range g.battles {
		if b.Active && b.Involves(id) {
			return true
		}
	}
	return false
}

// initiatedBattle reports whether the division is the attacker of an active battle.
func (g *Game) initiatedBattle(id DivisionID) bool {
	for _, b := range g.battles {
		if b.Active && b.AttackerID == id {
			return true
		}
	}
	return false
}

func (g *Game) battleBetween(a, b DivisionID) bool {
	for _, bt := range g.battles {
		if bt.Active && bt.Involves(a) && bt.Involves(b) {
			return true
		}
	}
	return false
}

// targets reports whether a has an ATTACK order against b.
func targets(a, b *Division) bool {
	return a.CurrentOrder != nil && a.CurrentOrder.Type == OrderAttack && a.CurrentOrder.TargetDivisionID == b.ID
}

// detectEncounters starts a battle for every pair of enemy divisions in
// contact range that are not already fighting each other.
func (g *Game) detectEncounters() {
	divs := g.divisionOrder
	for i := 0; i < len(divs); i++ {
		a := divs[i]
		if !a.Alive() {
			continue
		}
		for j := i + 1; j < len(divs); j++ {
			b := divs[j]
			if !b.Alive() || a.PlayerID == b.PlayerID {
				continue
			}
			if a.Position.Dist(b.Position) > g.Rules.EngagementRange || g.battleBetween(a.ID, b.ID) {
				continue
			}
			att, def := a, b
			switch {
			case targets(b, a) && !targets(a, b):
				att, def = b, a
			case !targets(a, b) && b.State == StateMoving && a.State != StateMoving:
				att, def = b, a
			}
			g.startBattle(att, def)
		}
	}
}

func (g *Game) startBattle(att, def *Division) {
	g.battleSeq++
	b := &Battle{
		ID:          fmt.Sprintf("battle-%d", g.battleSeq),
		AttackerID:  att.ID,
		DefenderID:  def.ID,
		Position:    att.Position.Add(def.Position).Scale(0.5),
		StartedTick: g.CurrentTick,
		Active:      true,
	}
	g.battles = append(g.battles, b)
	g.emit(BattleStarted{At: g.CurrentTick, BattleID: b.ID, AttackerID: att.ID, DefenderID: def.ID, Position: b.Position,
		AttackerExposure: g.exposure(att, def), DefenderExposure: g.exposure(def, att)})
	g.log.Info("battle started", "game_id", g.ID, "battle_id", b.ID, "attacker", att.ID, "defender", def.ID, "tick", g.CurrentTick)
	g.refreshState(att, "battle_started", false)
	g.refreshState(def, "battle_started", false)
}

// stance maps the current division state/order to a combat stance.
func (g *Game) stance(d *Division) combat.Stance {
	switch d.State {
	case StateRetreating:
		return combat.StanceRetreating
	case StateAttacking:
		return combat.StanceAttacking
	case StateDefending:
		if d.orderType() == OrderDefend {
			return combat.StanceDefending
		}
	}
	return combat.StanceHolding
}

// combatant is d fighting opponent: its formation's attack depends on the
// opponent's formation and its defense on the side the opponent hits.
func (g *Game) combatant(d, opponent *Division) combat.Combatant {
	f := g.Rules.formation(d.Formation)
	reform := 1.0
	if d.Reforming() {
		reform = g.Rules.FormationRules.ReformPenalty
	}
	return combat.Combatant{
		FormationAttack:  f.AttackVs(opponent.Formation) * reform,
		FormationDefense: f.Defense(g.exposure(d, opponent)) * reform,
		Frontage:         f.Frontage,
		UnitCount:        d.UnitCount,
		Attack:           d.Attack,
		Defense:          d.Defense,
		Morale:           g.combatMorale(d), // leadership bonus, not stored
		Experience:       d.Experience,
		Fatigue:          d.Fatigue,
		Terrain:          g.Map.ModifiersAt(d.Position),
		Stance:           g.stance(d),
	}
}

func (g *Game) applySide(d *Division, r combat.SideResult) {
	d.UnitCount -= r.Losses
	if d.UnitCount < 0 {
		d.UnitCount = 0
	}
	d.Morale = clamp(d.Morale+r.MoraleDelta, 0, g.Rules.MaxMorale)
	d.Fatigue = clamp(d.Fatigue+r.FatigueDelta, 0, 100)
	d.Experience = clamp(d.Experience+r.ExperienceDelta, 0, 100)
}

// updateBattles ends battles whose participants separated and resolves a
// combat round every CombatRoundTicks.
func (g *Game) updateBattles() {
	for _, b := range g.battles {
		if !b.Active {
			continue
		}
		att, def := g.divisions[b.AttackerID], g.divisions[b.DefenderID]
		if !att.Alive() || !def.Alive() {
			g.endBattle(b, "destroyed", survivor(att, def))
			continue
		}
		if att.Position.Dist(def.Position) > g.Rules.DisengageRange {
			g.endBattle(b, "disengaged", nonRetreating(att, def))
			continue
		}
		elapsed := g.CurrentTick - b.StartedTick
		if elapsed <= 0 || elapsed%int64(g.Rules.CombatRoundTicks) != 0 {
			continue
		}
		g.resolveRound(b, att, def)
	}
	// Compact: keep only active battles.
	active := g.battles[:0]
	for _, b := range g.battles {
		if b.Active {
			active = append(active, b)
		}
	}
	for i := len(active); i < len(g.battles); i++ {
		g.battles[i] = nil
	}
	g.battles = active
}

func (g *Game) resolveRound(b *Battle, att, def *Division) {
	attSide, defSide := g.exposure(att, def), g.exposure(def, att)
	r := g.engine.ResolveRound(g.combatant(att, def), g.combatant(def, att))
	g.applySide(att, r.A)
	g.applySide(def, r.B)
	b.Rounds++
	b.AttackerLosses += r.A.Losses
	b.DefenderLosses += r.B.Losses
	g.emit(BattleUpdated{
		At: g.CurrentTick, BattleID: b.ID, Round: b.Rounds,
		Attacker: report(att, r.A, attSide), Defender: report(def, r.B, defSide),
	})
	g.log.Debug("combat round", "game_id", g.ID, "battle_id", b.ID, "round", b.Rounds,
		"attacker_losses", r.A.Losses, "defender_losses", r.B.Losses,
		"attacker_units", att.UnitCount, "defender_units", def.UnitCount)

	for _, d := range []*Division{att, def} {
		if d.Alive() && d.UnitCount <= g.Rules.DestroyedUnitThreshold {
			g.destroy(d, b.ID)
		}
	}
	for _, d := range []*Division{att, def} {
		if d.Alive() && !d.Routed && d.Morale <= g.Rules.RoutMoraleThreshold {
			g.rout(d)
		}
	}
}

func report(d *Division, r combat.SideResult, side Exposure) BattleSideReport {
	return BattleSideReport{
		Exposure:   side,
		DivisionID: d.ID, Losses: r.Losses, UnitCount: d.UnitCount, Morale: d.Morale, Fatigue: d.Fatigue,
		EffectiveAttack: r.EffectiveAttack, EffectiveDefense: r.EffectiveDefense,
	}
}

func (g *Game) endBattle(b *Battle, reason string, winner DivisionID) {
	if !b.Active {
		return
	}
	b.Active = false
	b.EndedTick = g.CurrentTick
	b.EndReason = reason
	g.emit(BattleEnded{At: g.CurrentTick, BattleID: b.ID, AttackerID: b.AttackerID, DefenderID: b.DefenderID, Reason: reason, WinnerDivisionID: winner})
	g.log.Info("battle ended", "game_id", g.ID, "battle_id", b.ID, "reason", reason, "winner", winner, "rounds", b.Rounds)
	for _, id := range []DivisionID{b.AttackerID, b.DefenderID} {
		if d := g.divisions[id]; d.Alive() {
			g.refreshState(d, "battle_ended", false)
		}
	}
}

func (g *Game) destroy(d *Division, battleID string) {
	d.UnitCount = 0
	d.State = StateDestroyed
	d.CurrentOrder = nil
	d.path = nil
	d.Routed = false
	g.emit(DivisionDestroyed{At: g.CurrentTick, DivisionID: d.ID, PlayerID: d.PlayerID, BattleID: battleID})
	g.log.Info("division destroyed", "game_id", g.ID, "division_id", d.ID, "player_id", d.PlayerID, "tick", g.CurrentTick)
	for _, b := range g.battles {
		if b.Active && b.Involves(d.ID) {
			g.endBattle(b, "destroyed", b.opponent(d.ID))
		}
	}
}

// rout makes a division flee towards its deployment point.
func (g *Game) rout(d *Division) {
	d.Routed = true
	g.orderSeq++
	home := d.home
	d.CurrentOrder = &Order{
		ID: fmt.Sprintf("order-%d", g.orderSeq), PlayerID: d.PlayerID, DivisionID: d.ID,
		Type: OrderRetreat, TargetPosition: &home, CreatedAt: g.now(), CreatedTick: g.CurrentTick,
	}
	path, err := movement.FindPath(g.Map, d.Position, home)
	if err != nil {
		path = nil
	}
	d.path = path
	g.log.Info("division routed", "game_id", g.ID, "division_id", d.ID, "morale", d.Morale)
	g.refreshState(d, "routed", true)
}

func survivor(a, b *Division) DivisionID {
	switch {
	case a.Alive() && !b.Alive():
		return a.ID
	case b.Alive() && !a.Alive():
		return b.ID
	}
	return ""
}

func nonRetreating(a, b *Division) DivisionID {
	ar, br := a.State == StateRetreating, b.State == StateRetreating
	switch {
	case ar && !br:
		return b.ID
	case br && !ar:
		return a.ID
	}
	return ""
}
