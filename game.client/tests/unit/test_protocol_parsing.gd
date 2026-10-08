extends "res://tests/framework/test_case.gd"
## Orders -> messages, server messages -> client model. The sample messages
## have the exact shape the Go server sends (see game.server/README.md).

const SERVER_DIVISION := {
	"id": "division-1", "player_id": "player-1", "name": "1st Infantry",
	"x": 230.5, "y": 450, "unit_count": 2940, "max_unit_count": 3000,
	"attack": 10, "defense": 12, "speed": 30, "morale": 76.5, "experience": 10.4,
	"fatigue": 3.2, "state": "attacking", "routed": false, "in_battle": true, "terrain": "plain",
	"order": {"id": "order-3", "type": "attack", "target_division_id": "division-4"},
	"path": [{"x": 400, "y": 450}],
}


func test_order_messages_match_server_protocol() -> bool:
	var move := Order.move("division-1", Vector2(640, 420)).to_message()
	check_eq(move, {"division_id": "division-1", "type": "move_division", "x": 640.0, "y": 420.0}, "MOVE")
	var attack := Order.attack("division-1", "division-4").to_message()
	check_eq(attack, {"division_id": "division-1", "type": "attack_division", "target_division_id": "division-4"}, "ATTACK")
	check_eq(Order.defend("d").to_message()["type"], "defend_division", "DEFEND")
	check_eq(Order.hold("d").to_message()["type"], "hold_division", "HOLD")
	var retreat := Order.retreat("d").to_message()
	check_eq(retreat["type"], "retreat_division", "RETREAT")
	check(not retreat.has("x"), "RETREAT sin destino no envía x/y (vuelve a la base)")
	check(Order.move("d", Vector2.ZERO).timestamp > 0.0, "timestamp")
	return done()


func test_division_from_server_message() -> bool:
	var d := DivisionData.from_protocol(SERVER_DIVISION)
	check_eq(d.id, "division-1", "id")
	check_eq(d.display_name, "1st Infantry", "nombre")
	check_eq(d.position, Vector2(230.5, 450), "posición")
	check_eq(d.unit_count, 2940, "unidades")
	check_eq(d.state, GameTypes.STATE_ATTACKING, "estado en mayúsculas")
	check_eq(d.terrain, "PLAIN", "terreno")
	check(d.in_battle, "en combate")
	check(d.order != null and d.order.type == Order.ATTACK, "orden ATTACK")
	check_eq(d.order.target_division_id, "division-4", "objetivo")
	check_eq(d.path.size(), 1, "ruta")
	check_near(d.strength_ratio(), 0.98, 0.001, "fuerza relativa")
	var bare := DivisionData.from_protocol({"id": "x", "state": "idle"})
	check(bare.order == null and bare.path.is_empty(), "campos opcionales ausentes")
	return done()


func test_battle_state_snapshot_replaces_divisions() -> bool:
	var state := BattleState.new()
	var other := SERVER_DIVISION.duplicate(true)
	other["id"] = "division-4"
	other["player_id"] = "player-2"
	state.apply_snapshot({"type": "game_state", "tick": 5, "status": "running",
		"divisions": [SERVER_DIVISION, other],
		"battles": [{"id": "battle-1", "attacker_id": "division-1", "defender_id": "division-4", "x": 300, "y": 450, "rounds": 2}]})
	check_eq(state.tick, 5, "tick")
	check_eq(state.status, GameTypes.STATUS_RUNNING, "estado")
	check_eq(state.division_ids.size(), 2, "divisiones")
	check_eq(state.battles.size(), 1, "batallas")
	check_eq(state.battles[0]["position"], Vector2(300, 450), "posición de batalla")
	state.apply_snapshot({"type": "game_state", "tick": 6, "status": "running", "divisions": [other], "battles": []})
	check(state.get_division("division-1") == null, "una división ausente del snapshot se elimina")
	check_eq(state.division_ids.size(), 1, "queda una división")
	check_eq(state.division_ids[0], "division-4", "la que sigue en el snapshot")
	return done()


