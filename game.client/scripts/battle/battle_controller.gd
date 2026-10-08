class_name BattleController
extends Node2D
## Root of the battle scene. Connects the GameStateSource (local or network)
## to the views, the input and the HUD. It is the only place that knows how
## user intents become Orders. Clicks arrive in screen (isometric) space and
## are converted to world units with IsoProjection before reaching the logic.

signal exit_requested

## Spacing used for group moves when the source does not send radii (server).
const GROUP_FALLBACK_RADIUS := 30.0
## Command mode / button type: put the selection under a general or commander.
const ASSIGN_COMMANDER := "ASSIGN"

@export var visual_config: VisualConfig

var source: GameStateSource
var projection: IsoProjection
var map_objects: MapObjects = MapObjects.new()
## Chain of command overlay (generals, commanders, messengers), built in _ready.
var command_layer: CommandLayer
var _command_mode := ""  # "", Order.MOVE or Order.ATTACK (waiting for a click)
var _debug := false
var _finished := false
var _announce_player := false  # the player's name arrives with the lobby, after the session

@onready var map_view: MapView = $Map
@onready var decoration_layer: DecorationLayer = $World/Decorations
@onready var building_layer: MapObjectLayer = $World/Buildings
@onready var resource_layer: MapObjectLayer = $World/Resources
@onready var division_layer: DivisionLayer = $World/Units
@onready var battle_layer: BattleLayer = $Effects
@onready var camera: BattleCamera = $Camera
@onready var selection: SelectionManager = $SelectionManager
@onready var battle_input: BattleInput = $BattleInput
@onready var hud: Hud = $HUD


func _ready() -> void:
	InputActions.ensure()
	if visual_config == null:
		visual_config = VisualConfig.new()
	projection = visual_config.projection(MapData.new().cell_size)
	camera.configure(visual_config)
	battle_input.drag_threshold = visual_config.camera_drag_threshold
	battle_input.pan_requested.connect(camera.pan_screen)
	hud.action_menu.order_requested.connect(_on_order_requested)
	hud.action_menu.formation_requested.connect(_on_formation_requested)
	hud.division_panel.formation_requested.connect(_on_formation_requested)
	battle_input.formation_cycle_pressed.connect(_cycle_formation)
	battle_input.box_dragged.connect(func(from: Vector2, to: Vector2) -> void: hud.selection_box.show_box(from, to))
	battle_input.box_released.connect(_on_box_released)
	battle_input.select_all_pressed.connect(_select_all)
	division_layer.setup(projection, visual_config)
	battle_layer.setup(projection)
	map_view.marks.division_layer = division_layer
	battle_input.primary_clicked.connect(_on_primary_clicked)
	battle_input.secondary_clicked.connect(_on_secondary_clicked)
	battle_input.cancel_pressed.connect(_on_cancel)
	battle_input.order_hotkey_pressed.connect(_on_order_requested)
	battle_input.debug_toggled.connect(_toggle_debug)
	battle_input.switch_player_pressed.connect(_switch_player)
	selection.selection_changed.connect(_on_selection_changed)
	camera.zoom_level_changed.connect(_on_zoom_changed)
	hud.division_panel.order_requested.connect(_on_order_requested)
	hud.top_bar.ready_pressed.connect(func() -> void: source.set_ready(true))
	hud.top_bar.switch_player_pressed.connect(_switch_player)
	hud.top_bar.menu_pressed.connect(_exit)
	hud.game_over.back_pressed.connect(_exit)
	battle_input.command_radii_toggled.connect(_toggle_command_radii)
	command_layer = CommandLayer.new()
	command_layer.name = "CommandLayer"
	command_layer.z_index = 50
	add_child(command_layer)
	command_layer.setup(projection, division_layer)


