extends "res://tests/framework/test_case.gd"
## LocalGameState end to end through its public API and signals, exactly as
## the battle scene uses it (no scene involved).


func test_local_source_full_flow() -> bool:
	var src := LocalGameState.new()
	var events := []
	var rejected := []
	var maps := []
	src.game_event.connect(func(e: GameEvent) -> void: events.append(e.type))
	src.order_rejected.connect(func(code: String, _m: String) -> void: rejected.append(code))
	src.map_received.connect(func(m: MapData) -> void: maps.append(m))

	src.start()
	check_eq(maps.size(), 1, "map_received")
	check_eq(src.local_player_id, "player-1", "controla al jugador 1")
	check_eq(src.state.division_ids.size(), 6, "estado inicial con 6 divisiones")
	check_eq(src.state.status, GameTypes.STATUS_STARTING, "cuenta atrás")
	check_eq(src.state.players.size(), 2, "dos jugadores")

	for i in 30:
		src._process(0.1)
	check_eq(src.state.status, GameTypes.STATUS_RUNNING, "partida en curso")
	check(events.has("game_started"), "evento game_started")

	var d := src.state.get_division("division-1")
	var start := d.position
	src.submit_order(Order.move("division-1", start + Vector2(0, -150)))
	check(events.has("order_accepted"), "orden aceptada")
	for i in 10:
		src._process(0.1)
	var moved := src.state.get_division("division-1")
	check_eq(moved.state, GameTypes.STATE_MOVING, "MOVING en el estado del cliente")
	check(moved.position.distance_to(start) > 20.0, "la posición avanza")
	check(moved.order != null and moved.order.type == Order.MOVE, "orden visible en el modelo")

	src.submit_order(Order.move("division-4", Vector2(1500, 300)))
	check_eq(rejected, ["not_owner"], "no puede mover divisiones del rival")

	src.switch_controlled_player()
	check_eq(src.local_player_id, "player-2", "hot-seat: cambia de jugador")
	src.submit_order(Order.hold("division-4"))
	check_eq(rejected.size(), 1, "ahora sí puede ordenar a la división 4")

	src.stop()
	src.free()
	return done()
