extends "res://tests/framework/test_case.gd"
## LocalGameSimulation: validation, game loop, movement, combat, morale and
## victory. Positions used are on PLAIN tiles of the default map
## (row 22 = y 1100, columns 8..14) unless the test needs other terrain.

const P1 := LocalGameSimulation.PLAYER_1
const P2 := LocalGameSimulation.PLAYER_2
const SOLO_ARMY := [
	{"name": "Prueba", "offset": {"x": 0, "y": 0}, "unit_count": 3000,
		"attack": 10, "defense": 10, "speed": 30, "morale": 80, "experience": 0},
]


# --- helpers -------------------------------------------------------------------

func _rules(overrides := {}) -> Dictionary:
	var r: Dictionary = Definitions.rules().duplicate(true)
	r["start_countdown_ticks"] = 0
	r.merge(overrides, true)
	return r


## Running simulation. With SOLO_ARMY: division-1 = P1, division-2 = P2.
func _sim(army: Array = SOLO_ARMY, overrides := {}) -> LocalGameSimulation:
	var sim := LocalGameSimulation.new(_rules(overrides), MapData.from_definitions(), army)
	sim.start()
	return sim


func _div(sim: LocalGameSimulation, id: String):
	return sim._by_id[id]


func _place(sim: LocalGameSimulation, id: String, pos: Vector2) -> void:
	var d = _div(sim, id)
	d.position = pos
	d.destination = pos


func _run(sim: LocalGameSimulation, ticks: int) -> Array:
	var out := []
	for i in ticks:
		out.append_array(sim.step())
	return out


func _run_until(sim: LocalGameSimulation, cond: Callable, max_ticks: int) -> Array:
	var out := []
	for i in max_ticks:
		if cond.call():
			break
		out.append_array(sim.step())
	return out


func _find(messages: Array, type: String, key := "", value: Variant = null) -> Dictionary:
	for m in messages:
		if m["type"] == type and (key.is_empty() or m.get(key) == value):
			return m
	return {}


func _count(messages: Array, type: String) -> int:
	var n := 0
	for m in messages:
		if m["type"] == type:
			n += 1
	return n


func _error_code(replies: Array) -> String:
	if replies.size() == 1 and replies[0]["type"] == "error":
		return str(replies[0]["code"])
	return "<sin error>"


func _move(sim: LocalGameSimulation, player: String, id: String, pos: Vector2) -> Array:
	return sim.handle(player, Order.move(id, pos).to_message())


func _attack(sim: LocalGameSimulation, id: String, target: String) -> Array:
	return sim.handle(P1, Order.attack(id, target).to_message())


# --- tests -----------------------------------------------------------------------

func test_start_countdown_then_running() -> bool:
	var sim := LocalGameSimulation.new(Definitions.rules(), MapData.from_definitions(), Definitions.army())
	var out := sim.start()
	check_eq(sim.status, GameTypes.STATUS_STARTING, "cuenta atrás")
	check_eq(_count(out, "lobby_updated"), 1, "lobby")
	check_eq(sim.divisions.size(), 6, "3 divisiones por jugador")
	var joined := sim.joined_message(P1)
	check_eq(joined["type"], "game_created", "mensaje de sesión")
	check_eq(joined["map"]["tiles"].size(), 24, "mapa incluido")
	var msgs := _run_until(sim, func() -> bool: return sim.status == GameTypes.STATUS_RUNNING, 100)
	check_eq(_count(msgs, "game_started"), 1, "game_started una vez")
	check_eq(sim.tick, 0, "la cuenta atrás no avanza ticks")
	var p1_x: float = _div(sim, "division-1").position.x
	var p2_x: float = _div(sim, "division-4").position.x
	check(p1_x < 500.0 and p2_x > 1500.0, "despliegue en lados opuestos")
	return done()