## Called by Main right after adding the scene to the tree.
func start(p_source: GameStateSource) -> void:
	source = p_source
	source.name = "GameStateSource"
	add_child(source)
	source.session_started.connect(_on_session_started)
	source.map_received.connect(_on_map_received)
	source.lobby_changed.connect(_on_lobby_changed)
	source.state_updated.connect(_on_state_updated)
	source.division_changed.connect(_on_division_changed)
	source.game_event.connect(_on_game_event)
	source.order_rejected.connect(_on_order_rejected)
	source.game_finished.connect(_on_game_finished)
	source.connection_lost.connect(_on_connection_lost)
	hud.top_bar.set_switch_visible(source.can_switch_player())
	hud.division_panel.set_split_merge_available(source.supports_split_merge())
	hud.action_menu.set_split_merge_available(source.supports_split_merge())
	hud.division_panel.set_formations_available(source.supports_formations())
	hud.action_menu.set_formations_available(source.supports_formations())
	hud.division_panel.set_command_available(source.supports_command())
	hud.action_menu.set_command_available(source.supports_command())
	hud.event_log.add_entry("Fuente de partida: %s" % source.source_name(), Palette.LOG_INFO)
	hud.top_bar.set_status_text(source.loading_text())
	source.start()


func _announce_controlled_player() -> void:
	var player_id := source.local_player_id
	if not _announce_player or source.state.get_player(player_id).is_empty():
		return
	_announce_player = false
	var color := Palette.side_color(source.state.side_of(player_id))
	hud.event_log.add_entry("Controlas a %s" % source.state.player_name(player_id), color)


# --- Source callbacks -----------------------------------------------------------

func _on_session_started(game_id: String, player_id: String) -> void:
	hud.top_bar.set_game_id(game_id)
	_refresh_top_bar()
	selection.clear()
	_announce_player = true
	_announce_controlled_player()
	if source.state.status != GameTypes.STATUS_FINISHED:
		hud.top_bar.set_ready_visible(source.needs_ready() and source.state.status == GameTypes.STATUS_WAITING)
	_on_state_updated(source.state)


func _on_map_received(map: MapData) -> void:
	projection = visual_config.projection(map.cell_size)
	map_objects = MapObjects.for_map(map)
	map_view.setup(map, projection, visual_config)
	decoration_layer.setup(map, map_objects, projection, visual_config)
	building_layer.setup(map_objects.buildings, projection, visual_config)
	resource_layer.setup(map_objects.resources, projection, visual_config)
	division_layer.set_map(map)
	division_layer.setup(projection, visual_config)
	battle_layer.setup(projection)
	command_layer.setup(projection, division_layer)
	camera.set_bounds(projection.map_rect(map.cols, map.rows))
	_on_zoom_changed(camera.zoom.x)


func _on_lobby_changed(_players: Array, status: String) -> void:
	_announce_controlled_player()
	hud.top_bar.set_ready_visible(source.needs_ready() and status == GameTypes.STATUS_WAITING)
	_refresh_top_bar()


func _on_state_updated(state: BattleState) -> void:
	_drop_vanished_selection(state)
	division_layer.sync_state(state, source.local_player_id)
	battle_layer.sync_battles(state.battles)
	command_layer.sync(state, source.local_player_id)
	if state.status != GameTypes.STATUS_WAITING:
		hud.top_bar.set_ready_visible(false)
	_refresh_top_bar()
	_refresh_panel()


func _on_division_changed(division: DivisionData, _reason: String) -> void:
	division_layer.update_division(division, source.state, source.local_player_id)
	if selection.is_selected(division.id):
		_refresh_panel()


func _on_game_event(event: GameEvent) -> void:
	if event.type == Protocol.VOLLEY:
		battle_layer.add_volley(Protocol.vec_from(event.data.get("from")), Protocol.vec_from(event.data.get("to")))
	var entry := EventFormatter.format(event, source.state)
	if not entry.is_empty():
		# Some messages (order_accepted) carry no tick: stamp them with the current one.
		var tick := event.tick if event.data.has("tick") else source.state.tick
		hud.event_log.add_entry(entry["text"], entry["color"], UiStyle.format_time(float(tick) / source.state.tick_rate))


func _on_order_rejected(code: String, message: String) -> void:
	hud.event_log.add_entry("Orden rechazada (%s): %s" % [code, message], Palette.LOG_ERROR)


func _on_game_finished(result: String, reason: String, winner_id: String) -> void:
	_finished = true
	_cancel_command_mode()
	hud.action_menu.close()
	var reason_text := EventFormatter.finish_reason(reason)
	match result:
		"victory":
			hud.game_over.show_result("¡Victoria!", reason_text, Palette.LOG_GOOD)
		"defeat":
			hud.game_over.show_result("Derrota", reason_text, Palette.LOG_ERROR)
		_:
			hud.game_over.show_result("Empate", reason_text, Palette.TEXT)
	if source.can_switch_player() and not winner_id.is_empty():
		hud.game_over.show_result("Gana %s" % source.state.player_name(winner_id), reason_text,
			Palette.side_color(source.state.side_of(winner_id)))
	_refresh_panel()


