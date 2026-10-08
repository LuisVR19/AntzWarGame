extends "res://tests/framework/test_case.gd"
## Chain of command on the client: parsing of the server state (generals,
## commanders, messengers, command fields of divisions), helpers, log texts
## and the assign_commander message. Shapes match game.server/README.md.

const SNAPSHOT := {
	"type": "game_state", "tick": 40, "status": "running",
	"divisions": [
		{"id": "division-1", "player_id": "player-1", "name": "1st Infantry", "x": 200, "y": 450, "unit_count": 3000,
			"state": "idle", "commander_id": "commander-1", "command_link": "in_range"},
		{"id": "division-2", "player_id": "player-1", "name": "2nd Infantry", "x": 700, "y": 600, "unit_count": 3000,
			"state": "idle", "commander_id": "commander-1", "command_link": "out_of_range",
			"pending_order": {"messenger_id": "messenger-3", "eta_ticks": 45,
				"order": {"id": "order-7", "type": "defend"}}},
		{"id": "division-4", "player_id": "player-2", "name": "Enemy", "x": 1800, "y": 450, "unit_count": 3000, "state": "idle"},
	],
	"battles": [],
	"commanders": [
		{"id": "commander-1", "player_id": "player-1", "role": "commander", "name": "Infantry Command",
			"host_division_id": "division-1", "x": 200, "y": 450, "status": "active", "comm_radius": 350, "influence_radius": 350},
		{"id": "general-2", "player_id": "player-1", "role": "general", "name": "General",
			"host_division_id": "division-2", "x": 700, "y": 600, "status": "incapacitated", "comm_radius": 450, "influence_radius": 450},
		{"id": "general-5", "player_id": "player-2", "role": "general", "name": "General",
			"host_division_id": "division-4", "x": 1800, "y": 450, "status": "active", "comm_radius": 450, "influence_radius": 450},
	],
	"messengers": [
		{"id": "messenger-3", "sender_id": "commander-1", "division_id": "division-2", "x": 400, "y": 520,
			"sent_tick": 30, "eta_ticks": 45, "order": {"id": "order-7", "type": "defend"}},
	],
}


func _state() -> BattleState:
	var state := BattleState.new()
	state.tick_rate = 10
	state.apply_snapshot(SNAPSHOT)
	return state


func test_snapshot_with_chain_of_command() -> bool:
	var state := _state()
	check(state.has_chain_of_command(), "hay cadena de mando")
	check_eq(state.commander_ids.size(), 3, "generales y comandantes")
	var commander := state.get_command("commander-1")
	check(commander != null and not commander.is_general() and commander.is_active(), "comandante activo")
	check_eq(commander.comm_radius, 350.0, "radio de comunicación")
	check_eq(commander.influence_radius, 350.0, "radio de influencia")
	check_eq(commander.host_division_id, "division-1", "división anfitriona")
	var general := state.get_command("general-2")
	check(general.is_general() and general.status == CommandData.STATUS_INCAPACITATED, "general incapacitado")
	check(general.is_alive() and not general.is_active(), "incapacitado no es eliminado")
	check_eq(state.subordinates("commander-1").size(), 2, "divisiones subordinadas")
	check_eq(state.messengers.size(), 1, "mensajero en tránsito")
	check_eq(state.messengers[0]["position"], Vector2(400, 520), "posición del mensajero")
	check_eq((state.messengers[0]["order"] as Order).type, Order.DEFEND, "orden que transporta")

	var far := state.get_division("division-2")
	check_eq(far.commander_id, "commander-1", "comandante asignado")
	check_eq(far.command_link, CommandData.LINK_OUT_OF_RANGE, "fuera de rango")
	check(far.pending_order != null and far.pending_order.type == Order.DEFEND, "orden pendiente")
	check_eq(far.pending_eta_ticks, 45, "ETA en ticks")
	check_near(state.ticks_to_seconds(far.pending_eta_ticks), 4.5, 0.001, "ETA en segundos")
	var enemy := state.get_division("division-4")
	check(enemy.command_link.is_empty() and enemy.pending_order == null, "sin datos de mando del rival")

	state.apply_snapshot({"tick": 41, "status": "running", "divisions": [], "battles": []})
	check(not state.has_chain_of_command() and state.messengers.is_empty(), "sin cadena de mando (simulación local)")
	return done()


