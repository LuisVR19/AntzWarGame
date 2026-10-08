package game

import (
	"strings"
	"testing"

	"gameserver/internal/combat"
)

func TestAddBotTakesSecondSideAndIsReady(t *testing.T) {
	rules := oneDivisionRules()
	g, err := New("test", plainMap(t), rules, combat.NewSimpleEngine(rules.Combat))
	if err != nil {
		t.Fatal(err)
	}
	bot, err := g.AddBot("IA")
	if err != nil {
		t.Fatal(err)
	}
	if !bot.Bot || !bot.Ready || !bot.Connected || bot.Side != 1 || !strings.HasPrefix(string(bot.ID), "bot-") {
		t.Fatalf("unexpected bot player: %+v", bot)
	}
	if _, ok := g.PlayerByToken(""); ok {
		t.Fatal("the bot must not be reachable with an empty session token")
	}
	human, err := g.AddPlayer("alice", "tok-a")
	if err != nil {
		t.Fatal(err)
	}
	if human.Side != 0 || human.Bot || human.Ready {
		t.Fatalf("unexpected human player: %+v", human)
	}
	if _, err := g.AddBot("IA 2"); CodeOf(err) != CodeGameFull {
		t.Fatalf("third player: %v", err)
	}
	started, err := g.SetReady(human.ID, true)
	if err != nil || !started {
		t.Fatalf("the human's ready must start the game: started=%v err=%v", started, err)
	}
	if army, ok := g.Army(bot.ID); !ok || len(army.DivisionIDs) != len(rules.Army) {
		t.Fatal("the bot's army must be deployed like any other")
	}
	view := g.ViewFor(human.ID)
	if !view.Players[0].Bot || view.Players[1].Bot {
		t.Fatalf("player views must flag the bot: %+v", view.Players)
	}
}