func _on_connection_lost(reason: String) -> void:
	hud.event_log.add_entry(reason, Palette.LOG_ERROR)
	if not _finished:
		_finished = true
		hud.game_over.show_result("Desconectado", reason, Palette.TEXT_DIM)


# --- Input ----------------------------------------------------------------------

func _on_primary_clicked(screen_pos: Vector2, additive := false) -> void:
	var world_pos := projection.screen_to_world(screen_pos)
	var clicked := _pick(screen_pos)
	if _command_mode == Order.ATTACK or _command_mode == Order.MERGE:
		clicked = _as_division(clicked)
	if _command_mode == Order.MOVE:
		_issue_move(world_pos)
		_cancel_command_mode()
	elif _command_mode == Order.ATTACK:
		if not clicked.is_empty() and _is_enemy(clicked):
			for id in _commandable_ids():
				_issue(Order.attack(id, clicked))
		else:
			hud.event_log.add_entry("Ataque cancelado: haz clic sobre una división enemiga", Palette.LOG_ERROR)
		_cancel_command_mode()
	elif _command_mode == ASSIGN_COMMANDER:
		var command := source.state.get_command(clicked)
		if command != null and command.player_id == source.local_player_id and command.is_active():
			for id in _commandable_ids():
				source.assign_commander(id, command.id)
		else:
			hud.event_log.add_entry("Reasignación cancelada: haz clic sobre un general o comandante propio activo", Palette.LOG_ERROR)
		_cancel_command_mode()
	elif _command_mode == Order.MERGE:
		var ids := _commandable_ids()
		if _is_friendly(clicked) and not (ids.size() == 1 and ids[0] == clicked):
			for id in ids:
				if id != clicked:
					_issue(Order.merge(id, clicked))
		else:
			hud.event_log.add_entry("Unión cancelada: haz clic sobre otra división propia", Palette.LOG_ERROR)
		_cancel_command_mode()
	elif additive and _is_friendly(clicked):
		selection.toggle(clicked)
	elif clicked.is_empty():
		if not additive:
			selection.clear()
	else:
		selection.select(clicked)
		_open_action_menu()


## Right click = contextual order for every selected division: enemy ->
## ATTACK, anything else -> MOVE (several divisions line up, see GroupMove).
func _on_secondary_clicked(screen_pos: Vector2) -> void:
	var ids := _commandable_ids()
	if ids.is_empty():
		return
	_cancel_command_mode()
	var clicked := division_layer.pick(screen_pos)
	if clicked.is_empty():
		_issue_move(projection.screen_to_world(screen_pos))
	elif _is_enemy(clicked):
		for id in ids:
			_issue(Order.attack(id, clicked))


## A command marker stands for its host division when a division is expected.
func _as_division(id: String) -> String:
	var command := source.state.get_command(id)
	return command.host_division_id if command != null else id


## Entity under a screen point: command markers (drawn above the divisions)
## first, then divisions, buildings and resources.
func _pick(screen_pos: Vector2) -> String:
	var id := command_layer.pick(screen_pos)
	if id.is_empty():
		id = division_layer.pick(screen_pos)
	if id.is_empty():
		id = building_layer.pick(screen_pos)
	if id.is_empty():
		id = resource_layer.pick(screen_pos)
	return id