func test_players_and_sides() -> bool:
	var state := BattleState.new()
	state.set_players([{"id": "player-7", "name": "Ana", "side": 1, "ready": true, "connected": true}])
	check_eq(state.side_of("player-7"), 1, "lado desde el lobby")
	check_eq(state.player_name("player-7"), "Ana", "nombre")
	check_eq(state.player_name("desconocido"), "desconocido", "nombre por defecto")
	return done()


func test_source_parses_session_and_results() -> bool:
	var src := GameStateSource.new()
	var finished := []
	var rejected := []
	src.game_finished.connect(func(result: String, reason: String, _w: String) -> void: finished.append([result, reason]))
	src.order_rejected.connect(func(code: String, _m: String) -> void: rejected.append(code))
	var map := MapData.from_definitions().to_protocol()
	src._handle_message({"type": "game_joined", "game_id": "game-1", "player_id": "player-2",
		"session_token": "tok-1", "side": 1, "tick_rate": 20, "map": map,
		"state": {"tick": 0, "status": "waiting", "divisions": [], "battles": []}})
	check_eq(src.local_player_id, "player-2", "jugador local")
	check_eq(src.session_token, "tok-1", "token de reconexión")
	check_eq(src.state.tick_rate, 20, "tick rate del servidor")
	check(src.map_data != null and src.map_data.cols == 40, "mapa del servidor")
	src._handle_message({"type": "lobby_updated", "status": "starting",
		"players": [{"id": "player-1", "name": "A", "side": 0}, {"id": "player-2", "name": "B", "side": 1}]})
	check_eq(src.state.status, GameTypes.STATUS_STARTING, "estado del lobby")
	src._handle_message({"type": "error", "code": "not_owner", "message": "x"})
	check_eq(rejected, ["not_owner"], "error -> order_rejected")
	src._handle_message({"type": "game_finished", "tick": 9, "winner_player_id": "player-2", "reason": "annihilation"})
	check_eq(finished, [["victory", "annihilation"]], "resultado calculado para el jugador local")
	src._handle_message({"type": "game_finished", "tick": 9, "winner_player_id": "", "reason": "time_limit"})
	check_eq(finished[1][0], "draw", "empate")
	src.free()
	return done()


func test_split_merge_messages_and_events() -> bool:
	check_eq(Order.split("division-1").to_message(), {"division_id": "division-1", "type": "split_division", "ratio": 0.5}, "split_division")
	check_eq(Order.merge("division-1", "division-3").to_message(),
		{"division_id": "division-1", "type": "merge_division", "target_division_id": "division-3"}, "merge_division")
	var source := GameStateSource.new()
	source.state.apply_snapshot({"divisions": [{"id": "division-1", "player_id": "p1", "unit_count": 3000}]})
	source._handle_message({"type": "division_split", "tick": 5,
		"division": {"id": "division-1", "player_id": "p1", "unit_count": 1500},
		"new_division": {"id": "division-7", "player_id": "p1", "unit_count": 1500}})
	check(source.state.get_division("division-7") != null, "division_split añade la nueva división")
	check_eq(source.state.get_division("division-1").unit_count, 1500, "y actualiza la original")
	source._handle_message({"type": "divisions_merged", "tick": 9, "division_id": "division-1",
		"merged_division_id": "division-7", "division": {"id": "division-1", "player_id": "p1", "unit_count": 3000}})
	check(source.state.get_division("division-7") == null, "divisions_merged elimina la absorbida")
	check_eq(source.state.get_division("division-1").unit_count, 3000, "y actualiza la resultante")
	source.free()
	return done()


func test_formation_message_and_fields() -> bool:
	check_eq(Order.change_formation("division-1", Formations.SHIELD_WALL).to_message(),
		{"division_id": "division-1", "type": "set_formation", "formation": "shield_wall"}, "set_formation")
	var d := DivisionData.from_protocol({"id": "d", "formation": "wedge", "facing": 1.5, "reforming": true})
	check_eq(d.formation, Formations.WEDGE, "formación")
	check_near(d.facing, 1.5, 0.001, "orientación")
	check(d.reforming, "reorganizándose")
	check_eq(DivisionData.from_protocol({"id": "d"}).formation, Formations.LINE, "sin el campo (servidor Go): línea")
	return done()
