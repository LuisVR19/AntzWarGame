package app

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"gameserver/internal/ai"
	"gameserver/internal/combat"
	"gameserver/internal/game"
	"gameserver/internal/player"
	"gameserver/internal/terrain"
	"gameserver/pkg/idgen"
)

// ErrRoomClosed is returned when a command reaches a room that has stopped.
var ErrRoomClosed = errors.New("game room is closed")

// RoomConfig configures a Room.
type RoomConfig struct {
	Rules  game.Rules
	Map    *terrain.Map
	Engine combat.Engine
	// SnapshotEveryTicks controls how often game_state is broadcast.
	SnapshotEveryTicks int
	// WaitingTimeout closes rooms that never start.
	WaitingTimeout time.Duration
	// FinishedRetention keeps finished rooms queryable for a while.
	FinishedRetention time.Duration
	// AI tunes the bot added with AddBot. A zero value uses ai.DefaultConfig.
	AI ai.Config
	// ManualClock disables the internal ticker; ticks are driven by
	// Room.Step (tests).
	ManualClock bool
	Logger      *slog.Logger
	Now         func() time.Time
}

// Room owns one Game and runs its loop.
type Room struct {
	id      string
	cfg     RoomConfig
	g       *game.Game
	subs    map[player.ID]Subscriber
	cmds    chan func()
	done    chan struct{}
	onClose func(id string)
	log     *slog.Logger

	closing    bool
	finishedAt time.Time
	// bot controls the server-side player of a game against the AI.
	bot *ai.Bot
}

// NewRoom creates the game and starts the room goroutine.
func NewRoom(id string, cfg RoomConfig, onClose func(id string)) (*Room, error) {
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	if cfg.SnapshotEveryTicks <= 0 {
		cfg.SnapshotEveryTicks = 1
	}
	if cfg.AI == (ai.Config{}) {
		cfg.AI = ai.DefaultConfig()
	}
	log := cfg.Logger.With("game_id", id)
	g, err := game.New(id, cfg.Map, cfg.Rules, cfg.Engine, game.WithLogger(log), game.WithClock(cfg.Now))
	if err != nil {
		return nil, err
	}
	r := &Room{
		id:      id,
		cfg:     cfg,
		g:       g,
		subs:    make(map[player.ID]Subscriber),
		cmds:    make(chan func(), 64),
		done:    make(chan struct{}),
		onClose: onClose,
		log:     log,
	}
	go r.run()
	log.Info("game created")
	return r, nil
}

// ID returns the game ID.
func (r *Room) ID() string { return r.id }

// Done is closed when the room stops.
func (r *Room) Done() <-chan struct{} { return r.done }

func (r *Room) run() {
	defer func() {
		close(r.done)
		if r.onClose != nil {
			r.onClose(r.id)
		}
		r.log.Info("game room closed")
	}()
	var tick <-chan time.Time
	if !r.cfg.ManualClock {
		t := time.NewTicker(time.Second / time.Duration(r.cfg.Rules.TickRate))
		defer t.Stop()
		tick = t.C
	}
	for !r.closing {
		select {
		case fn := <-r.cmds:
			fn()
		case <-tick:
			r.step()
			r.housekeeping()
		}
	}
}

// exec runs fn on the room goroutine and waits for it to finish.
func (r *Room) exec(ctx context.Context, fn func()) error {
	finished := make(chan struct{})
	wrapped := func() { fn(); close(finished) }
	select {
	case r.cmds <- wrapped:
	case <-r.done:
		return ErrRoomClosed
	case <-ctx.Done():
		return ctx.Err()
	}
	select {
	case <-finished:
		return nil
	case <-r.done:
		// The command may have been the one that closed the room.
		select {
		case <-finished:
			return nil
		default:
			return ErrRoomClosed
		}
	case <-ctx.Done():
		return ctx.Err()
	}
}

// Close stops the room.
func (r *Room) Close() {
	_ = r.exec(context.Background(), func() { r.closing = true })
}

// Join adds a new player (token == "") or reconnects an existing one.
// The confirmation (OutJoined) is delivered to sub before any broadcast.
func (r *Room) Join(ctx context.Context, name, token, requestID string, created bool, sub Subscriber) (player.ID, error) {
	var pid player.ID
	var err error
	execErr := r.exec(ctx, func() { pid, err = r.join(name, token, requestID, created, sub) })
	if execErr != nil {
		return "", execErr
	}
	return pid, err
}

