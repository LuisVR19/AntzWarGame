extends "res://tests/framework/test_case.gd"
## Pathfinder (grid A*) used by the local simulation.

var map := MapData.from_definitions()
var finder := Pathfinder.new(map)


func _segments_passable(from: Vector2, path: PackedVector2Array) -> bool:
	var a := from
	for b in path:
		var steps := maxi(ceili(a.distance_to(b) / 5.0), 1)
		for k in steps + 1:
			if not map.is_passable(a.lerp(b, float(k) / steps)):
				return false
		a = b
	return true


func _length(from: Vector2, path: PackedVector2Array) -> float:
	var total := 0.0
	var a := from
	for b in path:
		total += a.distance_to(b)
		a = b
	return total


func _small_map(rows: Array) -> MapData:
	var m := MapData._from_raw({"cell_size": 50, "tiles": rows, "spawns": []})
	m.terrain = TerrainTable.from_dict(Definitions.terrain())
	return m


func test_routes_around_the_river() -> bool:
	var from := Vector2(450, 600)
	var to := Vector2(1400, 600)  # straight line crosses the river (rows 7..13 are water)
	var path := finder.find_path(from, to)
	check(not path.is_empty(), "hay ruta")
	check_eq(path[path.size() - 1], to, "termina exactamente en el destino")
	check(path.size() >= 2, "rodea con varios tramos")
	check(_segments_passable(from, path), "ningún tramo pisa agua")
	check(_length(from, path) > from.distance_to(to), "la ruta es más larga que la línea recta")
	return done()


func test_open_ground_is_a_single_segment() -> bool:
	var path := finder.find_path(Vector2(425, 1100), Vector2(675, 1100))
	check_eq(path.size(), 1, "en llanura despejada va en línea recta")
	return done()


func test_invalid_targets() -> bool:
	check(finder.find_path(Vector2(450, 600), Vector2(975, 600)).is_empty(), "destino en el agua")
	check_eq(finder.find_path(Vector2(410, 610), Vector2(440, 640)).size(), 1, "misma casilla")
	var walled_finder := Pathfinder.new(_small_map(["PPWPP", "PPWPP", "PPWPP"]))
	check(not walled_finder.is_reachable(Vector2(25, 25), Vector2(225, 25)), "otra orilla sin vado: inalcanzable")
	check(walled_finder.is_reachable(Vector2(25, 25), Vector2(75, 125)), "misma orilla: alcanzable")
	return done()


func test_goes_around_slow_terrain() -> bool:
	# Plain to plain with a forest strip in between: going around on the
	# plain is cheaper than crossing the forest.
	var m := _small_map(["PPPPPPP", "PFFFFFP", "PPPPPPP"])
	var path := Pathfinder.new(m).find_path(Vector2(25, 75), Vector2(325, 75))
	var left_the_strip := false
	for p in path:
		if p.y < 50.0 or p.y > 100.0:
			left_the_strip = true
	check(left_the_strip, "rodea el bosque por la llanura")
	return done()
