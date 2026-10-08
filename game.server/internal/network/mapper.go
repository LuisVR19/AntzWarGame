package network

import (
	"strings"

	"gameserver/internal/app"
	"gameserver/internal/game"
	"gameserver/internal/terrain"
)

// Enum values travel in lowercase on the wire ("moving", "running", ...).
func wire[T ~string](v T) string { return strings.ToLower(string(v)) }

func toPosition(p game.Position) PositionDTO { return PositionDTO{X: p.X, Y: p.Y} }

func toMap(m *terrain.Map) MapDTO {
	dto := MapDTO{
		Width: m.Width(), Height: m.Height(), CellSize: m.CellSize, Cols: m.Cols, Rows: m.Rows,
		Tiles:   m.EncodeRows(),
		Legend:  map[string]string{},
		Terrain: map[string]TerrainModifiersDTO{},
	}
	for _, t := range terrain.AllTypes {
		mod := m.Table().Get(t)
		dto.Legend[string(t.Code())] = wire(t)
		dto.Terrain[wire(t)] = TerrainModifiersDTO{Movement: mod.Movement, Attack: mod.Attack, Defense: mod.Defense, Visibility: mod.Visibility}
	}
	for _, s := range m.Spawns {
		dto.Spawns = append(dto.Spawns, toPosition(s))
	}
	return dto
}

func toOrder(o *game.OrderView) *OrderDTO {
	if o == nil {
		return nil
	}
	dto := &OrderDTO{ID: o.ID, Type: wire(o.Type), TargetDivisionID: string(o.TargetDivisionID)}
	if o.TargetPosition != nil {
		p := toPosition(*o.TargetPosition)
		dto.TargetPosition = &p
	}
	return dto
}

func toDivision(d game.DivisionView) DivisionDTO {
	dto := DivisionDTO{
		ID: string(d.ID), PlayerID: string(d.PlayerID), Name: d.Name,
		X: d.Position.X, Y: d.Position.Y,
		UnitCount: d.UnitCount, MaxUnitCount: d.MaxUnitCount,
		Attack: d.Attack, Defense: d.Defense, Speed: d.Speed,
		Morale: round2(d.Morale), Experience: round2(d.Experience), Fatigue: round2(d.Fatigue),
		State: wire(d.State), Routed: d.Routed, InBattle: d.InBattle, Terrain: wire(d.Terrain),
		Order: toOrder(d.Order),
	}
	for _, p := range d.Path {
		dto.Path = append(dto.Path, toPosition(p))
	}
	return dto
}

func toPlayers(v *game.GameView) []PlayerDTO {
	out := make([]PlayerDTO, 0, len(v.Players))
	for _, p := range v.Players {
		out = append(out, PlayerDTO{ID: string(p.ID), Name: p.Name, Side: int(p.Side), Ready: p.Ready, Connected: p.Connected, Bot: p.Bot})
	}
	return out
}

func toGameState(v *game.GameView) GameStateMessage {
	msg := GameStateMessage{
		Type: MsgGameState, GameID: v.ID, Status: wire(v.Status), Tick: v.Tick,
		Divisions: make([]DivisionDTO, 0, len(v.Divisions)),
		Battles:   make([]BattleDTO, 0, len(v.Battles)),
	}
	if v.Status == game.StatusStarting {
		msg.CountdownTicks = v.CountdownTicks
	}
	for _, d := range v.Divisions {
		msg.Divisions = append(msg.Divisions, toDivision(d))
	}
	for _, b := range v.Battles {
		msg.Battles = append(msg.Battles, BattleDTO{
			ID: b.ID, AttackerID: string(b.AttackerID), DefenderID: string(b.DefenderID),
			X: b.Position.X, Y: b.Position.Y, StartedTick: b.StartedTick, Rounds: b.Rounds,
			AttackerLosses: b.AttackerLosses, DefenderLosses: b.DefenderLosses,
		})
	}
	return msg
}

