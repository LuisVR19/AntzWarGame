extends "res://tests/framework/test_case.gd"
## Terrain definitions and MapData.


func test_terrain_values_come_from_definitions() -> bool:
	var table := TerrainTable.from_dict(Definitions.terrain())
	check_eq(table.movement("PLAIN"), 1.0, "PLAIN movement")
	check_eq(table.movement("FOREST"), 0.7, "FOREST movement")
	check_eq(table.attack("FOREST"), 0.9, "FOREST attack")
	check_eq(table.defense("FOREST"), 1.2, "FOREST defense")
	check_eq(table.attack("HILL"), 1.1, "HILL attack")
	check_eq(table.defense("HILL"), 1.3, "HILL defense")
	check_eq(table.movement("WATER"), 0.0, "WATER movement")
	check(not table.is_passable("WATER"), "WATER debe ser intransitable")
	check(table.is_passable("HILL"), "HILL debe ser transitable")
	return done()


func test_terrain_accepts_server_lowercase_keys() -> bool:
	var table := TerrainTable.from_dict({"forest": {"movement_modifier": 0.5, "attack_modifier": 1.0,
		"defense_modifier": 2.0, "visibility_modifier": 1.0}})
	check_eq(table.movement("FOREST"), 0.5, "clave en minúsculas")
	check_eq(table.defense("FOREST"), 2.0, "defensa")
	return done()


func test_default_map_layout() -> bool:
	var map := MapData.from_definitions()
	check_eq(map.cols, 40, "columnas")
	check_eq(map.rows, 24, "filas")
	check_eq(map.size(), Vector2(2000, 1200), "tamaño en unidades")
	check_eq(map.spawns.size(), 2, "dos bases")
	for s in map.spawns:
		check(map.is_passable(s), "base en terreno transitable %s" % s)
	check_eq(map.terrain_at(Vector2(975, 500)), "WATER", "río en el centro")
	check_eq(map.terrain_at(Vector2(975, 275)), "PLAIN", "vado norte")
	check_eq(map.terrain_at(Vector2(500, 200)), "FOREST", "bosque")
	check_eq(map.terrain_at(Vector2(325, 600)), "HILL", "colina")
	check_eq(map.terrain_at(Vector2(-5, 10)), "WATER", "fuera del mapa = intransitable")
	check(not map.is_passable(Vector2(2000, 100)), "borde derecho excluido")
	return done()


func test_map_protocol_round_trip() -> bool:
	var map := MapData.from_definitions()
	var copy := MapData.from_protocol(map.to_protocol())
	check_eq(copy.cols, map.cols, "cols")
	check_eq(copy.rows, map.rows, "rows")
	check_eq(copy.cell_size, map.cell_size, "cell_size")
	check_eq(copy.tiles, map.tiles, "tiles")
	check_eq(copy.spawns[1], map.spawns[1], "spawns")
	check_eq(copy.terrain.defense("HILL"), 1.3, "tabla de terreno")
	return done()
