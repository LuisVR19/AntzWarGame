package game

import "gameserver/internal/player"

// Division is a combat unit controlled by a player.
type Division struct {
	ID           DivisionID
	PlayerID     player.ID
	Name         string
	Position     Position
	UnitCount    int
	MaxUnitCount int
	Attack       float64
	Defense      float64
	Speed        float64
	Morale       float64 // 0..MaxMorale
	Experience   float64 // 0..100
	Fatigue      float64 // 0..100
	CurrentOrder *Order
	State        DivisionState
	// Routed divisions retreat automatically and ignore orders until they
	// rally (morale >= RallyMoraleThreshold).
	Routed bool
	// CommanderID is the command unit the division reports to ("" = the
	// general directly). See command.go.
	CommanderID CommandUnitID

	// Simulation internals (not part of the public state).
	home       Position   // deployment point, default retreat target
	path       []Position // remaining waypoints
	pathTarget Position   // position the current path was computed for
	lastRepath int64      // tick of the last path computation
	movedTick  float64    // distance moved during the current tick
}

// Alive reports whether the division still exists on the field.
func (d *Division) Alive() bool { return d.State != StateDestroyed }

// Path returns a copy of the remaining waypoints.
func (d *Division) Path() []Position { return append([]Position(nil), d.path...) }

// Home returns the deployment point used as default retreat destination.
func (d *Division) Home() Position { return d.home }

func (d *Division) orderType() OrderType {
	if d.CurrentOrder == nil {
		return ""
	}
	return d.CurrentOrder.Type
}

// Army groups the divisions of one player.
type Army struct {
	PlayerID    player.ID
	DivisionIDs []DivisionID
	// GeneralID is the army's general ("" = no chain of command).
	GeneralID CommandUnitID
	// successionAt is the tick at which a successor takes over a lost
	// general (-1 = no succession pending).
	successionAt int64
}