## Orders from the panel, the menu or the hotkeys, for every selected division.
func _on_order_requested(order_type: String) -> void:
	hud.action_menu.close()
	var ids := _commandable_ids()
	if ids.is_empty():
		return
	if order_type == Order.MOVE:
		_set_command_mode(Order.MOVE, "Haz clic en el mapa para elegir el destino (Esc cancela)")
	elif order_type == Order.ATTACK:
		_set_command_mode(Order.ATTACK, "Haz clic en una división enemiga (Esc cancela)")
	elif order_type == Order.DEFEND:
		for id in ids:
			_issue(Order.defend(id))
	elif order_type == Order.RETREAT:
		for id in ids:
			_issue(Order.retreat(id))
	elif order_type == Order.HOLD:
		for id in ids:
			_issue(Order.hold(id))
	elif order_type == ASSIGN_COMMANDER and source.supports_command():
		_set_command_mode(ASSIGN_COMMANDER, "Haz clic en un general o comandante propio para ponerlo al mando (Esc cancela)")
	elif order_type == Order.SPLIT and source.supports_split_merge():
		for id in ids:
			_issue(Order.split(id))
	elif order_type == Order.MERGE and source.supports_split_merge():
		if ids.size() > 1:
			# Several selected: they all gather into the first one.
			for id in ids.slice(1):
				_issue(Order.merge(id, ids[0]))
		else:
			_set_command_mode(Order.MERGE, "Haz clic en otra división propia: irá hacia ella y se unirán (Esc cancela)")


func _on_cancel() -> void:
	if not _command_mode.is_empty():
		_cancel_command_mode()
	elif hud.action_menu.visible:
		hud.action_menu.close()
	else:
		selection.clear()


func _on_selection_changed(ids: Array) -> void:
	_cancel_command_mode()
	hud.action_menu.close()
	division_layer.set_selection(ids)
	var primary := selection.primary()
	command_layer.selected_command_id = primary if source.state.get_command(primary) != null else ""
	building_layer.set_selection(ids)
	resource_layer.set_selection(ids)
	_refresh_panel()


func _on_zoom_changed(zoom_level: float) -> void:
	var label_scale := visual_config.label_scale_for_zoom(zoom_level)
	division_layer.set_label_scale(label_scale)
	building_layer.set_label_scale(label_scale)
	resource_layer.set_label_scale(label_scale)


func _toggle_debug() -> void:
	_debug = not _debug
	hud.debug_overlay.visible = _debug
	division_layer.set_debug(_debug, source.state)


func _switch_player() -> void:
	if source.can_switch_player():
		source.switch_controlled_player()


func _exit() -> void:
	source.stop()
	exit_requested.emit()


# --- Orders ---------------------------------------------------------------------

## MOVE for every selected division; several of them line up in rows
## around the clicked point instead of all heading to the same spot.
func _issue_move(world_pos: Vector2) -> void:
	var ids := _commandable_ids()
	if ids.is_empty():
		return
	if source.map_data != null and not source.map_data.is_passable(world_pos):
		hud.event_log.add_entry("Destino intransitable", Palette.LOG_ERROR)
		return
	if ids.size() == 1:
		_issue(Order.move(ids[0], world_pos))
		return
	var positions := []
	var radii := []
	for id in ids:
		var d := source.state.get_division(id)
		positions.append(d.position)
		radii.append(d.radius if d.radius > 0.0 else GROUP_FALLBACK_RADIUS)
	var targets := GroupMove.slots(positions, radii, world_pos)
	for i in ids.size():
		var target := targets[i]
		if source.map_data != null and not source.map_data.is_passable(target):
			target = world_pos  # the simulation spreads them apart on arrival
		_issue(Order.move(ids[i], target))


func _issue(order: Order) -> void:
	if order.division_id.is_empty():
		return
	source.submit_order(order)


## Primary selected division if the local player can command it, else "".
func _commandable_selection() -> String:
	var ids := _commandable_ids()
	return ids[0] if not ids.is_empty() else ""


## Selected divisions the local player can command right now.
func _commandable_ids() -> Array[String]:
	var result: Array[String] = []
	if _finished or source.state.status != GameTypes.STATUS_RUNNING:
		return result
	for id in selection.ids():
		var d := source.state.get_division(id)
		if d != null and d.is_alive() and d.player_id == source.local_player_id:
			result.append(id)
	return result


## Box selection: own divisions whose center is inside the rectangle
## (viewport pixels). Shift adds them to the current selection.
func _on_box_released(from: Vector2, to: Vector2, additive: bool) -> void:
	hud.selection_box.hide_box()
	var rect := Rect2(from, Vector2.ZERO).expand(to)
	var ids: Array = []
	if additive:
		ids.append_array(selection.ids())
	for view in division_layer.views():
		var d: DivisionData = view.data
		if d != null and d.is_alive() and d.player_id == source.local_player_id \
				and rect.has_point(_to_viewport(view.global_position)) and not ids.has(d.id):
			ids.append(d.id)
	if ids.is_empty():
		selection.clear()
	else:
		selection.select_many(ids)