func test_order_validation() -> bool:
	var idle := LocalGameSimulation.new(_rules(), MapData.from_definitions(), Definitions.army())
	check_eq(_error_code(_move(idle, P1, "division-1", Vector2(300, 300))), "game_not_running", "antes de empezar")

	var sim := _sim(Definitions.army())
	_div(sim, "division-5").state = GameTypes.STATE_DESTROYED
	check_eq(_error_code(_move(sim, P1, "division-1", Vector2(975, 500))), "impassable_position", "agua")
	check_eq(_error_code(_move(sim, P1, "division-1", Vector2(-10, 50))), "invalid_position", "fuera del mapa")
	check_eq(_error_code(_move(sim, P1, "division-4", Vector2(300, 300))), "not_owner", "división del rival")
	check_eq(_error_code(_move(sim, P1, "division-99", Vector2(300, 300))), "division_not_found", "no existe")
	check_eq(_error_code(sim.handle(P1, {"type": "move_division", "division_id": "division-1"})), "target_required", "sin destino")
	check_eq(_error_code(_attack(sim, "division-1", "division-2")), "target_friendly", "aliada")
	check_eq(_error_code(_attack(sim, "division-1", "division-99")), "target_not_found", "objetivo inexistente")
	check_eq(_error_code(_attack(sim, "division-1", "division-5")), "target_destroyed", "objetivo destruido")
	check_eq(_error_code(sim.handle(P1, {"type": "teleport"})), "unknown_message_type", "tipo desconocido")
	check_eq(sim.handle(P1, {"type": "ready"}).size(), 0, "ready se ignora en local")

	var ok := _move(sim, P1, "division-1", Vector2(300, 300))
	check_eq(ok[0]["type"], "order_accepted", "orden válida")
	check_eq(ok[0]["order"]["type"], "move", "tipo en minúsculas")
	check(ok[0]["order"].has("target_position"), "destino incluido")
	var retreat := sim.handle(P1, Order.retreat("division-2").to_message())
	check_eq(retreat[0]["order"]["target_position"], {"x": 200.0, "y": 750.0}, "RETREAT sin destino va a su base")
	return done()


func test_move_applied_next_tick_and_arrives() -> bool:
	var sim := _sim()
	var d = _div(sim, "division-1")
	_move(sim, P1, "division-1", Vector2(200, 300))
	check_eq(d.state, GameTypes.STATE_IDLE, "la orden no se aplica hasta el siguiente tick")
	var first := sim.step()
	check_eq(_find(first, "division_updated").get("reason"), "order", "division_updated(order)")
	check_eq(d.state, GameTypes.STATE_MOVING, "MOVING")
	var snapshot := _find(first, "game_state")
	check_eq(snapshot["divisions"][0]["state"], "moving", "snapshot en minúsculas")
	check_eq(snapshot["divisions"][0]["path"].size(), 1, "ruta incluida")
	var msgs := _run_until(sim, func() -> bool: return d.order.is_empty(), 400)
	check(not _find(msgs, "division_updated", "reason", "arrived").is_empty(), "evento arrived")
	check_near(d.position.distance_to(Vector2(200, 300)), 0.0, 0.01, "llega exacto")
	check_eq(d.state, GameTypes.STATE_IDLE, "vuelve a IDLE")
	check(d.fatigue > 0.0, "moverse cansa")
	return done()


func test_order_changes_while_moving() -> bool:
	var sim := _sim()
	var d = _div(sim, "division-1")
	_move(sim, P1, "division-1", Vector2(200, 300))
	_run(sim, 10)
	_move(sim, P1, "division-1", Vector2(200, 1000))
	sim.step()
	check_eq(d.destination, Vector2(200, 1000), "la nueva orden reemplaza a la anterior")
	sim.handle(P1, Order.hold("division-1").to_message())
	var before: Vector2 = d.position
	_run(sim, 5)
	check_eq(d.position, before, "HOLD detiene la división")
	return done()


func test_water_blocks_straight_line() -> bool:
	var sim := _sim()
	var d = _div(sim, "division-1")
	_place(sim, "division-1", Vector2(900, 600))
	_move(sim, P1, "division-1", Vector2(1100, 600))
	var msgs := _run_until(sim, func() -> bool: return d.order.is_empty() and sim.tick > 1, 200)
	check(not _find(msgs, "division_updated", "reason", "blocked").is_empty(), "evento blocked")
	check(d.position.x < 950.0, "se detiene antes del río")
	return done()


