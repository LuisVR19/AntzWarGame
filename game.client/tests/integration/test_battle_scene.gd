extends "res://tests/framework/test_case.gd"
## Smoke test of the real scenes in headless mode: main menu -> local battle
## -> select -> MOVE -> ATTACK -> debug -> back to menu. It catches runtime
## errors in scene/UI scripts (missing nodes, bad API calls, ...).
## Time is accelerated with Engine.time_scale to keep it fast.

var main: Node


func before_each() -> void:
	Engine.time_scale = 10.0
	main = load("res://scenes/main/main.tscn").instantiate()
	tree.root.add_child(main)


func after_each() -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(main):
		main.queue_free()


func test_local_battle_flow() -> bool:
	await wait_frames(2)
	check(main.menu.visible, "menú visible al iniciar")
	main.menu.local_requested.emit("default", "small")
	await wait_frames(2)
	var battle = main._battle
	check(battle != null, "se crea la escena de batalla")
	if battle == null:
		return done()
	check(not main.menu.visible, "el menú se oculta")

	var is_running := func() -> bool: return battle.source.state.status == GameTypes.STATUS_RUNNING
	var running: bool = await wait_until(is_running, 10.0)
	check(running, "la partida local arranca")
	check_eq(battle.division_layer._views.size(), 6, "6 vistas de división")
	check(battle.division_layer._views["division-1"]._radii.x > battle.division_layer._views["division-3"]._radii.x,
		"3000 soldados se ven más grandes que 2000")
	check(battle.map_view._map != null, "mapa cargado en la vista")

	# Isometric map: tiles, objects and a shared Y-sort for everything standing on the ground.
	check_eq(battle.map_view.ground.get_used_cells().size(), 40 * 24, "una celda del TileMapLayer por casilla")
	check_eq(battle.building_layer.count(), 6, "6 edificios (2 hormigueros + 4)")
	check_eq(battle.resource_layer.count(), 8, "8 recursos")
	check(battle.decoration_layer.item_count() > 50, "árboles y rocas")
	check(battle.decoration_layer.get_child_count() < battle.decoration_layer.item_count(), "agrupados por diagonal")
	var world: Node2D = battle.get_node("World")
	check(world.y_sort_enabled, "World usa Y-sort")
	for layer in world.get_children():
		check(layer.y_sort_enabled, "%s comparte el Y-sort de World" % layer.name)
	var unit_view = battle.division_layer._views["division-1"]
	check_near(unit_view.position.distance_to(battle.projection.world_to_screen(unit_view.world_position)), 0.0, 0.01,
		"la vista se dibuja en la proyección isométrica de su posición de mundo")

	# Clicking a building / resource selects it and shows its info (no order buttons).
	var nest = battle.building_layer.view("building-1")
	battle._on_primary_clicked(nest.position + Vector2(0, -10))
	await wait_frames(1)
	check_eq(battle.selection.primary(), "building-1", "clic sobre el hormiguero lo selecciona")
	check(nest.selection_indicator.visible, "indicador de selección del edificio")
	check(battle.hud.division_panel._info.visible and not battle.hud.division_panel._details.visible, "panel de edificio")
	var food = battle.resource_layer.view("resource-1")
	battle._on_primary_clicked(food.position)
	await wait_frames(1)
	check_eq(battle.selection.primary(), "resource-1", "clic sobre un recurso lo selecciona")
	check(not nest.selection_indicator.visible, "el edificio se deselecciona")

	# Select an own division: the panel shows its details.
	battle.selection.select("division-1")
	await wait_frames(1)
	check(battle.hud.division_panel._details.visible, "panel con detalles")
	check_eq(battle.hud.division_panel._title.text, battle.source.state.get_division("division-1").display_name, "título del panel")

	# Right click on the ground = MOVE.
	var start: Vector2 = battle.source.state.get_division("division-1").position
	battle._on_secondary_clicked(battle.projection.world_to_screen(start + Vector2(0, -150)))
	var has_moved := func() -> bool: return battle.source.state.get_division("division-1").position.distance_to(start) > 20.0
	var moved: bool = await wait_until(has_moved, 10.0)
	check(moved, "la división se mueve tras el clic derecho")
	var view = battle.division_layer._views["division-1"]
	check(view.world_position.distance_to(start) > 5.0, "la vista interpola hacia la nueva posición")
	check(not view.route_world.is_empty(), "se dibuja la ruta de la orden")
	check(view.selection_indicator.visible, "indicador de selección bajo la división")

	# Button mode: ATTACK, then click on an enemy.
	battle.selection.select("division-3")
	battle._on_order_requested(Order.ATTACK)
	check_eq(battle._command_mode, Order.ATTACK, "modo ataque esperando objetivo")
	var enemy_pos: Vector2 = battle.division_layer._views["division-4"].position
	battle._on_primary_clicked(enemy_pos)
	check_eq(battle._command_mode, "", "el modo se limpia tras el clic")
	var is_attacking := func() -> bool: return battle.source.state.get_division("division-3").state == GameTypes.STATE_ATTACKING
	check(await wait_until(is_attacking, 10.0), "la orden de ataque se aplica")
	var armored = battle.source.state.get_division("division-3")
	check(armored.order != null and armored.order.type == Order.ATTACK, "orden de ataque aceptada")
	check_eq(armored.state, GameTypes.STATE_ATTACKING, "estado ATTACKING")

	# Clicking an own division opens its order menu next to it.
	var menu = battle.hud.action_menu
	var worker = battle.division_layer._views["division-2"]
	battle._on_primary_clicked(worker.position)
	await wait_frames(1)
	check(menu.visible, "clic en una división propia abre su menú de órdenes")
	# DEFEND from the menu is immediate.
	menu._buttons[Order.DEFEND].pressed.emit()
	check(not menu.visible, "el menú se cierra al elegir una orden")
	var is_defending := func() -> bool: return battle.source.state.get_division("division-2").state == GameTypes.STATE_DEFENDING
	check(await wait_until(is_defending, 10.0), "DEFENDER desde el menú")
	# MOVE from the menu waits for a click on the map (with a preview line).
	battle._on_primary_clicked(worker.position)
	menu._buttons[Order.MOVE].pressed.emit()
	check_eq(battle._command_mode, Order.MOVE, "MOVER desde el menú espera el clic de destino")
	check(battle.map_view.marks.preview_division_ids.has("division-2"), "línea de previsualización de la orden")
	var worker_start: Vector2 = battle.source.state.get_division("division-2").position
	battle._on_primary_clicked(battle.projection.world_to_screen(worker_start + Vector2(120, 0)))
	check(battle.map_view.marks.preview_division_ids.is_empty(), "la previsualización se quita tras el clic")
	var worker_moved := func() -> bool: return battle.source.state.get_division("division-2").position.distance_to(worker_start) > 15.0
	check(await wait_until(worker_moved, 10.0), "la división se mueve al destino elegido con clic")
	# DIVIDIR from the menu creates a new division (and its view).
	check(menu._buttons[Order.SPLIT].visible, "DIVIDIR disponible en partida local")
	battle._on_primary_clicked(worker.position)
	menu._buttons[Order.SPLIT].pressed.emit()
	var has_split := func() -> bool: return battle.division_layer._views.size() == 7
	check(await wait_until(has_split, 10.0), "DIVIDIR crea una división nueva")
	# UNIR waits for a click on another own division.
	battle.selection.select("division-2")
	battle._on_order_requested(Order.MERGE)
	check_eq(battle._command_mode, Order.MERGE, "UNIR espera el clic sobre otra división propia")
	battle._on_cancel()
	# Formation from the UI.
	check(battle.hud.division_panel._formation_picker.visible, "selector de formación en partida local")
	battle._on_formation_requested(Formations.WEDGE)
	var in_wedge := func() -> bool: return battle.source.state.get_division("division-2").formation == Formations.WEDGE
	check(await wait_until(in_wedge, 10.0), "cambio de formación desde la UI")

	# Right button: dragging pans the camera without giving orders; a short click is an order.
	battle.camera._zoom_at(2.0, battle.camera.position)
	var secondary := [0]
	battle.battle_input.secondary_clicked.connect(func(_p: Vector2) -> void: secondary[0] += 1)
	var cam_before: Vector2 = battle.camera.position
	_right_button(battle, true, Vector2(600, 400))
	_right_motion(battle, Vector2(700, 430), Vector2(100, 30))
	_right_button(battle, false, Vector2(700, 430))
	check(battle.camera.position.x < cam_before.x, "arrastrar con clic derecho desplaza el mapa")
	check_eq(secondary[0], 0, "arrastrar no da una orden")
	_right_button(battle, true, Vector2(500, 400))
	_right_button(battle, false, Vector2(502, 401))
	check_eq(secondary[0], 1, "un clic derecho corto sigue siendo una orden")

	# Box selection (left drag) and a group order.
	var v1 = battle.division_layer.view("division-1")
	var v3 = battle.division_layer.view("division-3")
	var corner_a: Vector2 = battle._to_viewport(v1.global_position)
	var corner_b: Vector2 = battle._to_viewport(v3.global_position)
	var box := Rect2(corner_a, Vector2.ZERO).expand(corner_b).grow(4.0)
	battle._on_box_released(box.position, box.end, false)
	check(battle.selection.count() >= 2 and battle.selection.is_selected("division-1") and battle.selection.is_selected("division-3"),
		"el recuadro selecciona varias divisiones propias")
	check(v1.selection_indicator.visible and v3.selection_indicator.visible, "cada una con su indicador")
	var group: Array = battle._commandable_ids()
	var goal: Vector2 = battle.source.state.get_division("division-1").position + Vector2(150, 0)
	battle._on_secondary_clicked(battle.projection.world_to_screen(goal))
	var all_moving := func() -> bool:
		for id in group:
			var o = battle.source.state.get_division(id).order
			if o == null or o.type != Order.MOVE:
				return false
		return true
	check(await wait_until(all_moving, 10.0), "clic derecho da MOVER a todo el grupo")
	var targets := {}
	for id in group:
		var o = battle.source.state.get_division(id).order
		if o != null:
			targets[roundi(o.target_position.x) * 10000 + roundi(o.target_position.y)] = true
	check_eq(targets.size(), group.size(), "cada división recibe un destino distinto (en fila)")
	battle._select_all()
	var own := 0
	for d in battle.source.state.all_divisions():
		if d.is_alive() and d.player_id == battle.source.local_player_id:
			own += 1
	check_eq(battle.selection.count(), own, "Ctrl+A selecciona todas las divisiones propias")

	# Selecting an enemy shows it without enabling orders.
	battle.selection.select("division-5")
	await wait_frames(1)
	var move_button: Button = battle.hud.division_panel._buttons[Order.MOVE]
	check(move_button.disabled, "los botones se deshabilitan para divisiones enemigas")
	battle._on_primary_clicked(battle.division_layer._views["division-5"].position)
	check(not menu.visible, "las divisiones enemigas no abren el menú de órdenes")

	# Debug overlay and camera zoom.
	battle._toggle_debug()
	await wait_frames(2)
	check(battle.hud.debug_overlay.visible, "overlay de debug visible")
	var zoom_before: float = battle.camera.zoom.x
	battle.camera._zoom_at(1.5, Vector2(1000, 600))
	check(battle.camera.zoom.x > zoom_before, "zoom")

	# Event log received entries.
	check(battle.hud.event_log._entries.size() >= 3, "el registro de eventos tiene entradas")

	# Back to the menu.
	battle._exit()
	await wait_frames(3)
	check(main._battle == null, "se libera la batalla")
	check(main.menu.visible, "vuelve al menú")
	return done()


func _right_button(battle: Node, pressed: bool, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = pressed
	ev.position = pos
	battle.battle_input._unhandled_input(ev)


func _right_motion(battle: Node, pos: Vector2, relative: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.relative = relative
	ev.button_mask = MOUSE_BUTTON_MASK_RIGHT
	battle.battle_input._unhandled_input(ev)
