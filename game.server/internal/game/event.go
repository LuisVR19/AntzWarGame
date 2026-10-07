package game

import (
	"gameserver/internal/player"
)

// EventType identifies the kind of a GameEvent.
type EventType string

const (
	EventGameStarted       EventType = "game_started"
	EventDivisionUpdated   EventType = "division_updated"
	EventBattleStarted     EventType = "battle_started"
	EventBattleUpdated     EventType = "battle_updated"
	EventBattleEnded       EventType = "battle_ended"
	EventDivisionDestroyed EventType = "division_destroyed"
	EventGameFinished      EventType = "game_finished"
)

// GameEvent is something notable that happened during a tick. Events are
// produced by the simulation and drained by the application layer, which
// decides who receives them (see Game.EventVisibleTo).
type GameEvent interface {
	Type() EventType
	Tick() int64
}

// GameStarted is emitted when the countdown ends and the game is RUNNING.
type GameStarted struct{ At int64 }

// DivisionUpdated is emitted when a division's order or state changes.
// It carries only the ID: the receiver builds a view filtered for each player.
type DivisionUpdated struct {
	At         int64
	DivisionID DivisionID
	Reason     string
}

// BattleStarted is emitted when two enemy divisions make contact.
type BattleStarted struct {
	At         int64
	BattleID   string
	AttackerID DivisionID
	DefenderID DivisionID
	Position   Position
}

// BattleSideReport summarizes one side after a combat round.
type BattleSideReport struct {
	DivisionID       DivisionID
	Losses           int
	UnitCount        int
	Morale           float64
	Fatigue          float64
	EffectiveAttack  float64
	EffectiveDefense float64
}

// BattleUpdated is emitted after every combat round.
type BattleUpdated struct {
	At       int64
	BattleID string
	Round    int
	Attacker BattleSideReport
	Defender BattleSideReport
}

// BattleEnded is emitted when a battle is over.
type BattleEnded struct {
	At               int64
	BattleID         string
	AttackerID       DivisionID
	DefenderID       DivisionID
	Reason           string
	WinnerDivisionID DivisionID // empty if undecided
}

// DivisionDestroyed is emitted when a division is wiped out.
type DivisionDestroyed struct {
	At         int64
	DivisionID DivisionID
	PlayerID   player.ID
	BattleID   string
}

// GameFinished is emitted once when the game ends.
type GameFinished struct {
	At       int64
	WinnerID player.ID // empty on draw
	Reason   string
}

func (e GameStarted) Type() EventType       { return EventGameStarted }
func (e DivisionUpdated) Type() EventType   { return EventDivisionUpdated }
func (e BattleStarted) Type() EventType     { return EventBattleStarted }
func (e BattleUpdated) Type() EventType     { return EventBattleUpdated }
func (e BattleEnded) Type() EventType       { return EventBattleEnded }
func (e DivisionDestroyed) Type() EventType { return EventDivisionDestroyed }
func (e GameFinished) Type() EventType      { return EventGameFinished }

func (e GameStarted) Tick() int64       { return e.At }
func (e DivisionUpdated) Tick() int64   { return e.At }
func (e BattleStarted) Tick() int64     { return e.At }
func (e BattleUpdated) Tick() int64     { return e.At }
func (e BattleEnded) Tick() int64       { return e.At }
func (e DivisionDestroyed) Tick() int64 { return e.At }
func (e GameFinished) Tick() int64      { return e.At }

func (g *Game) emit(e GameEvent) { g.events = append(g.events, e) }

// DrainEvents returns and clears the events accumulated since the last call.
func (g *Game) DrainEvents() []GameEvent {
	ev := g.events
	g.events = nil
	return ev
}
