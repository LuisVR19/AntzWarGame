// Package game contains the authoritative domain model and the tick-based
// simulation of a 1v1 match. It has no knowledge of networking: the
// application layer feeds it commands and reads events/views from it.
//
// A Game is NOT safe for concurrent use. It must be owned by a single
// goroutine (see internal/app.Room).
package game

import (
	"gameserver/pkg/geom"
)

// Position is a point in world coordinates.
type Position = geom.Vec2

// Status is the lifecycle state of a game.
type Status string

const (
	StatusWaiting  Status = "WAITING"
	StatusStarting Status = "STARTING"
	StatusRunning  Status = "RUNNING"
	StatusFinished Status = "FINISHED"
)

// DivisionID identifies a division within a game.
type DivisionID string

// DivisionState is what a division is currently doing.
type DivisionState string

const (
	StateIdle       DivisionState = "IDLE"
	StateMoving     DivisionState = "MOVING"
	StateAttacking  DivisionState = "ATTACKING"
	StateDefending  DivisionState = "DEFENDING"
	StateRetreating DivisionState = "RETREATING"
	StateDestroyed  DivisionState = "DESTROYED"
)

// OrderType enumerates the orders a player can issue.
type OrderType string

const (
	OrderMove    OrderType = "MOVE"
	OrderAttack  OrderType = "ATTACK"
	OrderDefend  OrderType = "DEFEND"
	OrderRetreat OrderType = "RETREAT"
	OrderHold    OrderType = "HOLD"
)

// Valid reports whether t is a known order type.
func (t OrderType) Valid() bool {
	switch t {
	case OrderMove, OrderAttack, OrderDefend, OrderRetreat, OrderHold:
		return true
	}
	return false
}
