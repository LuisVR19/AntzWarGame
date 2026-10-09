package game

import (
	"fmt"
	"io"
	"log/slog"
	"math"
	"time"

	"gameserver/internal/combat"
	"gameserver/internal/player"
	"gameserver/internal/terrain"
)

// MaxPlayers is the number of players in a match.
const MaxPlayers = 2

// Game is the authoritative state of one match.
type Game struct {
	ID           string
	Status       Status
	Map          *terrain.Map
	Rules        Rules
	CurrentTick  int64
	CreatedAt    time.Time
	StartedAt    time.Time
	FinishedAt   time.Time
	WinnerID     player.ID
	FinishReason string

	players     map[player.ID]*player.Player
	playerOrder []player.ID
	armies      map[player.ID]*Army
	divisions   map[DivisionID]*Division
	// divisionOrder keeps a stable iteration order for determinism.
	divisionOrder []*Division
	battles       []*Battle
	pending       []pendingOrder
	// Formation changes validated since the previous tick (formation.go).
	pendingFormations []pendingFormation
	// Chain of command (command.go).
	commandUnits map[CommandUnitID]*CommandUnit
	commandOrder []*CommandUnit
	messengers   []*Messenger
	events       []GameEvent
	countdown    int
	// disconnectedAt holds the tick at which a player lost connection.
	disconnectedAt map[player.ID]int64

	playerSeq, divisionSeq, battleSeq, orderSeq, commandSeq, messengerSeq int

	engine     combat.Engine
	visibility VisibilityPolicy
	now        func() time.Time
	log        *slog.Logger
}

// Option customizes a Game.
type Option func(*Game)

// WithClock sets the wall clock used for timestamps (tests).
func WithClock(now func() time.Time) Option { return func(g *Game) { g.now = now } }

// WithVisibility sets the fog-of-war policy.
func WithVisibility(v VisibilityPolicy) Option { return func(g *Game) { g.visibility = v } }

// WithLogger sets the structured logger.
func WithLogger(l *slog.Logger) Option { return func(g *Game) { g.log = l } }

// New creates a game in WAITING status.
func New(id string, m *terrain.Map, rules Rules, engine combat.Engine, opts ...Option) (*Game, error) {
	if err := rules.Validate(); err != nil {
		return nil, err
	}
	if m == nil || engine == nil {
		return nil, fmt.Errorf("game: map and combat engine are required")
	}
	g := &Game{
		ID:             id,
		Status:         StatusWaiting,
		Map:            m,
		Rules:          rules,
		players:        make(map[player.ID]*player.Player),
		armies:         make(map[player.ID]*Army),
		divisions:      make(map[DivisionID]*Division),
		commandUnits:   make(map[CommandUnitID]*CommandUnit),
		disconnectedAt: make(map[player.ID]int64),
		engine:         engine,
		visibility:     FullVisibility{},
		now:            time.Now,
		log:            slog.New(slog.NewTextHandler(io.Discard, nil)),
	}
	for _, o := range opts {
		o(g)
	}
	g.CreatedAt = g.now()
	// Fail early if the army template does not fit the map.
	for side := 0; side < MaxPlayers; side++ {
		for _, t := range rules.Army {
			if p := spawnPosition(m, player.Side(side), t); !m.Passable(p) {
				return nil, fmt.Errorf("game: division %q of side %d spawns on impassable terrain", t.Name, side)
			}
		}
	}
	return g, nil
}

// AddPlayer adds a player to a waiting game and assigns the first free side.
func (g *Game) AddPlayer(name, sessionToken string) (*player.Player, error) {
	return g.addPlayer(name, sessionToken, false)
}

// AddBot adds a server-controlled player. It takes the last free side (so a
// human joining afterwards gets side 0), is always ready and is considered
// connected: it has no WebSocket and never forfeits by disconnection.
func (g *Game) AddBot(name string) (*player.Player, error) {
	return g.addPlayer(name, "", true)
}

func (g *Game) addPlayer(name, sessionToken string, bot bool) (*player.Player, error) {
	if g.Status != StatusWaiting {
		return nil, newErr(CodeInvalidState, "game is %s", g.Status)
	}
	if len(g.players) >= MaxPlayers {
		return nil, newErr(CodeGameFull, "game already has %d players", MaxPlayers)
	}
	used := map[player.Side]bool{}
	for _, p := range g.players {
		used[p.Side] = true
	}
	side, step, prefix := player.Side(0), player.Side(1), "player"
	if bot {
		side, step, prefix = MaxPlayers-1, -1, "bot"
	}
	for used[side] {
		side += step
	}
	g.playerSeq++
	p := &player.Player{
		ID:           player.ID(fmt.Sprintf("%s-%d", prefix, g.playerSeq)),
		Name:         name,
		Side:         side,
		SessionToken: sessionToken,
		Ready:        bot,
		Connected:    true,
		Bot:          bot,
	}
	g.players[p.ID] = p
	g.playerOrder = append(g.playerOrder, p.ID)
	return p, nil
}

// RemovePlayer removes a player from a game that has not started yet.
func (g *Game) RemovePlayer(id player.ID) error {
	if g.Status != StatusWaiting {
		return newErr(CodeInvalidState, "cannot leave a game that is %s", g.Status)
	}
	if _, ok := g.players[id]; !ok {
		return newErr(CodePlayerNotFound, "player %s not found", id)
	}
	delete(g.players, id)
	for i, pid := range g.playerOrder {
		if pid == id {
			g.playerOrder = append(g.playerOrder[:i], g.playerOrder[i+1:]...)
			break
		}
	}
	return nil
}

// Player returns a player by ID.
func (g *Game) Player(id player.ID) (*player.Player, bool) {
	p, ok := g.players[id]
	return p, ok
}

