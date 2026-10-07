class_name EventFormatter
extends RefCounted
## Turns GameEvents and Orders into short Spanish texts for the UI.
## Returns {} for events that should not be logged (to avoid spam).

const BATTLE_END_REASONS := {
	"destroyed": "una división fue destruida",
	"disengaged": "las tropas se separaron",
}
const FINISH_REASONS := {
	"annihilation": "ejército enemigo aniquilado",
	"mutual_annihilation": "ambos ejércitos aniquilados",
	"time_limit": "límite de tiempo",
	"opponent_disconnected": "el rival se desconectó",
	"abandoned": "partida abandonada",
}


static func format(event: GameEvent, state: BattleState) -> Dictionary:
	var data := event.data
	match event.type:
		"game_started":
			return _entry("¡La batalla comienza!", Palette.LOG_GOOD)
		"order_accepted":
			var order := Order.from_protocol(data.get("order", {}))
			var who := state.division_name(str(data.get("division_id", "")))
			return _entry("%s recibió orden de %s" % [who, Order.label(order.type)], Palette.LOG_INFO)
		"division_updated":
			return _division_update(data)
		"battle_started":
			var attacker := state.division_name(str(data.get("attacker_id", "")))
			var defender := state.division_name(str(data.get("defender_id", "")))
			return _entry("%s detectó al enemigo: combate iniciado contra %s" % [attacker, defender], Palette.LOG_COMBAT)
		"battle_updated":
			var a: Dictionary = data.get("attacker", {})
			var d: Dictionary = data.get("defender", {})
			return _entry("Ronda %d: %s -%d (%d)  |  %s -%d (%d)" % [
				int(data.get("round", 0)),
				state.division_name(str(a.get("division_id", ""))), int(a.get("losses", 0)), int(a.get("unit_count", 0)),
				state.division_name(str(d.get("division_id", ""))), int(d.get("losses", 0)), int(d.get("unit_count", 0)),
			], Palette.LOG_COMBAT.darkened(0.25))
		"battle_ended":
			var reason := str(BATTLE_END_REASONS.get(str(data.get("reason", "")), data.get("reason", "")))
			var winner := str(data.get("winner_division_id", ""))
			var text := "Combate terminado: %s" % reason
			if not winner.is_empty():
				text += " (vence %s)" % state.division_name(winner)
			return _entry(text, Palette.LOG_COMBAT)
		"division_destroyed":
			return _entry("%s fue destruida" % state.division_name(str(data.get("division_id", ""))), Palette.LOG_ERROR)
		"game_finished":
			return _entry("Partida terminada: %s" % finish_reason(str(data.get("reason", ""))), Palette.LOG_GOOD)
	return {}


static func finish_reason(reason: String) -> String:
	return str(FINISH_REASONS.get(reason, reason))


## Human-readable current order of a division.
static func describe_order(order: Order, state: BattleState) -> String:
	if order == null:
		return "Ninguna"
	match order.type:
		"MOVE":
			return "Mover a (%d, %d)" % [roundi(order.target_position.x), roundi(order.target_position.y)]
		"ATTACK":
			return "Atacar a %s" % state.division_name(order.target_division_id)
		"DEFEND":
			return "Defender posición"
		"RETREAT":
			return "Retirarse"
		"HOLD":
			return "Mantener posición"
	return order.type


static func _division_update(data: Dictionary) -> Dictionary:
	var division: Dictionary = data.get("division", {})
	var who := str(division.get("name", division.get("id", "")))
	match str(data.get("reason", "")):
		"arrived":
			return _entry("%s llegó a su destino" % who, Palette.LOG_INFO)
		"blocked":
			return _entry("%s se detuvo: terreno intransitable" % who, Palette.LOG_ERROR)
		"routed":
			return _entry("%s se desbanda y huye hacia su base" % who, Palette.LOG_ERROR)
		"rallied":
			return _entry("%s se reagrupó" % who, Palette.LOG_GOOD)
		"target_destroyed":
			return _entry("%s: objetivo eliminado" % who, Palette.LOG_INFO)
	return {}


static func _entry(text: String, color: Color) -> Dictionary:
	return {"text": text, "color": color}