func (r *Room) join(name, token, requestID string, created bool, sub Subscriber) (player.ID, error) {
	reconnected := false
	p, ok := r.g.PlayerByToken(token)
	switch {
	case ok:
		reconnected = true
		r.g.SetConnected(p.ID, true)
		r.log.Info("player reconnected", "player_id", p.ID)
	case token != "":
		return "", &game.Error{Code: game.CodePlayerNotFound, Message: "invalid session token"}
	default:
		var err error
		if p, err = r.g.AddPlayer(name, idgen.New("tok", 16)); err != nil {
			return "", err
		}
		r.log.Info("player joined", "player_id", p.ID, "name", p.Name, "side", p.Side)
	}
	r.subs[p.ID] = sub
	view := r.g.ViewFor(p.ID)
	sub.Deliver(Output{
		Kind: OutJoined, GameID: r.id, Viewer: p.ID, View: &view, RequestID: requestID,
		Join: &JoinInfo{PlayerID: p.ID, SessionToken: p.SessionToken, Side: p.Side, Created: created, Reconnected: reconnected, Map: r.g.Map},
	})
	r.broadcastLobby()
	return p.ID, nil
}

// AddBot adds a server-controlled opponent to a waiting game. It must be
// called before the human joins so that the human gets side 0 and receives
// a lobby that already includes the bot. The bot has no Subscriber: it reads
// the game through Game.ViewFor and submits orders like any player.
func (r *Room) AddBot(ctx context.Context, name string) (player.ID, error) {
	var pid player.ID
	var err error
	execErr := r.exec(ctx, func() {
		if r.bot != nil {
			err = &game.Error{Code: game.CodeGameFull, Message: "game already has a bot"}
			return
		}
		var p *player.Player
		if p, err = r.g.AddBot(name); err != nil {
			return
		}
		pid = p.ID
		r.bot = ai.New(p.ID, r.g.Map.Spawns[p.Side], r.cfg.AI, r.log)
		r.log.Info("bot joined", "player_id", p.ID, "name", p.Name, "side", p.Side)
		r.broadcastLobby()
	})
	if execErr != nil {
		return "", execErr
	}
	return pid, err
}

// Ready marks the player ready; the game starts when both are.
func (r *Room) Ready(ctx context.Context, pid player.ID, ready bool) error {
	var err error
	if e := r.exec(ctx, func() {
		var started bool
		started, err = r.g.SetReady(pid, ready)
		if err != nil {
			return
		}
		r.log.Info("player ready", "player_id", pid, "ready", ready)
		r.broadcastLobby()
		if started {
			r.broadcastSnapshot()
		}
	}); e != nil {
		return e
	}
	return err
}

// SubmitOrder validates and queues an order for the next tick.
func (r *Room) SubmitOrder(ctx context.Context, req game.OrderRequest) (*game.Order, error) {
	var o *game.Order
	var err error
	// Events it produces (messenger dispatched/cancelled) go out with the
	// next tick, after the order_accepted reply.
	if e := r.exec(ctx, func() { o, err = r.g.SubmitOrder(req) }); e != nil {
		return nil, e
	}
	if err != nil {
		r.log.Info("order rejected", "player_id", req.PlayerID, "division_id", req.DivisionID, "type", req.Type, "code", game.CodeOf(err))
		return nil, err
	}
	r.log.Info("order accepted", "player_id", req.PlayerID, "order_id", o.ID, "division_id", req.DivisionID, "type", req.Type, "delivery", o.Delivery)
	return o, nil
}

// AssignRequest moves a division under another command unit.
type AssignRequest struct {
	PlayerID    player.ID
	DivisionID  game.DivisionID
	CommanderID game.CommandUnitID
}

// AssignCommander validates and applies a change of commander. It is
// immediate; the resulting division_updated goes out with the next tick.
func (r *Room) AssignCommander(ctx context.Context, req AssignRequest) error {
	var err error
	if e := r.exec(ctx, func() {
		err = r.g.AssignCommander(req.PlayerID, req.DivisionID, req.CommanderID)
	}); e != nil {
		return e
	}
	if err != nil {
		r.log.Info("assignment rejected", "player_id", req.PlayerID, "division_id", req.DivisionID, "commander_id", req.CommanderID, "code", game.CodeOf(err))
	}
	return err
}

// Disconnect is called by the network when a player's connection drops.
// It is ignored if sub is no longer the player's active subscriber.
func (r *Room) Disconnect(pid player.ID, sub Subscriber) {
	_ = r.exec(context.Background(), func() {
		if cur, ok := r.subs[pid]; !ok || cur != sub {
			return
		}
		delete(r.subs, pid)
		switch r.g.Status {
		case game.StatusWaiting:
			_ = r.g.RemovePlayer(pid)
			r.log.Info("player left lobby", "player_id", pid)
			if !r.hasHumans() {
				r.closing = true
				return
			}
		case game.StatusStarting, game.StatusRunning:
			r.g.SetConnected(pid, false)
			r.log.Info("player disconnected", "player_id", pid)
			// Against the bot the game goes on: the human may reconnect
			// within disconnect_grace_ticks or the bot wins by forfeit.
			// Without a grace period nothing would ever end it: abort.
			if len(r.subs) == 0 && (r.bot == nil || r.cfg.Rules.DisconnectGraceTicks <= 0) {
				r.g.Abort("abandoned")
				r.flushEvents()
			}
		}
		r.broadcastLobby()
	})
}

