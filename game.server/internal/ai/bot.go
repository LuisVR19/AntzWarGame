package ai

import (
	"cmp"
	"fmt"
	"io"
	"log/slog"
	"slices"

	"gameserver/internal/game"
	"gameserver/internal/player"
)

// distanceScale softens the preference for close targets when scoring:
// a target this far away scores half as much as an adjacent one.
const distanceScale = 1000.0

// Decision is an order chosen by the bot and the main reason behind it.
type Decision struct {
	Order  game.OrderRequest
	Reason string
}

// Bot is a deterministic rule-based player:
//
//  1. weak divisions (few troops or low morale) retreat to the base and
//     guard it; routed and engaged divisions are left alone
//  2. enemies near the base are attacked first, with enough power to match
//     them (defense)
//  3. the rest attack visible enemies, spread over several targets, only
//     with acceptable odds; otherwise they fall back to the nearest ally
//     closer to the base or hold their position
//
// It only reads the GameView of its own player, so it knows exactly what a
// human in its place would know. Orders already being executed, or sent
// recently, are not repeated.
//
// A Bot is not safe for concurrent use; the Room goroutine owns it.
type Bot struct {
	id   player.ID
	base game.Position
	cfg  Config
	log  *slog.Logger

	lastDecision int64
	// issued remembers the last order sent to each division.
	issued map[game.DivisionID]issuedOrder
	// recovering marks divisions that retreated for low morale and must
	// reach cfg.RecoverMorale before fighting again.
	recovering map[game.DivisionID]bool
	defending  bool
}

type issuedOrder struct {
	req  game.OrderRequest
	tick int64
}

