// Package player models a participant in a match. There are no accounts:
// a player only exists for the lifetime of a game.
package player

// ID identifies a player inside a game.
type ID string

// Side is the slot a player occupies (0 or 1). It selects the spawn.
type Side int

// Player is a participant of a 1v1 match.
type Player struct {
	ID   ID     `json:"id"`
	Name string `json:"name"`
	Side Side   `json:"side"`
	// SessionToken is a secret returned only to the player, used to
	// reconnect. It is never broadcast.
	SessionToken string `json:"-"`
	Ready        bool   `json:"ready"`
	Connected    bool   `json:"connected"`
	// Bot players are controlled by the server (internal/ai) and have no
	// connection of their own.
	Bot bool `json:"bot"`
}
