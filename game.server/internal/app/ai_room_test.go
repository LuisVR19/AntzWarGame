package app

import (
	"context"
	"log/slog"
	"sync"
	"testing"
	"time"

	"gameserver/internal/ai"
	"gameserver/internal/combat"
	"gameserver/internal/game"
	"gameserver/internal/player"
	"gameserver/internal/terrain"
)

// logCounter is a slog.Handler that counts records by message.
type logCounter struct {
	mu     sync.Mutex
	counts map[string]int
}

func (h *logCounter) Enabled(context.Context, slog.Level) bool { return true }
func (h *logCounter) Handle(_ context.Context, r slog.Record) error {
	h.mu.Lock()
	h.counts[r.Message]++
	h.mu.Unlock()
	return nil
}
func (h *logCounter) WithAttrs([]slog.Attr) slog.Handler { return h }
func (h *logCounter) WithGroup(string) slog.Handler      { return h }
func (h *logCounter) count(msg string) int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.counts[msg]
}

func newAIRoom(t *testing.T, rules game.Rules) (*Room, *logCounter) {
	t.Helper()
	m, err := terrain.DefaultMap(terrain.DefaultTable())
	if err != nil {
		t.Fatal(err)
	}
	logs := &logCounter{counts: map[string]int{}}
	r, err := NewRoom("game-ai", RoomConfig{
		Rules: rules, Map: m, Engine: combat.NewSimpleEngine(rules.Combat),
		SnapshotEveryTicks: 1, ManualClock: true, Logger: slog.New(logs),
		// Keep finished games inspectable.
		FinishedRetention: time.Hour,
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(r.Close)
	return r, logs
}

// startAIGame adds the bot and a human, readies the human and ticks into RUNNING.
func startAIGame(t *testing.T, r *Room) (bot, human player.ID, sub *recorder) {
	t.Helper()
	ctx := context.Background()
	bot, err := r.AddBot(ctx, "IA")
	if err != nil {
		t.Fatal(err)
	}
	sub = &recorder{}
	human, err = r.Join(ctx, "alice", "", "req-1", true, sub)
	if err != nil {
		t.Fatal(err)
	}
	out := sub.take()
	if out[0].Kind != OutJoined || out[0].Join.Side != 0 || len(out[0].View.Players) != 2 {
		t.Fatalf("the human must join side 0 of a game that already has the bot: %+v", out[0])
	}
	if _, err := r.AddBot(ctx, "IA"); game.CodeOf(err) != game.CodeGameFull {
		t.Fatalf("second bot: %v", err)
	}
	if err := r.Ready(ctx, human, true); err != nil {
		t.Fatal(err)
	}
	for i := 0; ; i++ {
		var st game.Status
		_ = r.Inspect(ctx, func(g *game.Game) { st = g.Status })
		if st == game.StatusRunning {
			break
		}
		if i > 50 {
			t.Fatalf("AI game did not start (status %s)", st)
		}
		if err := r.Step(ctx); err != nil {
			t.Fatal(err)
		}
	}
	return bot, human, sub
}

func TestAIGamePlaysByTheRulesUntilTheEnd(t *testing.T) {
	ctx := context.Background()
	rules := game.DefaultRules()
	rules.StartCountdownTicks = 3
	rules.MaxDurationTicks = 6000
	r, logs := newAIRoom(t, rules)
	bot, human, sub := startAIGame(t, r)
	m, _ := terrain.DefaultMap(terrain.DefaultTable())

	// The human stays passive; the bot must go and fight.
	var status game.Status
	for i := 0; i < 7000; i++ {
		if err := r.Step(ctx); err != nil {
			t.Fatal(err)
		}
		_ = r.Inspect(ctx, func(g *game.Game) { status = g.Status })
		if status == game.StatusFinished {
			break
		}
	}
	if status != game.StatusFinished {
		t.Fatal("the AI game never finished")
	}
	if logs.count("ai decision") == 0 {
		t.Fatal("the bot took no decisions")
	}
	if n := logs.count("ai order rejected"); n != 0 {
		t.Fatalf("the bot sent %d invalid orders", n)
	}
	if logs.count("ai stopped") != 1 {
		t.Fatal("the end of the game must stop the bot")
	}

	// Check the human's stream: the bot moved, fought and the game ended
	// through the normal rules.
	maxStep := 0.0
	for _, tmpl := range rules.Army {
		maxStep = max(maxStep, tmpl.Speed*rules.RetreatSpeedMultiplier*rules.DT())
	}
	losses := map[game.DivisionID]int{}
	destroyed := map[game.DivisionID]bool{}
	var botOrders, battles int
	var finished *game.GameFinished
	var last *game.GameView
	prev := map[game.DivisionID]game.Position{}
	for _, out := range sub.take() {
		switch out.Kind {
		case OutSnapshot:
			for _, d := range out.View.Divisions {
				if d.State == game.StateDestroyed {
					continue
				}
				if !m.Passable(d.Position) {
					t.Fatalf("division %s on impassable terrain at %+v", d.ID, d.Position)
				}
				if p, ok := prev[d.ID]; ok && p.Dist(d.Position) > maxStep+1e-6 {
					t.Fatalf("division %s moved %.2f in one tick (max %.2f)", d.ID, p.Dist(d.Position), maxStep)
				}
				prev[d.ID] = d.Position
			}
			last = out.View
		case OutEvent:
			switch ev := out.Event.(type) {
			case game.DivisionUpdated:
				if ev.Reason == "order" && out.Division.PlayerID == bot {
					botOrders++
				}
			case game.BattleStarted:
				battles++
			case game.BattleUpdated:
				losses[ev.Attacker.DivisionID] += ev.Attacker.Losses
				losses[ev.Defender.DivisionID] += ev.Defender.Losses
			case game.DivisionDestroyed:
				destroyed[ev.DivisionID] = true
			case game.GameFinished:
				finished = &ev
			}
		}
	}
	if botOrders == 0 || battles == 0 {
		t.Fatalf("the bot must issue orders and fight: orders=%d battles=%d", botOrders, battles)
	}
	if finished == nil || last == nil || last.Status != game.StatusFinished {
		t.Fatal("the human must receive game_finished and the final snapshot")
	}
	// No flapping: on average less than one new order per evaluation.
	if evals := finished.At / int64(ai.DefaultConfig().DecisionIntervalTicks); int64(logs.count("ai decision")) > evals {
		t.Fatalf("the bot issued %d orders in %d evaluations", logs.count("ai decision"), evals)
	}
	if finished.Reason != "annihilation" && finished.Reason != "time_limit" {
		t.Fatalf("unexpected finish reason %q", finished.Reason)
	}
	if finished.WinnerID != "" && finished.WinnerID != bot && finished.WinnerID != human {
		t.Fatalf("unknown winner %s", finished.WinnerID)
	}
	// Troops are only lost in combat rounds resolved by the engine.
	for _, d := range last.Divisions {
		if d.State == game.StateDestroyed {
			if !destroyed[d.ID] {
				t.Fatalf("division %s destroyed without event", d.ID)
			}
			continue
		}
		if lost := d.MaxUnitCount - d.UnitCount; lost != losses[d.ID] {
			t.Fatalf("division %s lost %d troops but combat reported %d", d.ID, lost, losses[d.ID])
		}
	}

	// Once finished, the bot no longer acts.
	before := logs.count("ai decision")
	for i := 0; i < 50; i++ {
		if err := r.Step(ctx); err != nil {
			t.Fatal(err)
		}
	}
	if logs.count("ai decision") != before {
		t.Fatal("the bot kept deciding after the game ended")
	}
}

func TestAIGameHumanDisconnectGivesBotTheWinAfterGrace(t *testing.T) {
	ctx := context.Background()
	rules := game.DefaultRules()
	rules.StartCountdownTicks = 1
	rules.DisconnectGraceTicks = 20
	r, _ := newAIRoom(t, rules)
	bot, human, sub := startAIGame(t, r)

	r.Disconnect(human, sub)
	var status game.Status
	var winner player.ID
	_ = r.Inspect(ctx, func(g *game.Game) { status = g.Status })
	if status != game.StatusRunning {
		t.Fatalf("the game must wait for the human to reconnect, status %s", status)
	}
	for i := 0; i < 30; i++ {
		if err := r.Step(ctx); err != nil {
			t.Fatalf("step %d: %v", i, err)
		}
	}
	_ = r.Inspect(ctx, func(g *game.Game) { status, winner = g.Status, g.WinnerID })
	if status != game.StatusFinished || winner != bot {
		t.Fatalf("bot must win by forfeit: status=%s winner=%s", status, winner)
	}
}

func TestAIGameWithoutGraceIsAbortedWhenHumanLeaves(t *testing.T) {
	ctx := context.Background()
	rules := game.DefaultRules()
	rules.StartCountdownTicks = 1
	rules.DisconnectGraceTicks = 0
	rules.MaxDurationTicks = 0
	r, _ := newAIRoom(t, rules)
	_, human, sub := startAIGame(t, r)
	r.Disconnect(human, sub)
	var status game.Status
	var reason string
	_ = r.Inspect(ctx, func(g *game.Game) { status, reason = g.Status, g.FinishReason })
	if status != game.StatusFinished || reason != "abandoned" {
		t.Fatalf("an AI game nobody can finish must be aborted: status=%s reason=%s", status, reason)
	}
}

func TestAIGameLobbyClosesWhenHumanLeaves(t *testing.T) {
	ctx := context.Background()
	r, _ := newAIRoom(t, game.DefaultRules())
	if _, err := r.AddBot(ctx, "IA"); err != nil {
		t.Fatal(err)
	}
	sub := &recorder{}
	human, err := r.Join(ctx, "alice", "", "", true, sub)
	if err != nil {
		t.Fatal(err)
	}
	r.Disconnect(human, sub)
	<-r.Done()
}

// The bot's orders to a division out of its commander's range travel by
// messenger exactly like a human's: they are not applied before delivery.
func TestAIOrdersFollowTheChainOfCommand(t *testing.T) {
	ctx := context.Background()
	rules := game.DefaultRules()
	rules.StartCountdownTicks = 2
	r, logs := newAIRoom(t, rules)
	bot, err := r.AddBot(ctx, "IA")
	if err != nil {
		t.Fatal(err)
	}
	sub := &recorder{}
	human, err := r.Join(ctx, "alice", "", "", true, sub)
	if err != nil {
		t.Fatal(err)
	}
	if err := r.Ready(ctx, human, true); err != nil {
		t.Fatal(err)
	}
	// While STARTING, move the bot's 2nd Infantry far from Infantry Command.
	var far game.DivisionID
	_ = r.Inspect(ctx, func(g *game.Game) {
		army, _ := g.Army(bot)
		far = army.DivisionIDs[1]
		d, _ := g.Division(far)
		d.Position = game.Position{X: 1300, Y: 300}
	})
	var link game.CommandLink
	var pending *game.Messenger
	var order *game.Order
	for i := 0; i < 10 && pending == nil; i++ {
		if err := r.Step(ctx); err != nil {
			t.Fatal(err)
		}
		_ = r.Inspect(ctx, func(g *game.Game) {
			link = g.CommandLinkOf(far)
			pending, _ = g.PendingOrder(far)
			d, _ := g.Division(far)
			order = d.CurrentOrder
		})
	}
	if link != game.LinkOutOfRange || pending == nil {
		t.Fatalf("the bot's order to an out-of-range division must travel by messenger (link=%s)", link)
	}
	if order != nil {
		t.Fatal("the bot's order was applied before delivery")
	}
	eta := pending.ETATicks
	for i := int64(0); i < eta+5; i++ {
		_ = r.Step(ctx)
	}
	_ = r.Inspect(ctx, func(g *game.Game) { d, _ := g.Division(far); order = d.CurrentOrder })
	if order == nil || order.PlayerID != bot {
		t.Fatal("the bot's order must be applied after delivery")
	}
	if logs.count("ai order rejected") != 0 {
		t.Fatal("rejected bot orders")
	}
}