// New creates a bot for player id whose base is its deployment point.
func New(id player.ID, base game.Position, cfg Config, log *slog.Logger) *Bot {
	if log == nil {
		log = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	return &Bot{
		id: id, base: base, cfg: cfg, log: log,
		lastDecision: -1,
		issued:       make(map[game.DivisionID]issuedOrder),
		recovering:   make(map[game.DivisionID]bool),
	}
}

// PlayerID returns the player controlled by the bot.
func (b *Bot) PlayerID() player.ID { return b.id }

// Due reports whether the bot should evaluate the battle at tick.
func (b *Bot) Due(tick int64) bool {
	return b.lastDecision < 0 || tick-b.lastDecision >= int64(b.cfg.DecisionIntervalTicks)
}

// plan accumulates the decisions of one evaluation.
type plan struct {
	tick      int64
	decisions []Decision
	// busy divisions already have a role in this evaluation.
	busy map[game.DivisionID]bool
	// sent is the power and number of divisions sent against each enemy.
	sent  map[game.DivisionID]float64
	count map[game.DivisionID]int
}

// Decide evaluates v, which must be Game.ViewFor(b.PlayerID()), and returns
// the new orders. It returns nothing unless the game is RUNNING.
func (b *Bot) Decide(v game.GameView) []Decision {
	if v.Status != game.StatusRunning {
		return nil
	}
	b.lastDecision = v.Tick
	var own, enemies []game.DivisionView
	for _, d := range v.Divisions {
		switch {
		case d.State == game.StateDestroyed:
		case d.PlayerID == b.id:
			own = append(own, d)
		default:
			enemies = append(enemies, d)
		}
	}
	p := &plan{
		tick:  v.Tick,
		busy:  make(map[game.DivisionID]bool),
		sent:  make(map[game.DivisionID]float64),
		count: make(map[game.DivisionID]int),
	}

	// 1. Weak divisions withdraw; routed and engaged ones are left alone.
	var available []game.DivisionView
	for _, d := range own {
		switch {
		case d.Routed:
			// Routed divisions retreat on their own and only accept RETREAT.
		case b.weak(d):
			b.withdraw(p, d)
		case d.InBattle:
			// Keep fighting: MOVE and ATTACK are not allowed in combat.
		default:
			available = append(available, d)
		}
	}

	// 2. Defense: enemies close to the base are attacked first.
	threats := b.threats(enemies)
	if defending := len(threats) > 0; defending != b.defending {
		b.defending = defending
		mode := "attack"
		if defending {
			mode = "defend"
		}
		b.log.Info("ai mode changed", "tick", v.Tick, "player_id", b.id, "mode", mode, "threats", len(threats))
	}
	for _, t := range threats {
		need := power(t)
		for _, d := range byDistance(available, t.Position) {
			if p.sent[t.ID] >= need {
				break
			}
			if !p.busy[d.ID] {
				b.attack(p, d, t, fmt.Sprintf("defend base: %s is %.0f from the base", t.ID, t.Position.Dist(b.base)))
			}
		}
		if p.sent[t.ID] >= need {
			// Matched: the rest of the army does not pile on it.
			p.count[t.ID] = max(p.count[t.ID], b.cfg.MaxAttackersPerTarget)
		}
	}

	// 3. Attack, regroup or hold.
	for _, d := range available {
		if !p.busy[d.ID] {
			b.engage(p, d, own, enemies)
		}
	}

	for _, dec := range p.decisions {
		b.logDecision(v.Tick, dec)
	}
	return p.decisions
}

// weak reports whether d should stop fighting. Losing troops is permanent;
// low morale lasts until the division recovers cfg.RecoverMorale.
func (b *Bot) weak(d game.DivisionView) bool {
	if d.MaxUnitCount > 0 && float64(d.UnitCount)/float64(d.MaxUnitCount) < b.cfg.RetreatStrengthRatio {
		return true
	}
	if b.recovering[d.ID] {
		if d.Morale >= b.cfg.RecoverMorale {
			delete(b.recovering, d.ID)
			return false
		}
		return true
	}
	if d.Morale < b.cfg.RetreatMorale {
		b.recovering[d.ID] = true
		return true
	}
	return false
}

// withdraw retreats a weak division to its base, or keeps it guarding once
// it is there (or has already completed a retreat).
func (b *Bot) withdraw(p *plan, d game.DivisionView) {
	reason := fmt.Sprintf("weak (%d/%d troops, morale %.0f)", d.UnitCount, d.MaxUnitCount, d.Morale)
	last, retreated := b.issued[d.ID]
	retreated = retreated && last.req.Type == game.OrderRetreat && d.Order == nil
	switch {
	case d.InBattle:
		b.propose(p, d, game.OrderRequest{Type: game.OrderRetreat}, reason+": disengage and retreat to base")
	case d.Order != nil && d.Order.Type == game.OrderRetreat:
		p.busy[d.ID] = true // already on its way
	case retreated || d.Position.Dist(b.base) <= b.cfg.HomeRadius:
		b.propose(p, d, game.OrderRequest{Type: game.OrderDefend}, reason+": guard the base")
	default:
		b.propose(p, d, game.OrderRequest{Type: game.OrderRetreat}, reason+": retreat to base")
	}
}

// threats returns the enemies inside the base threat radius, closest first.
func (b *Bot) threats(enemies []game.DivisionView) []game.DivisionView {
	var out []game.DivisionView
	for _, e := range enemies {
		if e.Position.Dist(b.base) <= b.cfg.BaseThreatRadius {
			out = append(out, e)
		}
	}
	return byDistance(out, b.base)
}

// engage attacks the best target if the odds are acceptable; otherwise the
// division regroups with the nearest ally closer to the base (the one
// closest to the base holds and waits for the others) or holds its ground.
func (b *Bot) engage(p *plan, d game.DivisionView, own, enemies []game.DivisionView) {
	t, ok := b.pickTarget(p, d, enemies)
	if !ok {
		if d.Order == nil {
			b.propose(p, d, game.OrderRequest{Type: game.OrderDefend}, "no visible enemy: hold position")
		}
		p.busy[d.ID] = true
		return
	}
	// Allies close by fight alongside, so they count for the odds.
	group := power(d) + p.sent[t.ID]
	nearby := 0
	var rally *game.DivisionView
	for i := range own {
		a := &own[i]
		if a.ID == d.ID || a.Routed {
			continue
		}
		dist := a.Position.Dist(d.Position)
		if dist <= b.cfg.RegroupRadius {
			group += power(*a)
			nearby++
		}
		if a.Position.Dist(b.base) < d.Position.Dist(b.base) && (rally == nil || dist < rally.Position.Dist(d.Position)) {
			rally = a
		}
	}
	odds := group / power(t)
	dist := d.Position.Dist(t.Position)
	threshold := b.cfg.MinAttackOdds
	if d.Order != nil && d.Order.Type == game.OrderAttack && d.Order.TargetDivisionID == t.ID {
		threshold = b.cfg.KeepAttackOdds
	}
	switch {
	case odds >= threshold:
		reason := fmt.Sprintf("attack %s: odds %.2f, distance %.0f", t.ID, odds, dist)
		if nearby > 0 {
			reason += fmt.Sprintf(", %d allies nearby", nearby)
		}
		b.attack(p, d, t, reason)
	case rally != nil && rally.Position.Dist(d.Position) > b.cfg.RegroupRadius:
		pos := rally.Position
		b.propose(p, d, game.OrderRequest{Type: game.OrderMove, TargetPosition: &pos},
			fmt.Sprintf("regroup with %s: odds %.2f against %s", rally.ID, odds, t.ID))
	default:
		b.propose(p, d, game.OrderRequest{Type: game.OrderDefend},
			fmt.Sprintf("outmatched by %s (odds %.2f): hold position", t.ID, odds))
	}
}

// pickTarget chooses the enemy with the best odds/distance score, avoiding
// targets that already have cfg.MaxAttackersPerTarget attackers while there
// are others. The current target is kept unless another is clearly better.
func (b *Bot) pickTarget(p *plan, d game.DivisionView, enemies []game.DivisionView) (game.DivisionView, bool) {
	saturated := true
	for _, e := range enemies {
		if p.count[e.ID] < b.cfg.MaxAttackersPerTarget {
			saturated = false
			break
		}
	}
	var best game.DivisionView
	bestScore, found := 0.0, false
	for _, e := range enemies {
		if !saturated && p.count[e.ID] >= b.cfg.MaxAttackersPerTarget {
			continue
		}
		if s := b.score(p, d, e); !found || s > bestScore {
			best, bestScore, found = e, s, true
		}
	}
	if !found {
		return best, false
	}
	if d.Order != nil && d.Order.Type == game.OrderAttack && d.Order.TargetDivisionID != best.ID {
		for _, e := range enemies {
			if e.ID == d.Order.TargetDivisionID && bestScore < b.score(p, d, e)*b.cfg.TargetSwitchFactor {
				return e, true
			}
		}
	}
	return best, true
}

func (b *Bot) score(p *plan, d, e game.DivisionView) float64 {
	odds := (power(d) + p.sent[e.ID]) / power(e)
	return odds / (1 + d.Position.Dist(e.Position)/distanceScale)
}

func (b *Bot) attack(p *plan, d, t game.DivisionView, reason string) {
	p.sent[t.ID] += power(d)
	p.count[t.ID]++
	b.propose(p, d, game.OrderRequest{Type: game.OrderAttack, TargetDivisionID: t.ID}, reason)
}

// propose gives d a role and emits req unless the division is already
// executing it or it was sent less than cfg.ReissueCooldownTicks ago.
func (b *Bot) propose(p *plan, d game.DivisionView, req game.OrderRequest, reason string) {
	p.busy[d.ID] = true
	req.PlayerID, req.DivisionID = b.id, d.ID
	if b.executing(d, req) {
		return
	}
	if last, ok := b.issued[d.ID]; ok && b.sameOrder(last.req, req) && p.tick-last.tick < int64(b.cfg.ReissueCooldownTicks) {
		return
	}
	b.issued[d.ID] = issuedOrder{req: req, tick: p.tick}
	p.decisions = append(p.decisions, Decision{Order: req, Reason: reason})
}

// executing reports whether the division's current order already is req.
func (b *Bot) executing(d game.DivisionView, req game.OrderRequest) bool {
	o := d.Order
	if o == nil || o.Type != req.Type {
		return false
	}
	switch req.Type {
	case game.OrderAttack:
		return o.TargetDivisionID == req.TargetDivisionID
	case game.OrderMove:
		return o.TargetPosition != nil && req.TargetPosition != nil &&
			o.TargetPosition.Dist(*req.TargetPosition) <= b.cfg.MoveTolerance
	}
	return true // DEFEND, HOLD and RETREAT to base have no parameters.
}

func (b *Bot) sameOrder(a, c game.OrderRequest) bool {
	if a.Type != c.Type || a.TargetDivisionID != c.TargetDivisionID {
		return false
	}
	if a.TargetPosition == nil || c.TargetPosition == nil {
		return a.TargetPosition == nil && c.TargetPosition == nil
	}
	return a.TargetPosition.Dist(*c.TargetPosition) <= b.cfg.MoveTolerance
}

func (b *Bot) logDecision(tick int64, dec Decision) {
	o := dec.Order
	attrs := []any{"tick", tick, "player_id", b.id, "division_id", o.DivisionID, "action", o.Type, "reason", dec.Reason}
	if o.TargetDivisionID != "" {
		attrs = append(attrs, "target_division_id", o.TargetDivisionID)
	}
	if o.TargetPosition != nil {
		attrs = append(attrs, "x", o.TargetPosition.X, "y", o.TargetPosition.Y)
	}
	b.log.Info("ai decision", attrs...)
}

// power estimates the fighting value of a division from what is visible.
func power(d game.DivisionView) float64 {
	morale := 0.5 + clamp01(d.Morale/100)/2
	fatigue := 1 - clamp01(d.Fatigue/100)/2
	return max(float64(d.UnitCount)*(d.Attack+d.Defense)/2*morale*fatigue, 1)
}

func clamp01(v float64) float64 { return min(max(v, 0), 1) }

// byDistance returns a copy of divs sorted by distance to p (stable, so
// ties keep the view's deterministic order).
func byDistance(divs []game.DivisionView, p game.Position) []game.DivisionView {
	out := slices.Clone(divs)
	slices.SortStableFunc(out, func(a, b game.DivisionView) int {
		return cmp.Compare(a.Position.Dist(p), b.Position.Dist(p))
	})
	return out
}