## Ctrl+A: every own division.
func _select_all() -> void:
	var ids: Array = []
	for d in source.state.all_divisions():
		if d.is_alive() and d.player_id == source.local_player_id:
			ids.append(d.id)
	if not ids.is_empty():
		selection.select_many(ids)


func _on_formation_requested(formation: String) -> void:
	hud.action_menu.close()
	if not source.supports_formations():
		return
	for id in _commandable_ids():
		if source.state.get_division(id).formation != formation:
			_issue(Order.change_formation(id, formation))


## F: next formation (after the primary's) for every selected division.
func _cycle_formation() -> void:
	var primary := _commandable_selection()
	if primary.is_empty():
		return
	_on_formation_requested(Formations.next(source.state.get_division(primary).formation))


func _is_friendly(division_id: String) -> bool:
	var d := source.state.get_division(division_id)
	return d != null and d.is_alive() and d.player_id == source.local_player_id


## Removes from the selection the divisions that disappeared (merged).
func _drop_vanished_selection(state: BattleState) -> void:
	var kept: Array = []
	for id in selection.ids():
		if state.get_division(id) != null or state.get_command(id) != null \
				or map_objects.building(id) != null or map_objects.resource(id) != null:
			kept.append(id)
	if kept.size() == selection.count():
		return
	if kept.is_empty():
		selection.clear()
	else:
		selection.select_many(kept)


func _is_enemy(division_id: String) -> bool:
	var d := source.state.get_division(division_id)
	return d != null and d.is_alive() and d.player_id != source.local_player_id


## Opens the order menu next to the selected division if it is commandable.
func _open_action_menu() -> void:
	var view := division_layer.view(_commandable_selection())
	if view == null:
		hud.action_menu.close()
		return
	hud.action_menu.open(view.data.display_name, _to_viewport(view.global_position))
	hud.action_menu.set_current_formation(view.data.formation)


## Keeps the open menu next to its division; closes it when the division
## can no longer be commanded (destroyed, game over, player switched...).
func _follow_action_menu() -> void:
	if not hud.action_menu.visible:
		return
	var view := division_layer.view(_commandable_selection())
	if view == null:
		hud.action_menu.close()
	else:
		hud.action_menu.follow(_to_viewport(view.global_position))


## Canvas (isometric) position -> viewport pixels, for HUD elements.
func _to_viewport(canvas_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * canvas_position


func _set_command_mode(mode: String, hint: String) -> void:
	_command_mode = mode
	map_view.marks.preview_division_ids = _commandable_ids()
	map_view.marks.preview_order_type = mode
	hud.division_panel.set_mode_hint(hint)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)


func _cancel_command_mode() -> void:
	_command_mode = ""
	map_view.marks.preview_division_ids = []
	hud.division_panel.set_mode_hint("")
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# --- UI refresh -----------------------------------------------------------------

func _refresh_top_bar() -> void:
	var state := source.state
	var countdown := float(state.countdown_ticks) / float(maxi(state.tick_rate, 1))
	hud.top_bar.set_status(state.status, state.players.size(), countdown)
	hud.top_bar.set_elapsed(state.elapsed_seconds())
	hud.top_bar.set_player(state.player_name(source.local_player_id), state.side_of(source.local_player_id))


func _refresh_panel() -> void:
	var state := source.state
	var d := state.get_division(selection.primary())
	if d == null:
		_refresh_panel_object(selection.primary())
		return
	var own := d.player_id == source.local_player_id
	var owner_text := "Tu división" if own else "División enemiga (%s)" % state.player_name(d.player_id)
	if selection.count() > 1:
		owner_text += " · %d seleccionadas: las órdenes van a todas" % selection.count()
	hud.division_panel.show_division(d, owner_text, Palette.side_color(state.side_of(d.player_id)),
		EventFormatter.describe_order(d.order, state), not _commandable_selection().is_empty())
	_refresh_command_rows(d)