// PlayerByToken finds a player by its secret session token.
func (g *Game) PlayerByToken(token string) (*player.Player, bool) {
	if token == "" {
		return nil, false
	}
	for _, id := range g.playerOrder {
		if p := g.players[id]; p.SessionToken == token {
			return p, true
		}
	}
	return nil, false
}

// Players returns the players in join order.
func (g *Game) Players() []*player.Player {
	out := make([]*player.Player, 0, len(g.playerOrder))
	for _, id := range g.playerOrder {
		out = append(out, g.players[id])
	}
	return out
}

// Division returns a division by ID.
func (g *Game) Division(id DivisionID) (*Division, bool) {
	d, ok := g.divisions[id]
	return d, ok
}

// Divisions returns all divisions in creation order.
func (g *Game) Divisions() []*Division { return append([]*Division(nil), g.divisionOrder...) }

// Battles returns the active battles.
func (g *Game) Battles() []*Battle { return append([]*Battle(nil), g.battles...) }

// Army returns the army of a player.
func (g *Game) Army(id player.ID) (*Army, bool) {
	a, ok := g.armies[id]
	return a, ok
}

// CountdownTicks returns the ticks left before RUNNING (STARTING only).
func (g *Game) CountdownTicks() int { return g.countdown }

// SetReady marks a player ready. When both players are ready the armies are
// deployed and the game enters STARTING. Returns true if the game started.
func (g *Game) SetReady(id player.ID, ready bool) (bool, error) {
	if g.Status != StatusWaiting {
		return false, newErr(CodeInvalidState, "game is %s", g.Status)
	}
	p, ok := g.players[id]
	if !ok {
		return false, newErr(CodePlayerNotFound, "player %s not found", id)
	}
	p.Ready = ready
	if len(g.players) < MaxPlayers {
		return false, nil
	}
	for _, p := range g.players {
		if !p.Ready {
			return false, nil
		}
	}
	g.deployArmies()
	g.Status = StatusStarting
	g.countdown = g.Rules.StartCountdownTicks
	g.log.Info("game starting", "game_id", g.ID, "countdown_ticks", g.countdown)
	return true, nil
}

// SetConnected records a player's connection status. Disconnection during a
// match starts the forfeit grace period.
func (g *Game) SetConnected(id player.ID, connected bool) {
	p, ok := g.players[id]
	if !ok {
		return
	}
	p.Connected = connected
	if connected {
		delete(g.disconnectedAt, id)
	} else {
		g.disconnectedAt[id] = g.CurrentTick
	}
}

// Forfeit ends the game with the opponent of id as winner.
func (g *Game) Forfeit(id player.ID, reason string) error {
	if g.Status != StatusRunning && g.Status != StatusStarting {
		return newErr(CodeInvalidState, "game is %s", g.Status)
	}
	if _, ok := g.players[id]; !ok {
		return newErr(CodePlayerNotFound, "player %s not found", id)
	}
	g.finish(g.opponentOf(id), reason)
	return nil
}

// Abort ends a started game without a winner (e.g. both players left).
func (g *Game) Abort(reason string) {
	if g.Status == StatusRunning || g.Status == StatusStarting {
		g.finish("", reason)
	}
}

func (g *Game) opponentOf(id player.ID) player.ID {
	for _, pid := range g.playerOrder {
		if pid != id {
			return pid
		}
	}
	return ""
}

func spawnPosition(m *terrain.Map, side player.Side, t DivisionTemplate) Position {
	off := t.Offset
	if side == 1 {
		off.X = -off.X
	}
	return m.Spawns[side].Add(off)
}

// deployArmies creates every player's divisions from the army template.
func (g *Game) deployArmies() {
	for _, pid := range g.playerOrder {
		p := g.players[pid]
		army := &Army{PlayerID: pid}
		divs := make([]*Division, 0, len(g.Rules.Army))
		for _, raw := range g.Rules.Army {
			t := g.Rules.Resolved(raw)
			g.divisionSeq++
			pos := spawnPosition(g.Map, p.Side, t)
			d := &Division{
				ID:           DivisionID(fmt.Sprintf("division-%d", g.divisionSeq)),
				PlayerID:     pid,
				Name:         t.Name,
				Position:     pos,
				UnitCount:    t.UnitCount,
				MaxUnitCount: t.UnitCount,
				Attack:       t.Attack,
				Defense:      t.Defense,
				Speed:        t.Speed,
				Morale:       math.Min(t.Morale, g.Rules.MaxMorale),
				Experience:   t.Experience,
				UnitType:     t.Type,
				Formation:    t.Formation,
				Facing:       initialFacing(p.Side),
				State:        StateIdle,
				home:         pos,
			}
			g.divisions[d.ID] = d
			g.divisionOrder = append(g.divisionOrder, d)
			army.DivisionIDs = append(army.DivisionIDs, d.ID)
			divs = append(divs, d)
		}
		g.deployCommand(army, divs)
		g.armies[pid] = army
	}
}

func (g *Game) finish(winner player.ID, reason string) {
	if g.Status == StatusFinished {
		return
	}
	g.Status = StatusFinished
	g.WinnerID = winner
	g.FinishReason = reason
	g.FinishedAt = g.now()
	g.pending = nil
	g.pendingFormations = nil
	for _, m := range append([]*Messenger(nil), g.messengers...) {
		g.endMessenger(m, MessageCancelled, "game_finished")
	}
	g.emit(GameFinished{At: g.CurrentTick, WinnerID: winner, Reason: reason})
	g.log.Info("game finished", "game_id", g.ID, "winner", winner, "reason", reason, "tick", g.CurrentTick)
}

func clamp(v, lo, hi float64) float64 { return math.Max(lo, math.Min(hi, v)) }
