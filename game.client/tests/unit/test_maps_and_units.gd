extends "res://tests/framework/test_case.gd"
## Map catalog (default + large), starting armies and ant types.

const P1 := LocalGameSimulation.PLAYER_1
const P2 := LocalGameSimulation.PLAYER_2


func _rules() -> Dictionary:
	var r: Dictionary = Definitions.rules().duplicate(true)
	r["start_countdown_ticks"] = 0
	return r


func _sim(army: Array, map_id := "default") -> LocalGameSimulation:
	var sim := LocalGameSimulation.new(_rules(), MapData.from_definitions(map_id), army)
	sim.start()
	return sim


func _find(messages: Array, type: String) -> Dictionary:
	for m in messages:
		if m["type"] == type:
			return m
	return {}


func test_large_map() -> bool:
	var map := MapData.from_definitions("large")
	check_eq(Vector2i(map.cols, map.rows), Vector2i(80, 48), "80x48 casillas")
	check_eq(map.size(), Vector2(4000, 2400), "4000x2400 unidades de mundo")
	var symmetric := true
	for row in map.rows:
		for col in map.cols:
			if map.type_at_cell(Vector2i(col, row)) != map.type_at_cell(Vector2i(map.cols - 1 - col, row)):
				symmetric = false
	check(symmetric, "el mapa es simétrico para ambos jugadores")
	for spawn in map.spawns:
		check(map.is_passable(spawn), "spawn transitable")
	check(Pathfinder.new(map).is_reachable(map.spawns[0], map.spawns[1]), "hay camino entre las bases (vados)")
	var objects := MapObjects.for_map(map)
	check_eq(objects.buildings.size(), 8, "2 hormigueros + 6 edificios")
	check_eq(objects.resources.size(), 16, "16 recursos")
	for r in objects.resources:
		check(map.terrain.is_passable(map.type_at_cell(r.cell)), "%s fuera del agua" % r.id)
	check_eq(MapData.from_definitions().cols, 40, "el mapa por defecto sigue siendo el pequeño")
	return done()


func test_every_army_deploys_on_every_map() -> bool:
	for map_id in Definitions.maps().keys():
		for army_id in Definitions.armies().keys():
			var army := Definitions.army(army_id)
			var sim := _sim(army, map_id)
			var where := "%s/%s" % [map_id, army_id]
			check_eq(sim.divisions.size(), army.size() * 2, "%s: una división por entrada y jugador" % where)
			var names := {}
			for d in sim.divisions:
				check(sim.map.is_passable(d.position), "%s: %s en terreno transitable" % [where, d.id])
				check(UnitTypes.exists(d.unit_type), "%s: tipo válido" % where)
				names[d.player_id + d.name] = true
				for o in sim.divisions:
					if o != d and o.player_id == d.player_id:
						check(d.position.distance_to(o.position) >= 60.0, "%s: %s no se superpone con %s" % [where, d.id, o.id])
			check_eq(names.size(), sim.divisions.size(), "%s: nombres únicos por jugador" % where)
	return done()


func test_types_give_base_stats() -> bool:
	var sim := _sim(Definitions.army("medium"))
	var by_type := {}
	for d in sim.divisions:
		if d.player_id == P1:
			by_type[d.unit_type] = d
	check_eq(by_type.size(), 5, "el ejército mediano tiene los cinco tipos")
	check_eq(by_type[UnitTypes.ARCHER].speed, 35.0, "velocidad de la arquera desde unit_types.json")
	check_eq(by_type[UnitTypes.TANK].defense, 22.0, "defensa de la acorazada")
	check_eq(by_type[UnitTypes.ARCHER].name, "1a Arquera", "nombre automático por tipo")
	check_eq(sim._division_dto(by_type[UnitTypes.SCOUT])["unit_type"], "scout", "el tipo viaja al cliente")
	var tank: String = by_type[UnitTypes.TANK].id
	var worker: String = by_type[UnitTypes.WORKER].id
	var reply := sim.handle(P1, Order.merge(worker, tank).to_message())
	check_eq(reply[0].get("code"), "type_mismatch", "solo se unen divisiones del mismo tipo")
	return done()


func test_archers_shoot_at_range() -> bool:
	var sim := _sim([{"type": "ARCHER", "unit_count": 1500, "offset": {"x": 0, "y": 0}}])
	var archer = sim._by_id["division-1"]
	var target = sim._by_id["division-2"]
	target.unit_type = UnitTypes.WORKER  # only one side shoots in this test
	archer.position = Vector2(500, 1100)
	target.position = Vector2(650, 1100)  # 150: out of melee (60), in range (220)
	var msgs := []
	for i in 15:
		msgs.append_array(sim.step())
	var volley := _find(msgs, "volley")
	check(not volley.is_empty(), "la arquera dispara")
	check_eq(volley.get("shooter_id"), "division-1", "quién dispara")
	check(int(volley.get("losses", 0)) > 0, "causa bajas")
	check(target.unit_count < 1500, "el objetivo pierde soldados")
	check(archer.unit_count == 1500, "la arquera no sufre bajas a distancia")
	check(sim.battles.is_empty(), "no hay cuerpo a cuerpo")
	return done()


func test_archer_attack_stops_at_range() -> bool:
	var sim := _sim([{"type": "ARCHER", "unit_count": 1500, "offset": {"x": 0, "y": 0}}])
	var archer = sim._by_id["division-1"]
	var target = sim._by_id["division-2"]
	target.unit_type = UnitTypes.WORKER
	archer.position = Vector2(300, 1100)
	archer.destination = archer.position
	target.position = Vector2(700, 1100)
	target.destination = target.position
	sim.handle(P1, Order.attack("division-1", "division-2").to_message())
	var msgs := []
	for i in 400:
		msgs.append_array(sim.step())
		if not _find(msgs, "volley").is_empty():
			break
	check(not _find(msgs, "volley").is_empty(), "se acerca y dispara")
	var distance: float = archer.position.distance_to(target.position)
	check(distance > 60.0 and distance <= UnitTypes.attack_range(UnitTypes.ARCHER), "se detiene a distancia de tiro (%.0f)" % distance)
	check(sim.battles.is_empty(), "no se mete en el cuerpo a cuerpo")
	return done()


func test_client_parses_unit_type() -> bool:
	check_eq(DivisionData.from_protocol({"id": "d", "unit_type": "archer"}).unit_type, UnitTypes.ARCHER, "tipo")
	check_eq(DivisionData.from_protocol({"id": "d"}).unit_type, UnitTypes.WORKER, "sin el campo (servidor Go): obrera")
	return done()