## Panel for a selected general/commander, building or resource (or empty).
func _refresh_panel_object(id: String) -> void:
	var command := source.state.get_command(id)
	if command != null:
		_show_command_panel(command)
		return
	var b := map_objects.building(id)
	if b != null:
		hud.division_panel.show_info(b.display_name, "Edificio %s" % Palette.side_name(b.side), Palette.side_color(b.side), [
			["Vida", "%d / %d" % [b.hp, b.max_hp]],
			["Tamaño", "%dx%d casillas" % [b.size.x, b.size.y]],
			["Casilla", "(%d, %d)" % [b.origin.x, b.origin.y]],
		])
		return
	var r := map_objects.resource(id)
	if r != null:
		hud.division_panel.show_info(r.display_name, "Recurso", Palette.resource_color(r.type), [
			["Cantidad", "%d / %d" % [r.amount, r.max_amount]],
			["Casilla", "(%d, %d)" % [r.cell.x, r.cell.y]],
		])
		return
	hud.division_panel.show_empty()


## General/commander panel: status, radii and, for own units, the
## subordinate divisions and whether each one is within the comm radius.
func _show_command_panel(c: CommandData) -> void:
	var state := source.state
	var rows := [
		["Rol", c.role_label()],
		["Estado", CommandData.status_label(c.status)],
		["División anfitriona", state.division_name(c.host_division_id)],
		["Radio de comunicación", str(roundi(c.comm_radius))],
		["Radio de influencia", str(roundi(c.influence_radius))],
	]
	if c.player_id == source.local_player_id:
		var subordinates := state.subordinates(c.id)
		var in_range := 0
		for d in subordinates:
			if d.command_link == CommandData.LINK_IN_RANGE:
				in_range += 1
		rows.append(["Divisiones subordinadas", str(subordinates.size())])
		rows.append(["Enlace", "%d en rango · %d fuera" % [in_range, subordinates.size() - in_range]])
		for d in subordinates:
			rows.append(["  " + d.display_name, CommandData.link_label(d.command_link)])
		if c.is_general():
			var commanders := 0
			for other in state.all_commands():
				if other.player_id == c.player_id and not other.is_general() and other.is_alive():
					commanders += 1
			rows.append(["Comandantes", str(commanders)])
	var owner_text := "%s de %s" % [c.role_label(), state.player_name(c.player_id)]
	hud.division_panel.show_info(c.display_name, owner_text, Palette.side_color(state.side_of(c.player_id)), rows)


## Chain-of-command rows of an own division (hidden otherwise).
func _refresh_command_rows(d: DivisionData) -> void:
	var state := source.state
	if not state.has_chain_of_command() or d.player_id != source.local_player_id:
		hud.division_panel.set_command_info(false, "", "", "")
		return
	var command_text := "Directo al general"
	var command := state.get_command(d.commander_id)
	if command != null:
		command_text = "%s (%s)" % [command.display_name, CommandData.status_label(command.status)]
		if not command.is_active() and d.command_link != CommandData.LINK_NO_COMMAND:
			command_text += " · órdenes vía general"
	var pending_text := "Ninguna"
	if d.pending_order != null:
		pending_text = "%s · en camino con mensajero, ~%d s" % [
			EventFormatter.describe_order(d.pending_order, state), ceili(state.ticks_to_seconds(d.pending_eta_ticks)),
		]
	hud.division_panel.set_command_info(true, command_text, CommandData.link_label(d.command_link), pending_text)


func _toggle_command_radii() -> void:
	command_layer.show_radii = not command_layer.show_radii


func _process(_delta: float) -> void:
	_follow_action_menu()
	if not _debug or source == null:
		return
	var state := source.state
	var mouse := projection.screen_to_world(get_global_mouse_position())
	var cell := projection.screen_to_cell(get_global_mouse_position())
	var terrain := source.map_data.terrain_at(mouse) if source.map_data != null else "-"
	hud.debug_overlay.set_lines(PackedStringArray([
		"FPS: %d" % Engine.get_frames_per_second(),
		"Fuente: %s" % source.source_name(),
		"Partida: %s  estado: %s  tick: %d" % [state.game_id, state.status, state.tick],
		"Divisiones: %d vivas / %d" % [state.alive_count(), state.division_ids.size()],
		"Batallas activas: %d" % state.battles.size(),
		"Jugador local: %s" % source.local_player_id,
		"Zoom: %.2f" % camera.zoom.x,
		"Cursor: mundo (%d, %d) celda (%d, %d) %s" % [roundi(mouse.x), roundi(mouse.y), cell.x, cell.y, terrain],
	]))
	division_layer.set_debug(true, state)
