extends "res://tests/framework/test_case.gd"
## Isometric projection, TileMapLayer alignment and grid-based map objects.

var proj := IsoProjection.new(50.0, 64.0, 32.0)


func test_formula_matches_spec() -> bool:
	# screen = ((gx - gy) * tw / 2, (gx + gy) * th / 2)
	check_eq(proj.grid_to_screen(Vector2(3, 2)), Vector2(32, 80), "grid (3, 2)")
	check_eq(proj.grid_to_screen(Vector2.ZERO), Vector2.ZERO, "origen")
	check_eq(proj.world_to_screen(Vector2(150, 100)), Vector2(32, 80), "mundo = grid * cell_size")
	check_eq(proj.cell_center(Vector2i(0, 0)), Vector2(0, 16), "centro de la celda (0, 0)")
	return done()


func test_round_trips() -> bool:
	for world in [Vector2(0, 0), Vector2(123.4, 987.6), Vector2(1999, 1), Vector2(-40, 310)]:
		var back := proj.screen_to_world(proj.world_to_screen(world))
		check_near(back.distance_to(world), 0.0, 0.001, "mundo -> pantalla -> mundo %s" % world)
	check_eq(proj.screen_to_cell(proj.cell_center(Vector2i(7, 11))), Vector2i(7, 11), "pantalla -> celda")
	return done()


func test_tile_map_layer_is_aligned() -> bool:
	var layer := TileMapLayer.new()
	layer.tile_set = TerrainTileSet.build(VisualConfig.new())
	layer.position = proj.cell_center(Vector2i.ZERO) - layer.map_to_local(Vector2i.ZERO)
	for cell in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(39, 23), Vector2i(12, 5)]:
		check_near((layer.position + layer.map_to_local(cell)).distance_to(proj.cell_center(cell)), 0.0, 0.01,
			"TileMapLayer y IsoProjection coinciden en %s" % cell)
	var source := layer.tile_set.get_source(TerrainTileSet.SOURCE_ID) as TileSetAtlasSource
	check_eq(source.get_atlas_grid_size().y, TerrainTileSet.ROWS.size(), "una fila del atlas por terreno")
	layer.free()
	return done()


func test_ground_radii_and_map_rect() -> bool:
	# A world circle of one cell radius spans sqrt(2)/2 tiles horizontally.
	var radii := proj.ground_radii(50.0)
	check_near(radii.x, 64.0 * sqrt(2.0) * 0.5, 0.001, "radio horizontal")
	check_near(radii.x / radii.y, 2.0, 0.001, "proporción 2:1 de la elipse")
	var rect := proj.map_rect(40, 24)
	check_eq(rect.position, Vector2(-24 * 32, 0), "esquina del mapa")
	check_eq(rect.size, Vector2(64 * 32, 64 * 16), "tamaño del mapa en pantalla")
	return done()


func test_map_objects_on_grid() -> bool:
	var map := MapData.from_definitions()
	var objects := MapObjects.for_map(map)
	check_eq(objects.buildings.size(), 6, "edificios")
	check_eq(objects.resources.size(), 8, "recursos")
	var sizes := {}
	for b in objects.buildings:
		sizes[b.size] = true
		for x in b.size.x:
			for y in b.size.y:
				check(map.terrain.is_passable(map.type_at_cell(b.origin + Vector2i(x, y))), "%s fuera del agua" % b.id)
	check(sizes.has(Vector2i(1, 1)) and sizes.has(Vector2i(2, 2)) and sizes.has(Vector2i(3, 3)), "tamaños 1x1, 2x2 y 3x3")
	var nest := objects.buildings[0]
	check_eq(nest.type, "anthill", "el primer edificio es un hormiguero")
	check(nest.occupies(map.cell_of(map.spawns[0])), "el hormiguero cubre el spawn")
	var types := {}
	for r in objects.resources:
		types[r.type] = true
		check(map.terrain.is_passable(map.type_at_cell(r.cell)), "%s fuera del agua" % r.id)
	check_eq(types.size(), 4, "oro, madera, piedra y comida")
	check(objects.is_occupied(nest.origin + Vector2i(1, 1)), "celda ocupada por edificio")
	return done()


func test_depth_order_follows_screen_y() -> bool:
	# Y-sort draws larger screen Y in front: whatever is further "south-east"
	# on the grid (greater gx + gy) must come out in front.
	var nest := BuildingData.create("b", "anthill", {"size": [3, 3]}, 0, Vector2i(3, 11))
	var sort_y := proj.grid_to_screen(nest.center_grid()).y
	var behind := proj.grid_to_screen(Vector2(4.5, 10.5)).y  # north of the nest
	var in_front := proj.grid_to_screen(Vector2(4.5, 14.5)).y  # south of the nest
	check(behind < sort_y, "una unidad detrás del edificio se dibuja antes")
	check(in_front > sort_y, "una unidad delante del edificio se dibuja después")
	return done()