func test_source_applies_command_events() -> bool:
	var src := GameStateSource.new()
	src.state.apply_snapshot(SNAPSHOT)
	var events := []
	src.game_event.connect(func(e: GameEvent) -> void: events.append(e.type))
	src._handle_message({"type": "command_updated", "tick": 50, "command_id": "commander-1", "player_id": "player-1",
		"role": "commander", "status": "eliminated", "reason": "host_destroyed"})
	check_eq(src.state.get_command("commander-1").status, CommandData.STATUS_ELIMINATED, "estado actualizado al instante")
	src._handle_message({"type": "command_updated", "tick": 60, "command_id": "general-2", "player_id": "player-1",
		"role": "general", "status": "active", "reason": "host_rallied"})
	src._handle_message({"type": "messenger_updated", "tick": 70, "messenger_id": "messenger-3", "division_id": "division-2",
		"status": "delivered", "reason": "delivered", "order": {"id": "order-7", "type": "defend"}})
	check_eq(events, ["command_updated", "command_updated", "messenger_updated"], "eventos para el registro")
	check(not src.supports_command(), "la fuente abstracta no tiene cadena de mando")
	src.free()
	return done()


func test_log_texts() -> bool:
	var state := _state()
	state.set_players([{"id": "player-1", "name": "Ana", "side": 0}, {"id": "player-2", "name": "IA", "side": 1}])
	var messenger := _format({"type": "order_accepted", "division_id": "division-2", "delivery": "messenger",
		"messenger_id": "messenger-3", "eta_ticks": 45, "order": {"id": "order-7", "type": "defend"}}, state)
	check(messenger.contains("mensajero") and messenger.contains("~5 s"), "orden con mensajero y ETA: %s" % messenger)
	var immediate := _format({"type": "order_accepted", "division_id": "division-1", "delivery": "immediate",
		"order": {"id": "order-8", "type": "hold"}}, state)
	check(immediate.contains("inmediata"), "orden inmediata: %s" % immediate)
	var delivered := _format({"type": "messenger_updated", "division_id": "division-2", "status": "delivered",
		"reason": "delivered", "order": {"type": "defend"}}, state)
	check(delivered.contains("recibió"), "entrega: %s" % delivered)
	var superseded := _format({"type": "messenger_updated", "division_id": "division-2", "status": "cancelled",
		"reason": "superseded", "order": {"type": "defend"}}, state)
	check(superseded.contains("sustituye"), "sustitución: %s" % superseded)
	var invalid := _format({"type": "messenger_updated", "division_id": "division-2", "status": "cancelled",
		"reason": "target_destroyed", "order": {"type": "attack"}}, state)
	check(invalid.contains("ya no era válida"), "orden inválida al llegar: %s" % invalid)
	check(_format({"type": "messenger_updated", "status": "pending", "reason": "dispatched", "order": {}}, state).is_empty(),
		"el envío no se repite en el registro")
	var fallen := _format({"type": "command_updated", "command_id": "commander-1", "player_id": "player-1",
		"status": "eliminated", "reason": "host_destroyed"}, state)
	check(fallen.contains("Infantry Command") and fallen.contains("Ana") and fallen.contains("caído"), "caída: %s" % fallen)
	var promoted := _format({"type": "command_updated", "command_id": "commander-1", "player_id": "player-1",
		"status": "active", "reason": "promoted"}, state)
	check(promoted.contains("general"), "sucesión: %s" % promoted)
	return done()


func _format(msg: Dictionary, state: BattleState) -> String:
	return str(EventFormatter.format(GameEvent.from_message(msg), state).get("text", ""))


func test_assign_commander_message() -> bool:
	check_eq(Protocol.assign_commander("division-2", "commander-1"),
		{"type": "assign_commander", "division_id": "division-2", "commander_id": "commander-1"}, "assign_commander")
	var network := NetworkGameState.new()
	var local := LocalGameState.new()
	check(network.supports_command(), "el servidor Go tiene cadena de mando")
	check(not local.supports_command(), "la simulación local no")
	network.free()
	local.free()
	check_eq(CommandData.link_label(""), "-", "sin cadena de mando")
	return done()


func test_general_leads_divisions_without_commander() -> bool:
	var state := _state()
	var direct := DivisionData.from_protocol({"id": "division-3", "player_id": "player-1", "name": "1st Armored", "state": "idle"})
	state.upsert_division(direct)
	var ids := []
	for d in state.subordinates("general-2"):
		ids.append(d.id)
	check(ids.has("division-3"), "división sin comandante: depende del general")
	check(not ids.has("division-1"), "las del comandante activo no")
	state.set_command_status("commander-1", CommandData.STATUS_ELIMINATED, CommandData.ROLE_COMMANDER)
	ids.clear()
	for d in state.subordinates("general-2"):
		ids.append(d.id)
	check(ids.has("division-1") and ids.has("division-2"), "al caer su comandante pasan al general")
	return done()
