// Package config centralizes every tunable of the server. Defaults live in
// code; a JSON file can override any subset of them.
package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"strings"
	"time"

	"gameserver/internal/ai"
	"gameserver/internal/game"
	"gameserver/internal/terrain"
)

// Config is the full server configuration.
type Config struct {
	Server  Server        `json:"server"`
	Rooms   Rooms         `json:"rooms"`
	Log     Log           `json:"log"`
	Game    game.Rules    `json:"game"`
	Terrain terrain.Table `json:"terrain"`
	// AI tunes the server-controlled opponent of create_ai_game.
	AI ai.Config `json:"ai"`
}

// Server holds network settings.
type Server struct {
	Addr string `json:"addr"`
	// AllowedOrigins for WebSocket upgrades. Empty = allow any origin
	// (native Godot clients do not send an Origin header).
	AllowedOrigins    []string `json:"allowed_origins"`
	SendQueueSize     int      `json:"send_queue_size"`
	MaxMessageBytes   int64    `json:"max_message_bytes"`
	WriteTimeoutSec   int      `json:"write_timeout_seconds"`
	PongTimeoutSec    int      `json:"pong_timeout_seconds"`
	RequestTimeoutSec int      `json:"request_timeout_seconds"`
}

// Rooms holds game-room lifecycle settings.
type Rooms struct {
	MaxGames             int `json:"max_games"`
	SnapshotEveryTicks   int `json:"snapshot_every_ticks"`
	WaitingTimeoutSec    int `json:"waiting_timeout_seconds"`
	FinishedRetentionSec int `json:"finished_retention_seconds"`
}

// Log holds logging settings.
type Log struct {
	Level  string `json:"level"`  // debug, info, warn, error
	Format string `json:"format"` // text or json
}

// Default returns the built-in configuration.
func Default() Config {
	return Config{
		Server: Server{
			Addr:              ":8080",
			SendQueueSize:     256,
			MaxMessageBytes:   8 * 1024,
			WriteTimeoutSec:   5,
			PongTimeoutSec:    30,
			RequestTimeoutSec: 5,
		},
		Rooms: Rooms{
			MaxGames:             500,
			SnapshotEveryTicks:   1,
			WaitingTimeoutSec:    15 * 60,
			FinishedRetentionSec: 60,
		},
		Log:     Log{Level: "info", Format: "text"},
		Game:    game.DefaultRules(),
		Terrain: terrain.DefaultTable(),
		AI:      ai.DefaultConfig(),
	}
}

// Load reads path over the defaults. A missing file is not an error when
// optional is true.
func Load(path string, optional bool) (Config, error) {
	cfg := Default()
	if path == "" {
		return cfg, cfg.Validate()
	}
	data, err := os.ReadFile(path)
	switch {
	case errors.Is(err, fs.ErrNotExist) && optional:
		return cfg, cfg.Validate()
	case err != nil:
		return cfg, fmt.Errorf("config: %w", err)
	}
	// encoding/json reuses existing slice elements, which would merge the
	// file's army with the default one. Reset it so it is fully replaced.
	var probe struct {
		Game struct {
			Army json.RawMessage `json:"army"`
		} `json:"game"`
	}
	if err := json.Unmarshal(data, &probe); err == nil && probe.Game.Army != nil {
		cfg.Game.Army = nil
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return cfg, fmt.Errorf("config %s: %w", path, err)
	}
	return cfg, cfg.Validate()
}

// Validate checks the whole configuration.
func (c Config) Validate() error {
	if err := c.Game.Validate(); err != nil {
		return err
	}
	if err := c.Terrain.Validate(); err != nil {
		return err
	}
	if err := c.AI.Validate(); err != nil {
		return err
	}
	if c.Server.SendQueueSize <= 0 || c.Server.MaxMessageBytes <= 0 {
		return errors.New("config: server queue and message sizes must be > 0")
	}
	if c.Rooms.SnapshotEveryTicks <= 0 {
		return errors.New("config: rooms.snapshot_every_ticks must be > 0")
	}
	return nil
}

func (s Server) WriteTimeout() time.Duration { return time.Duration(s.WriteTimeoutSec) * time.Second }
func (s Server) PongTimeout() time.Duration  { return time.Duration(s.PongTimeoutSec) * time.Second }
func (s Server) RequestTimeout() time.Duration {
	return time.Duration(s.RequestTimeoutSec) * time.Second
}
func (r Rooms) WaitingTimeout() time.Duration {
	return time.Duration(r.WaitingTimeoutSec) * time.Second
}
func (r Rooms) FinishedRetention() time.Duration {
	return time.Duration(r.FinishedRetentionSec) * time.Second
}

// NewLogger builds the structured logger described by the config.
func (l Log) NewLogger() *slog.Logger {
	var level slog.Level
	if err := level.UnmarshalText([]byte(l.Level)); err != nil {
		level = slog.LevelInfo
	}
	opts := &slog.HandlerOptions{Level: level}
	if strings.EqualFold(l.Format, "json") {
		return slog.New(slog.NewJSONHandler(os.Stdout, opts))
	}
	return slog.New(slog.NewTextHandler(os.Stdout, opts))
}
