// Package matchmaking keeps track of live game rooms. The MVP only supports
// creating a game and joining it by ID (no queues, ranking or accounts).
package matchmaking

import (
	"errors"
	"log/slog"
	"sync"

	"gameserver/internal/app"
	"gameserver/pkg/idgen"
)

var (
	ErrGameNotFound = errors.New("game not found")
	ErrTooManyGames = errors.New("server is at maximum game capacity")
)

// RoomFactory builds the configuration of a new room.
type RoomFactory func() app.RoomConfig

// Registry indexes rooms by game ID. It is the only shared structure
// accessed by many goroutines, so it uses a mutex; game state itself is
// owned by each Room goroutine.
type Registry struct {
	mu       sync.RWMutex
	rooms    map[string]*app.Room
	factory  RoomFactory
	maxGames int
	log      *slog.Logger
}

// NewRegistry creates an empty registry. maxGames <= 0 means unlimited.
func NewRegistry(factory RoomFactory, maxGames int, log *slog.Logger) *Registry {
	return &Registry{rooms: make(map[string]*app.Room), factory: factory, maxGames: maxGames, log: log}
}

// CreateGame creates a new empty room in WAITING status.
func (r *Registry) CreateGame() (*app.Room, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.maxGames > 0 && len(r.rooms) >= r.maxGames {
		return nil, ErrTooManyGames
	}
	id := idgen.New("game", 6)
	for r.rooms[id] != nil {
		id = idgen.New("game", 6)
	}
	room, err := app.NewRoom(id, r.factory(), r.remove)
	if err != nil {
		return nil, err
	}
	r.rooms[id] = room
	return room, nil
}

// Get returns the room of a game.
func (r *Registry) Get(id string) (*app.Room, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	room, ok := r.rooms[id]
	if !ok {
		return nil, ErrGameNotFound
	}
	return room, nil
}

// Count returns the number of live rooms.
func (r *Registry) Count() int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.rooms)
}

func (r *Registry) remove(id string) {
	r.mu.Lock()
	delete(r.rooms, id)
	r.mu.Unlock()
}

// Shutdown closes every room.
func (r *Registry) Shutdown() {
	r.mu.RLock()
	rooms := make([]*app.Room, 0, len(r.rooms))
	for _, room := range r.rooms {
		rooms = append(rooms, room)
	}
	r.mu.RUnlock()
	for _, room := range rooms {
		room.Close()
	}
}
