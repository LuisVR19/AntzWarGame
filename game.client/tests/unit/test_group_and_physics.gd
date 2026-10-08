extends "res://tests/framework/test_case.gd"
## Group moves (GroupMove) and the physical space of divisions (no overlaps).
## With PAIR, player 1 owns division-1 and division-2.

const P1 := LocalGameSimulation.PLAYER_1
const PAIR := [
	{"name": "A", "offset": {"x": 0, "y": 0}, "unit_count": 3000},
	{"name": "B", "offset": {"x": 0, "y": 300}, "unit_count": 3000},
]


func _sim(army: Array) -> LocalGameSimulation:
	var rules: Dictionary = Definitions.rules().duplicate(true)
	rules["start_countdown_ticks"] = 0
	var sim := LocalGameSimulation.new(rules, MapData.from_definitions(), army)
	sim.start()
	return sim


func _place(sim: LocalGameSimulation, id: String, pos: Vector2) -> void:
	sim._by_id[id].position = pos
	sim._by_id[id].destination = pos


## Worst overlap (contact distance minus real distance) among alive divisions.
func _max_overlap(sim: LocalGameSimulation) -> float:
	var worst := 0.0
	for a in sim.divisions:
		for b in sim.divisions:
			if a != b and a.alive() and b.alive():
				worst = maxf(worst, sim._contact(a, b) - a.position.distance_to(b.position))
	return worst


func test_group_slots() -> bool:
	var positions := [Vector2(100, 100), Vector2(100, 200), Vector2(100, 300)]
	var radii := [25.0, 25.0, 25.0]
	var target := Vector2(600, 200)
	var slots := GroupMove.slots(positions, radii, target)
	check_eq(slots.size(), 3, "un destino por división")
	for i in 3:
		for j in range(i + 1, 3):
			check(slots[i].distance_to(slots[j]) >= 50.0, "destinos sin solaparse (%d, %d)" % [i, j])
	check_near(((slots[0] + slots[1] + slots[2]) / 3.0).distance_to(target), 0.0, 0.01, "la fila se centra en el clic")
	check(slots[0].y < slots[1].y and slots[1].y < slots[2].y, "conservan su orden lateral (no se cruzan)")
	var many := []
	var many_radii := []
	for i in 7:
		many.append(Vector2(100, 100 + i * 60))
		many_radii.append(20.0)
	var rows := GroupMove.slots(many, many_radii, Vector2(800, 280))
	var xs := {}
	for p in rows:
		xs[roundi(p.x)] = true
	check_eq(xs.size(), 2, "7 divisiones forman dos filas de hasta 5")
	return done()


func test_overlapping_divisions_separate() -> bool:
	var sim := _sim(PAIR)
	_place(sim, "division-1", Vector2(500, 1100))
	_place(sim, "division-2", Vector2(510, 1100))
	sim.step()
	check(_max_overlap(sim) < 0.5, "una pasada separa a las aliadas solapadas")
	check(sim._division_dto(sim._by_id["division-1"])["radius"] > 0.0, "el radio viaja al cliente")
	return done()


func test_marching_division_goes_around_a_friend() -> bool:
	var sim := _sim(PAIR)
	var a = sim._by_id["division-1"]
	var b = sim._by_id["division-2"]
	_place(sim, "division-1", Vector2(300, 1100))
	_place(sim, "division-2", Vector2(500, 1100))  # standing in the way
	sim.handle(P1, Order.move("division-1", Vector2(700, 1100)).to_message())
	var worst := 0.0
	for i in 400:
		sim.step()
		worst = maxf(worst, _max_overlap(sim))
		if a.order.is_empty() and i > 1:
			break
	check(worst < 2.0, "nunca se pisan (máximo solape %.1f)" % worst)
	check(a.position.distance_to(Vector2(700, 1100)) < 30.0, "llega al otro lado")
	check(b.position.distance_to(Vector2(500, 1100)) < 30.0, "la que estaba quieta apenas se mueve")
	return done()


func test_same_destination_settles_side_by_side() -> bool:
	var sim := _sim(PAIR)
	var a = sim._by_id["division-1"]
	var b = sim._by_id["division-2"]
	_place(sim, "division-1", Vector2(400, 1050))
	_place(sim, "division-2", Vector2(400, 1150))
	sim.handle(P1, Order.move("division-1", Vector2(650, 1100)).to_message())
	sim.handle(P1, Order.move("division-2", Vector2(650, 1100)).to_message())
	for i in 600:
		sim.step()
		if a.order.is_empty() and b.order.is_empty() and i > 1:
			break
	check(a.order.is_empty() and b.order.is_empty(), "ambas terminan la orden (no empujan para siempre)")
	check(_max_overlap(sim) < 0.5, "quedan una al lado de la otra")
	return done()


func test_big_divisions_fight_edge_to_edge() -> bool:
	var big := [{"name": "Grande", "offset": {"x": 0, "y": 0}, "unit_count": 6000}]
	var sim := _sim(big)
	_place(sim, "division-1", Vector2(400, 1100))
	_place(sim, "division-2", Vector2(650, 1100))
	sim.handle(P1, Order.attack("division-1", "division-2").to_message())
	for i in 400:
		sim.step()
		if not sim.battles.is_empty():
			break
	check(not sim.battles.is_empty(), "combaten")
	var a = sim._by_id["division-1"]
	var b = sim._by_id["division-2"]
	var contact := sim._contact(a, b)
	check(contact > 60.0, "dos divisiones de 6000 son más anchas que el antiguo rango fijo")
	var dist: float = a.position.distance_to(b.position)
	check(dist >= contact - 0.5 and dist <= contact + 10.5, "chocan borde con borde (%.0f, contacto %.0f)" % [dist, contact])
	return done()


func test_nobody_is_pushed_into_water() -> bool:
	var sim := _sim(PAIR)
	var bank = sim._by_id["division-1"]
	_place(sim, "division-1", Vector2(930, 600))  # the river starts at x = 950
	_place(sim, "division-2", Vector2(920, 600))  # overlapping, on the land side
	for i in 5:
		sim.step()
	check(sim.map.is_passable(bank.position), "la de la orilla sigue en tierra")
	check(_max_overlap(sim) < 0.5, "se separan igualmente")
	return done()


func test_client_parses_radius() -> bool:
	check_near(DivisionData.from_protocol({"id": "d", "radius": 33.5}).radius, 33.5, 0.001, "radio")
	check_eq(DivisionData.from_protocol({"id": "d"}).radius, 0.0, "sin el campo (servidor Go): 0")
	return done()