func test_encounter_starts_battle_and_changes_stats() -> bool:
	var sim := _sim()
	var a = _div(sim, "division-1")
	var b = _div(sim, "division-2")
	_place(sim, "division-1", Vector2(500, 1100))
	_place(sim, "division-2", Vector2(650, 1100))
	_move(sim, P1, "division-1", Vector2(700, 1100))
	var msgs := _run_until(sim, func() -> bool: return not sim.battles.is_empty(), 200)
	var started := _find(msgs, "battle_started")
	check_eq(started.get("attacker_id"), "division-1", "quien se mueve es el atacante")
	check_eq(a.state, GameTypes.STATE_ATTACKING, "atacante ATTACKING")
	check_eq(b.state, GameTypes.STATE_DEFENDING, "defensor DEFENDING")
	check(a.position.distance_to(b.position) <= 60.0, "en rango de combate")
	var stopped: Vector2 = a.position
	var morale_a: float = a.morale
	var morale_b: float = b.morale

	msgs = _run(sim, 10)
	check_eq(_count(msgs, "battle_updated"), 1, "una ronda por segundo")
	check_eq(a.position, stopped, "en combate no avanza")
	check(a.unit_count < 3000 and b.unit_count < 3000, "bajas en ambos lados")
	check(a.morale < morale_a and b.morale < morale_b, "la moral baja")
	check(a.experience > 0.0, "gana experiencia")

	check_eq(_error_code(_move(sim, P1, "division-1", Vector2(300, 1100))), "division_engaged", "MOVE en combate")
	var defend := sim.handle(P2, Order.defend("division-2").to_message())
	check_eq(defend[0]["type"], "order_accepted", "DEFEND en combate")
	return done()


func test_attack_order_chases_target() -> bool:
	var sim := _sim()
	_place(sim, "division-1", Vector2(450, 1100))
	_place(sim, "division-2", Vector2(700, 1100))
	sim.handle(P1, Order.attack("division-1", "division-2").to_message())
	var msgs := _run_until(sim, func() -> bool: return not sim.battles.is_empty(), 300)
	check_eq(_find(msgs, "battle_started").get("attacker_id"), "division-1", "el que ataca inicia")
	check_eq(_div(sim, "division-1").state, GameTypes.STATE_ATTACKING, "ATTACKING")
	return done()


func test_retreat_disengages() -> bool:
	var sim := _sim()
	_place(sim, "division-1", Vector2(500, 1100))
	_place(sim, "division-2", Vector2(540, 1100))
	sim.step()
	check_eq(sim.battles.size(), 1, "combate por contacto")
	sim.handle(P1, Order.retreat("division-1").to_message())
	var msgs := _run_until(sim, func() -> bool: return sim.battles.is_empty(), 300)
	var ended := _find(msgs, "battle_ended")
	check_eq(ended.get("reason"), "disengaged", "se separan")
	check_eq(ended.get("winner_division_id"), "division-2", "gana quien se queda")
	check_eq(_div(sim, "division-1").state, GameTypes.STATE_RETREATING, "sigue en retirada")
	check_eq(_div(sim, "division-2").state, GameTypes.STATE_IDLE, "el otro vuelve a IDLE")
	return done()


func test_destroy_and_victory() -> bool:
	var sim := _sim()
	_place(sim, "division-1", Vector2(500, 1100))
	_place(sim, "division-2", Vector2(540, 1100))
	sim.step()
	_div(sim, "division-2").unit_count = 150
	var msgs := _run_until(sim, func() -> bool: return sim.status == GameTypes.STATUS_FINISHED, 100)
	check_eq(_find(msgs, "division_destroyed").get("division_id"), "division-2", "destruida")
	var finished := _find(msgs, "game_finished")
	check_eq(finished.get("winner_player_id"), P1, "gana P1")
	check_eq(finished.get("reason"), "annihilation", "por aniquilación")
	check_eq(_div(sim, "division-2").state, GameTypes.STATE_DESTROYED, "estado DESTROYED")
	check_eq(sim.step().size(), 0, "una partida terminada no simula más")
	return done()


