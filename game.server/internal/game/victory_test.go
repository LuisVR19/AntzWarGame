package game

import "testing"

func lastFinished(t *testing.T, events []GameEvent) GameFinished {
	t.Helper()
	for i := len(events) - 1; i >= 0; i-- {
		if f, ok := events[i].(GameFinished); ok {
			return f
		}
	}
	t.Fatal("no game_finished event")
	return GameFinished{}
}

func TestVictoryByAnnihilation(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	tg.div(t, tg.p2, 0).State = StateDestroyed
	ev := tg.Tick()
	if tg.Status != StatusFinished || tg.WinnerID != tg.p1 || tg.FinishReason != "annihilation" {
		t.Fatalf("status=%s winner=%s reason=%s", tg.Status, tg.WinnerID, tg.FinishReason)
	}
	if f := lastFinished(t, ev); f.WinnerID != tg.p1 {
		t.Fatalf("event winner %s", f.WinnerID)
	}
	// A finished game no longer simulates.
	tick := tg.CurrentTick
	tg.Tick()
	if tg.CurrentTick != tick {
		t.Fatal("finished game kept ticking")
	}
}

func TestMutualAnnihilationIsDraw(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	tg.div(t, tg.p1, 0).State = StateDestroyed
	tg.div(t, tg.p2, 0).State = StateDestroyed
	tg.Tick()
	if tg.Status != StatusFinished || tg.WinnerID != "" {
		t.Fatalf("status=%s winner=%q", tg.Status, tg.WinnerID)
	}
}

func TestVictoryByTimeLimit(t *testing.T) {
	r := oneDivisionRules()
	r.MaxDurationTicks = 20
	tg := newRunningGame(t, plainMap(t), r)
	tg.div(t, tg.p1, 0).UnitCount = 2500
	tg.run(19)
	if tg.Status != StatusRunning {
		t.Fatal("finished too early")
	}
	tg.Tick()
	if tg.Status != StatusFinished || tg.WinnerID != tg.p2 || tg.FinishReason != "time_limit" {
		t.Fatalf("status=%s winner=%s reason=%s", tg.Status, tg.WinnerID, tg.FinishReason)
	}
}

func TestVictoryByDisconnect(t *testing.T) {
	r := oneDivisionRules()
	r.DisconnectGraceTicks = 10
	tg := newRunningGame(t, plainMap(t), r)
	tg.SetConnected(tg.p1, false)
	tg.run(5)
	tg.SetConnected(tg.p1, true) // reconnect resets the grace period
	tg.run(20)
	if tg.Status != StatusRunning {
		t.Fatal("reconnected player must not forfeit")
	}
	tg.SetConnected(tg.p2, false)
	tg.run(10)
	if tg.Status != StatusFinished || tg.WinnerID != tg.p1 || tg.FinishReason != "opponent_disconnected" {
		t.Fatalf("status=%s winner=%s reason=%s", tg.Status, tg.WinnerID, tg.FinishReason)
	}
}

func TestForfeitAndAbort(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	if err := tg.Forfeit(tg.p2, "surrender"); err != nil {
		t.Fatal(err)
	}
	if tg.WinnerID != tg.p1 {
		t.Fatalf("winner %s", tg.WinnerID)
	}
	if err := tg.Forfeit(tg.p1, "surrender"); err == nil {
		t.Fatal("cannot forfeit a finished game")
	}

	tg2 := newRunningGame(t, plainMap(t), oneDivisionRules())
	tg2.Abort("abandoned")
	if tg2.Status != StatusFinished || tg2.WinnerID != "" {
		t.Fatal("abort must finish without winner")
	}
}

func TestLobbyRules(t *testing.T) {
	tg := newRunningGame(t, plainMap(t), oneDivisionRules())
	if _, err := tg.AddPlayer("late", "x"); CodeOf(err) != CodeInvalidState {
		t.Fatalf("join running game: %v", err)
	}
	if p, ok := tg.PlayerByToken("tok-b"); !ok || p.ID != tg.p2 {
		t.Fatal("token lookup failed")
	}
	if _, ok := tg.PlayerByToken(""); ok {
		t.Fatal("empty token must not match")
	}
}
