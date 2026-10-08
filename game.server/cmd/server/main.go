// Command server runs the authoritative 1v1 strategy game server.
//
//	go run ./cmd/server [-config configs/server.json] [-addr :8080]
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"gameserver/internal/app"
	"gameserver/internal/combat"
	"gameserver/internal/config"
	"gameserver/internal/matchmaking"
	"gameserver/internal/network"
	"gameserver/internal/terrain"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "fatal:", err)
		os.Exit(1)
	}
}

func run() error {
	cfgPath := flag.String("config", "configs/server.json", "path to the JSON configuration (optional)")
	addr := flag.String("addr", "", "listen address, overrides config (e.g. :8080)")
	printConfig := flag.Bool("print-config", false, "print the default configuration as JSON and exit")
	flag.Parse()

	if *printConfig {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		return enc.Encode(config.Default())
	}

	cfg, err := config.Load(*cfgPath, true)
	if err != nil {
		return err
	}
	if *addr != "" {
		cfg.Server.Addr = *addr
	} else if port := os.Getenv("PORT"); port != "" {
		cfg.Server.Addr = ":" + port
	}
	log := cfg.Log.NewLogger()

	// The map and the combat engine are immutable and shared by all games.
	battlefield, err := terrain.DefaultMap(cfg.Terrain)
	if err != nil {
		return err
	}
	engine := combat.NewSimpleEngine(cfg.Game.Combat)

	registry := matchmaking.NewRegistry(func() app.RoomConfig {
		return app.RoomConfig{
			Rules:              cfg.Game,
			Map:                battlefield,
			Engine:             engine,
			SnapshotEveryTicks: cfg.Rooms.SnapshotEveryTicks,
			WaitingTimeout:     cfg.Rooms.WaitingTimeout(),
			FinishedRetention:  cfg.Rooms.FinishedRetention(),
			AI:                 cfg.AI,
			Logger:             log,
		}
	}, cfg.Rooms.MaxGames, log)

	srv := &http.Server{
		Addr:              cfg.Server.Addr,
		Handler:           network.NewServer(registry, cfg.Server, cfg.Game.TickRate, log).Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	errCh := make(chan error, 1)
	go func() {
		log.Info("server listening", "addr", cfg.Server.Addr, "tick_rate", cfg.Game.TickRate, "ws", "/ws")
		errCh <- srv.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
		log.Info("shutting down")
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	registry.Shutdown()
	return srv.Shutdown(shutdownCtx)
}
