package game

import (
	"time"

	"gameserver/internal/player"
	"gameserver/internal/terrain"
)

// Spectator is the viewer ID used for omniscient views (HTTP, logs, tests).
const Spectator player.ID = ""

// VisibilityPolicy decides what each player may know. Every piece of state
// sent to a client goes through it, so fog of war can be added later by
// providing a different implementation without touching the network layer.
type VisibilityPolicy interface {
	CanSee(g *Game, viewer player.ID, d *Division) bool
}

// FullVisibility shows every division to everyone (no fog of war, MVP).
type FullVisibility struct{}

func (FullVisibility) CanSee(*Game, player.ID, *Division) bool { return true }

// OrderView is the public representation of an order.
type OrderView struct {
	ID               string
	Type             OrderType
	TargetPosition   *Position
	TargetDivisionID DivisionID
}

// DivisionView is what a viewer knows about a division.
type DivisionView struct {
	ID           DivisionID
	PlayerID     player.ID
	Name         string
	Position     Position
	UnitCount    int
	MaxUnitCount int
	Attack       float64
	Defense      float64
	Speed        float64
	Morale       float64
	Experience   float64
	Fatigue      float64
	State        DivisionState
	Routed       bool
	InBattle     bool
	Terrain      terrain.Type
	// Owner-only information (nil for opponents).
	Order *OrderView
	Path  []Position
}

// BattleView is the public representation of an active battle.
type BattleView struct {
	ID             string
	AttackerID     DivisionID
	DefenderID     DivisionID
	Position       Position
	StartedTick    int64
	Rounds         int
	AttackerLosses int
	DefenderLosses int
}

// PlayerView is the public representation of a player.
type PlayerView struct {
	ID        player.ID
	Name      string
	Side      player.Side
	Ready     bool
	Connected bool
}

// GameView is a snapshot of the game as seen by one viewer.
type GameView struct {
	ID             string
	Status         Status
	Tick           int64
	CountdownTicks int
	CreatedAt      time.Time
	StartedAt      time.Time
	Players        []PlayerView
	Divisions      []DivisionView
	Battles        []BattleView
	WinnerID       player.ID
	FinishReason   string
}

// ViewFor builds the snapshot a viewer is allowed to see.
func (g *Game) ViewFor(viewer player.ID) GameView {
	v := GameView{
		ID:             g.ID,
		Status:         g.Status,
		Tick:           g.CurrentTick,
		CountdownTicks: g.countdown,
		CreatedAt:      g.CreatedAt,
		StartedAt:      g.StartedAt,
		WinnerID:       g.WinnerID,
		FinishReason:   g.FinishReason,
	}
	for _, p := range g.Players() {
		v.Players = append(v.Players, PlayerView{ID: p.ID, Name: p.Name, Side: p.Side, Ready: p.Ready, Connected: p.Connected})
	}
	for _, d := range g.divisionOrder {
		if dv, ok := g.DivisionViewFor(viewer, d.ID); ok {
			v.Divisions = append(v.Divisions, dv)
		}
	}
	for _, b := range g.battles {
		if g.battleVisible(viewer, b.AttackerID, b.DefenderID) {
			v.Battles = append(v.Battles, BattleView{
				ID: b.ID, AttackerID: b.AttackerID, DefenderID: b.DefenderID, Position: b.Position,
				StartedTick: b.StartedTick, Rounds: b.Rounds, AttackerLosses: b.AttackerLosses, DefenderLosses: b.DefenderLosses,
			})
		}
	}
	return v
}

// DivisionViewFor returns a division as seen by viewer, if visible.
func (g *Game) DivisionViewFor(viewer player.ID, id DivisionID) (DivisionView, bool) {
	d, ok := g.divisions[id]
	if !ok || !g.canSee(viewer, d) {
		return DivisionView{}, false
	}
	dv := DivisionView{
		ID: d.ID, PlayerID: d.PlayerID, Name: d.Name, Position: d.Position,
		UnitCount: d.UnitCount, MaxUnitCount: d.MaxUnitCount,
		Attack: d.Attack, Defense: d.Defense, Speed: d.Speed,
		Morale: d.Morale, Experience: d.Experience, Fatigue: d.Fatigue,
		State: d.State, Routed: d.Routed, InBattle: g.engaged(d.ID),
		Terrain: g.Map.TypeAt(d.Position),
	}
	if viewer == Spectator || viewer == d.PlayerID {
		if o := d.CurrentOrder; o != nil {
			dv.Order = &OrderView{ID: o.ID, Type: o.Type, TargetPosition: o.TargetPosition, TargetDivisionID: o.TargetDivisionID}
		}
		dv.Path = d.Path()
	}
	return dv, true
}

func (g *Game) canSee(viewer player.ID, d *Division) bool {
	return viewer == Spectator || viewer == d.PlayerID || g.visibility.CanSee(g, viewer, d)
}

func (g *Game) battleVisible(viewer player.ID, ids ...DivisionID) bool {
	for _, id := range ids {
		if d, ok := g.divisions[id]; ok && g.canSee(viewer, d) {
			return true
		}
	}
	return false
}

// EventVisibleTo reports whether an event may be delivered to viewer.
func (g *Game) EventVisibleTo(e GameEvent, viewer player.ID) bool {
	switch ev := e.(type) {
	case DivisionUpdated:
		return g.battleVisible(viewer, ev.DivisionID)
	case DivisionDestroyed:
		return g.battleVisible(viewer, ev.DivisionID)
	case BattleStarted:
		return g.battleVisible(viewer, ev.AttackerID, ev.DefenderID)
	case BattleUpdated:
		return g.battleVisible(viewer, ev.Attacker.DivisionID, ev.Defender.DivisionID)
	case BattleEnded:
		return g.battleVisible(viewer, ev.AttackerID, ev.DefenderID)
	}
	return true
}