// Snapshot returns the omniscient view (used by HTTP endpoints).
func (r *Room) Snapshot(ctx context.Context) (game.GameView, error) {
	var v game.GameView
	err := r.exec(ctx, func() { v = r.g.ViewFor(game.Spectator) })
	return v, err
}

// Step advances one tick synchronously (ManualClock mode, tests).
func (r *Room) Step(ctx context.Context) error {
	return r.exec(ctx, func() { r.step(); r.housekeeping() })
}

// Inspect runs fn with exclusive access to the game (tests, debugging).
func (r *Room) Inspect(ctx context.Context, fn func(*game.Game)) error {
	return r.exec(ctx, func() { fn(r.g) })
}

// step runs one simulation tick and publishes its results (game loop step 8).
// The bot decides after the tick, so its orders, like the humans', take
// effect in the next one.
func (r *Room) step() {
	before := r.g.Status
	events := r.g.Tick()
	r.publish(events)
	switch st := r.g.Status; {
	case st == game.StatusFinished && before != game.StatusFinished:
		r.broadcastSnapshot()
		if r.bot != nil {
			r.log.Info("ai stopped", "player_id", r.bot.PlayerID(), "reason", r.g.FinishReason)
		}
	case st == game.StatusRunning || st == game.StatusStarting:
		if r.g.CurrentTick%int64(r.cfg.SnapshotEveryTicks) == 0 {
			r.broadcastSnapshot()
		}
	}
	r.driveBot()
}

// driveBot lets the bot evaluate its view of the game and submits its orders
// through the normal validation. It does nothing once the game is over.
func (r *Room) driveBot() {
	if r.bot == nil || r.g.Status != game.StatusRunning || !r.bot.Due(r.g.CurrentTick) {
		return
	}
	for _, dec := range r.bot.Decide(r.g.ViewFor(r.bot.PlayerID())) {
		if a := dec.Assign; a != nil {
			if err := r.g.AssignCommander(r.bot.PlayerID(), a.DivisionID, a.CommanderID); err != nil {
				r.log.Warn("ai assignment rejected", "player_id", r.bot.PlayerID(), "division_id", a.DivisionID, "code", game.CodeOf(err))
				r.bot.AssignmentRejected(a.DivisionID)
			}
			continue
		}
		if _, err := r.g.SubmitOrder(dec.Order); err != nil {
			r.log.Warn("ai order rejected", "player_id", dec.Order.PlayerID, "division_id", dec.Order.DivisionID,
				"type", dec.Order.Type, "code", game.CodeOf(err), "err", err)
		}
	}
}

// hasHumans reports whether a non-bot player is still in the game.
func (r *Room) hasHumans() bool {
	for _, p := range r.g.Players() {
		if !p.Bot {
			return true
		}
	}
	return false
}

func (r *Room) flushEvents() {
	r.publish(r.g.DrainEvents())
	if r.g.Status == game.StatusFinished {
		r.broadcastSnapshot()
	}
}

func (r *Room) publish(events []game.GameEvent) {
	for _, ev := range events {
		if _, ok := ev.(game.GameStarted); ok {
			for pid, sub := range r.subs {
				v := r.g.ViewFor(pid)
				sub.Deliver(Output{Kind: OutGameStarted, GameID: r.id, Viewer: pid, View: &v, Event: ev})
			}
			continue
		}
		for pid, sub := range r.subs {
			if !r.g.EventVisibleTo(ev, pid) {
				continue
			}
			out := Output{Kind: OutEvent, GameID: r.id, Viewer: pid, Event: ev}
			if du, ok := ev.(game.DivisionUpdated); ok {
				dv, visible := r.g.DivisionViewFor(pid, du.DivisionID)
				if !visible {
					continue
				}
				out.Division = &dv
			}
			sub.Deliver(out)
		}
	}
}

func (r *Room) broadcastSnapshot() {
	for pid, sub := range r.subs {
		v := r.g.ViewFor(pid)
		sub.Deliver(Output{Kind: OutSnapshot, GameID: r.id, Viewer: pid, View: &v})
	}
}

func (r *Room) broadcastLobby() {
	for pid, sub := range r.subs {
		v := r.g.ViewFor(pid)
		sub.Deliver(Output{Kind: OutLobby, GameID: r.id, Viewer: pid, View: &v})
	}
}

// housekeeping closes rooms that timed out or finished long ago.
func (r *Room) housekeeping() {
	now := r.cfg.Now()
	switch r.g.Status {
	case game.StatusWaiting:
		if r.cfg.WaitingTimeout > 0 && now.Sub(r.g.CreatedAt) > r.cfg.WaitingTimeout {
			r.log.Info("closing idle lobby")
			r.closing = true
		}
	case game.StatusFinished:
		if r.finishedAt.IsZero() {
			r.finishedAt = now
		}
		if now.Sub(r.finishedAt) >= r.cfg.FinishedRetention {
			r.closing = true
		}
	}
}
