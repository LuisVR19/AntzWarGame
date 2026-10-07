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
	main.menu.local_requested.emit()
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
	check(battle.map_view._map != null, "mapa cargado en la vista")

	# Select an own division: the panel shows its details.
	battle.selection.select("division-1")
	await wait_frames(1)
	check(battle.hud.division_panel._details.visible, "panel con detalles")
	check_eq(battle.hud.division_panel._title.text, battle.source.state.get_division("division-1").display_name, "título del panel")

	# Right click on the ground = MOVE.
	var start: Vector2 = battle.source.state.get_division("division-1").position
	battle._on_secondary_clicked(start + Vector2(0, -150))
	var has_moved := func() -> bool: return battle.source.state.get_division("division-1").position.distance_to(start) > 20.0
	var moved: bool = await wait_until(has_moved, 10.0)
	check(moved, "la división se mueve tras el clic derecho")
	var view = battle.division_layer._views["division-1"]
	check(view.position.distance_to(start) > 5.0, "la vista interpola hacia la nueva posición")
	check(not view._order_points.is_empty(), "se dibuja la ruta de la orden")

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

	# Selecting an enemy shows it without enabling orders.
	battle.selection.select("division-5")
	await wait_frames(1)
	var move_button: Button = battle.hud.division_panel._buttons[Order.MOVE]
	check(move_button.disabled, "los botones se deshabilitan para divisiones enemigas")

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