func toBattleSide(s game.BattleSideReport) BattleSideDTO {
	return BattleSideDTO{
		DivisionID: string(s.DivisionID), Losses: s.Losses, UnitCount: s.UnitCount,
		Morale: round2(s.Morale), Fatigue: round2(s.Fatigue),
		EffectiveAttack: round2(s.EffectiveAttack), EffectiveDefense: round2(s.EffectiveDefense),
	}
}

// encodeOutput converts an application output into a protocol message.
// It returns nil for outputs that have no wire representation.
func encodeOutput(out app.Output, tickRate int) any {
	switch out.Kind {
	case app.OutJoined:
		typ := MsgGameJoined
		if out.Join.Created {
			typ = MsgGameCreated
		}
		return GameJoinedMessage{
			Type: typ, RequestID: out.RequestID, GameID: out.GameID,
			PlayerID: string(out.Join.PlayerID), SessionToken: out.Join.SessionToken,
			Side: int(out.Join.Side), Reconnected: out.Join.Reconnected, TickRate: tickRate,
			Map: toMap(out.Join.Map), State: toGameState(out.View),
		}
	case app.OutLobby:
		return LobbyUpdatedMessage{Type: MsgLobbyUpdated, GameID: out.GameID, Status: wire(out.View.Status), Players: toPlayers(out.View)}
	case app.OutGameStarted:
		return GameStartedMessage{Type: MsgGameStarted, GameID: out.GameID, Tick: out.View.Tick, State: toGameState(out.View)}
	case app.OutSnapshot:
		return toGameState(out.View)
	case app.OutEvent:
		return encodeEvent(out)
	}
	return nil
}

func encodeEvent(out app.Output) any {
	switch ev := out.Event.(type) {
	case game.DivisionUpdated:
		if out.Division == nil {
			return nil
		}
		return DivisionUpdatedMessage{Type: MsgDivisionUpdated, Tick: ev.At, Reason: ev.Reason, Division: toDivision(*out.Division)}
	case game.BattleStarted:
		return BattleStartedMessage{
			Type: MsgBattleStarted, Tick: ev.At, BattleID: ev.BattleID,
			AttackerID: string(ev.AttackerID), DefenderID: string(ev.DefenderID), X: ev.Position.X, Y: ev.Position.Y,
		}
	case game.BattleUpdated:
		return BattleUpdatedMessage{
			Type: MsgBattleUpdated, Tick: ev.At, BattleID: ev.BattleID, Round: ev.Round,
			Attacker: toBattleSide(ev.Attacker), Defender: toBattleSide(ev.Defender),
		}
	case game.BattleEnded:
		return BattleEndedMessage{
			Type: MsgBattleEnded, Tick: ev.At, BattleID: ev.BattleID, Reason: ev.Reason,
			AttackerID: string(ev.AttackerID), DefenderID: string(ev.DefenderID), WinnerDivisionID: string(ev.WinnerDivisionID),
		}
	case game.DivisionDestroyed:
		return DivisionDestroyedMessage{Type: MsgDivisionDestroyed, Tick: ev.At, DivisionID: string(ev.DivisionID), PlayerID: string(ev.PlayerID), BattleID: ev.BattleID}
	case game.GameFinished:
		result := "draw"
		switch {
		case ev.WinnerID == "":
		case ev.WinnerID == out.Viewer:
			result = "victory"
		default:
			result = "defeat"
		}
		return GameFinishedMessage{Type: MsgGameFinished, Tick: ev.At, WinnerPlayerID: string(ev.WinnerID), Reason: ev.Reason, Result: result}
	}
	return nil
}

func errorMessage(requestID string, err error) ErrorMessage {
	if de, ok := err.(*game.Error); ok {
		return ErrorMessage{Type: MsgError, RequestID: requestID, Code: string(de.Code), Message: de.Message}
	}
	return ErrorMessage{Type: MsgError, RequestID: requestID, Code: "internal", Message: err.Error()}
}

func round2(v float64) float64 {
	if v < 0 {
		return -round2(-v)
	}
	return float64(int64(v*100+0.5)) / 100
}
