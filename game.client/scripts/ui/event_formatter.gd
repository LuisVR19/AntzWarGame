class_name EventFormatter
extends RefCounted
## Turns GameEvents and Orders into short Spanish texts for the UI.
## Returns {} for events that should not be logged (to avoid spam).

const BATTLE_END_REASONS := {
	"destroyed": "una división fue destruida",
	"disengaged": "las tropas se separaron",
}
const BLOW_TEXT := {"flank": "¡por el flanco!", "rear": "¡por la retaguardia!"}
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
			return _division_update(data, state)
		"battle_started":
			var attacker := state.division_name(str(data.get("attacker_id", "")))
			var defender := state.division_name(str(data.get("defender_id", "")))
			var text := "%s detectó al enemigo: combate iniciado contra %s" % [attacker, defender]
			var side := str(data.get("defender_exposure", Formations.FRONT))
			if BLOW_TEXT.has(side):
				text += " " + BLOW_TEXT[side]
			return _entry(text, Palette.LOG_COMBAT)
		"battle_updated":
			var a: Dictionary = data.get("attacker", {})
			var d: Dictionary = data.get("defender", {})
			return _entry("Ronda %d: %s -%d (%d)  |  %s -%d (%d)" % [
				int(data.get("round", 0)),
				_fighter(state, a), int(a.get("losses", 0)), int(a.get("unit_count", 0)),
				_fighter(state, d), int(d.get("losses", 0)), int(d.get("unit_count", 0)),
			], Palette.LOG_COMBAT.darkened(0.25))
		"battle_ended":
			var reason := str(BATTLE_END_REASONS.get(str(data.get("reason", "")), data.get("reason", "")))
			var winner := str(data.get("winner_division_id", ""))
			var text := "Combate terminado: %s" % reason
			if not winner.is_empty():
				text += " (vence %s)" % state.division_name(winner)
			return _entry(text, Palette.LOG_COMBAT)
		"volley":
			var text := "%s lanza ácido a %s: -%d (%d)" % [
				state.division_name(str(data.get("shooter_id", ""))), state.division_name(str(data.get("target_id", ""))),
				int(data.get("losses", 0)), int(data.get("unit_count", 0)),
			]
			var side := str(data.get("exposure", Formations.FRONT))
			if side != Formations.FRONT:
				text += " [%s]" % Formations.side_label(side)
			return _entry(text, Palette.ACID.darkened(0.2))
		"division_split":
			var original := str(data.get("division", {}).get("name", ""))
			var created := str(data.get("new_division", {}).get("name", ""))
			return _entry("%s se dividió: nace %s" % [original, created], Palette.LOG_GOOD)
		"divisions_merged":
			var result := str(data.get("division", {}).get("name", ""))
			return _entry("%s absorbió a %s" % [result, str(data.get("merged_division_name", ""))], Palette.LOG_GOOD)
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
			if order.automatic:
				return "Ayudar a un aliado: atacar a %s" % state.division_name(order.target_division_id)
			return "Atacar a %s" % state.division_name(order.target_division_id)
		"DEFEND":
			return "Defender posición"
		"RETREAT":
			return "Retirarse"
		"HOLD":
			return "Mantener posición"
		"MERGE":
			return "Unirse a %s" % state.division_name(order.target_division_id)
	return order.type


static func _division_update(data: Dictionary, state: BattleState) -> Dictionary:
	var division: Dictionary = data.get("division", {})
	var who := str(division.get("name", division.get("id", "")))
	if str(data.get("reason", "")) == "assisting":
		var target := str(division.get("order", {}).get("target_division_id", ""))
		return _entry("%s acude en ayuda de un aliado: ataca a %s" % [who, state.division_name(target)], Palette.LOG_COMBAT)
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
		"formation_changed":
			return _entry("%s adopta la formación %s (reorganizándose)" % [who, _formation_of(division)], Palette.LOG_INFO)
		"formation_ready":
			return _entry("%s ya está en formación %s" % [who, _formation_of(division)], Palette.LOG_GOOD)
		"merge_target_lost":
			return _entry("%s: la división con la que iba a unirse ya no existe" % who, Palette.LOG_INFO)
		"merge_failed":
			return _entry("%s no pudo unirse: una de las dos está en combate" % who, Palette.LOG_ERROR)
	return {}


## Name of a fighter in a battle round, tagged when hit on a flank or rear.
static func _fighter(state: BattleState, side: Dictionary) -> String:
	var text := state.division_name(str(side.get("division_id", "")))
	var exposure := str(side.get("exposure", Formations.FRONT))
	if exposure != Formations.FRONT:
		text += " [%s]" % Formations.side_label(exposure)
	return text


static func _formation_of(division: Dictionary) -> String:
	return Formations.label(GameTypes.from_wire(str(division.get("formation", "line"))))


static func _entry(text: String, color: Color) -> Dictionary:
	return {"text": text, "color": color}
