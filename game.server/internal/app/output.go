// Package app is the application layer between the network and the domain.
// Each match is run by a Room: a goroutine that is the single owner of the
// game state. Network goroutines talk to it only through commands, and it
// pushes results to subscribers, so no locks are needed on the game itself.
package app

import (
	"gameserver/internal/game"
	"gameserver/internal/player"
	"gameserver/internal/terrain"
)

// OutputKind identifies what a Room is pushing to a subscriber.
type OutputKind int

const (
	// OutJoined confirms a create/join/reconnect to the joining player.
	OutJoined OutputKind = iota
	// OutLobby carries the lobby state (players, ready flags, status).
	OutLobby
	// OutGameStarted is sent once when the game becomes RUNNING.
	OutGameStarted
	// OutSnapshot is a periodic full state snapshot.
	OutSnapshot
	// OutEvent carries one domain event.
	OutEvent
)

// JoinInfo describes the result of a join for the joining player only.
type JoinInfo struct {
	PlayerID     player.ID
	SessionToken string
	Side         player.Side
	Created      bool // the player created the game
	Reconnected  bool
	Map          *terrain.Map
}

// Output is a message from a Room to one subscriber. Views are already
// filtered for Viewer; the struct is immutable once delivered.
type Output struct {
	Kind   OutputKind
	GameID string
	Viewer player.ID
	Join   *JoinInfo
	View   *game.GameView
	Event  game.GameEvent
	// Division is the viewer's view of the division referenced by a
	// DivisionUpdated event (nil otherwise).
	Division *game.DivisionView
	// RequestID correlates OutJoined with the client request.
	RequestID string
}

// Subscriber receives outputs for one connected player.
// Deliver is called from the Room goroutine and MUST NOT block.
type Subscriber interface {
	Deliver(Output)
}