func test_rout_and_rally() -> bool:
	var sim := _sim(SOLO_ARMY, {"morale_recovery_per_second": 30.0})
	var a = _div(sim, "division-1")
	_div(sim, "division-2").attack = 40.0
	_place(sim, "division-1", Vector2(500, 1100))
	_place(sim, "division-2", Vector2(540, 1100))
	var msgs := _run_until(sim, func() -> bool: return a.routed, 400)
	check(a.routed, "se desbanda con moral baja")
	check_eq(a.state, GameTypes.STATE_RETREATING, "huye")
	check_eq(a.order.get("type"), "retreat", "orden automática de retirada")
	check(not _find(msgs, "division_updated", "reason", "routed").is_empty(), "evento routed")
	check_eq(_error_code(sim.handle(P1, Order.defend("division-1").to_message())), "division_routed", "solo acepta RETREAT")
	msgs = _run_until(sim, func() -> bool: return not a.routed or not a.alive(), 1000)
	check(a.alive() and not a.routed, "se reagrupa")
	check(not _find(msgs, "division_updated", "reason", "rallied").is_empty(), "evento rallied")
	return done()


func test_time_limit_victory() -> bool:
	var sim := _sim(SOLO_ARMY, {"max_duration_ticks": 20})
	_div(sim, "division-1").unit_count = 2500
	var msgs := _run(sim, 20)
	var finished := _find(msgs, "game_finished")
	check_eq(finished.get("reason"), "time_limit", "límite de tiempo")
	check_eq(finished.get("winner_player_id"), P2, "gana quien tiene más tropas")
	return done()


func test_full_match_is_deterministic_and_consistent() -> bool:
	var first := _scripted_match()
	var second := _scripted_match()
	check_eq(first["status"], GameTypes.STATUS_FINISHED, "la partida termina")
	check_eq(first, second, "dos ejecuciones idénticas")
	check(first["battles"] > 0, "hubo combates")
	check(first["invariants_ok"], "invariantes (unidades, moral, fatiga, terreno)")
	return done()


## P1 sends idle divisions against the nearest enemy; P2 defends.
func _scripted_match() -> Dictionary:
	var sim := _sim(Definitions.army(), {"max_duration_ticks": 3000})
	for d in sim.divisions:
		if d.player_id == P2:
			sim.handle(P2, Order.defend(d.id).to_message())
	var battles := 0
	while sim.status == GameTypes.STATUS_RUNNING and sim.tick < 4000:
		if sim.tick % 20 == 0:
			for d in sim.divisions:
				if d.player_id != P1 or not d.alive() or d.routed or not d.order.is_empty() or sim._engaged(d):
					continue
				var target = _nearest_enemy(sim, d)
				if target == null:
					continue
				# Local movement is straight-line: cross the river through a ford first.
				if _line_clear(sim.map, d.position, target.position):
					sim.handle(P1, Order.attack(d.id, target.id).to_message())
				else:
					sim.handle(P1, Order.move(d.id, _nearest_ford(d.position)).to_message())
		battles += _count(sim.step(), "battle_started")
	var ok := true
	var units := []
	for d in sim.divisions:
		units.append([d.id, d.unit_count, snappedf(d.morale, 0.001), d.state])
		ok = ok and d.unit_count >= 0 and d.unit_count <= d.max_unit_count
		ok = ok and d.morale >= 0.0 and d.morale <= 100.0 and d.fatigue >= 0.0 and d.fatigue <= 100.0
		ok = ok and sim.map.is_passable(d.position)
	return {"status": sim.status, "tick": sim.tick, "winner": sim.winner_id, "reason": sim.finish_reason,
		"battles": battles, "units": units, "invariants_ok": ok}


func _nearest_enemy(sim: LocalGameSimulation, d):
	var best = null
	for e in sim.divisions:
		if e.player_id == d.player_id or not e.alive():
			continue
		if best == null or d.position.distance_to(e.position) < d.position.distance_to(best.position):
			best = e
	return best


func _line_clear(map: MapData, from: Vector2, to: Vector2) -> bool:
	var steps := ceili(from.distance_to(to) / 12.5)
	for i in steps + 1:
		if not map.is_passable(from.lerp(to, float(i) / maxf(steps, 1))):
			return false
	return true


## Fords of the default map: rows 5-6 and 17-18 of the river (columns 19-20).
func _nearest_ford(from: Vector2) -> Vector2:
	var north := Vector2(975, 300)
	var south := Vector2(975, 900)
	return north if from.distance_to(north) < from.distance_to(south) else south
