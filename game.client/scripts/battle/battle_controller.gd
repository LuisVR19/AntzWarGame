class_name BattleController
extends Node2D
## Root of the battle scene. Connects the GameStateSource (local or network)
## to the views, the input and the HUD. It is the only place that knows how
## user intents become Orders.

signal exit_requested

var source: GameStateSource
var _command_mode := ""  # "", Order.MOVE or Order.ATTACK (waiting for a click)
var _debug := false
var _finished := false

@onready var map_view: MapView = $MapView
@onready var battle_layer: BattleLayer = $BattleLayer
@onready var division_layer: DivisionLayer = $DivisionLayer
@onready var camera: BattleCamera = $Camera
@onready var selection: SelectionManager = $SelectionManager
@onready var battle_input: BattleInput = $BattleInput
@onready var hud: Hud = $HUD


func _ready() -> void:
	InputActions.ensure()
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
	hud.event_log.add_entry("Fuente de partida: %s" % source.source_name(), Palette.LOG_INFO)
	source.start()


# --- Source callbacks -----------------------------------------------------------

func _on_session_started(game_id: String, player_id: String) -> void:
	hud.top_bar.set_game_id(game_id)
	_refresh_top_bar()
	selection.clear()
	var color := Palette.side_color(source.state.side_of(player_id))
	hud.event_log.add_entry("Controlas a %s" % source.state.player_name(player_id), color)
	if source.state.status != GameTypes.STATUS_FINISHED:
		hud.top_bar.set_ready_visible(source.needs_ready() and source.state.status == GameTypes.STATUS_WAITING)
	_on_state_updated(source.state)


func _on_map_received(map: MapData) -> void:
	map_view.set_map(map)
	division_layer.set_map(map)
	camera.set_bounds(map.bounds())


func _on_lobby_changed(_players: Array, status: String) -> void:
	hud.top_bar.set_ready_visible(source.needs_ready() and status == GameTypes.STATUS_WAITING)
	_refresh_top_bar()


func _on_state_updated(state: BattleState) -> void:
	division_layer.sync_state(state, source.local_player_id)
	battle_layer.sync_battles(state.battles)
	if state.status != GameTypes.STATUS_WAITING:
		hud.top_bar.set_ready_visible(false)
	_refresh_top_bar()
	_refresh_panel()


func _on_division_changed(division: DivisionData, _reason: String) -> void:
	division_layer.update_division(division, source.state, source.local_player_id)
	if selection.is_selected(division.id):
		_refresh_panel()


func _on_game_event(event: GameEvent) -> void:
	var entry := EventFormatter.format(event, source.state)
	if not entry.is_empty():
		hud.event_log.add_entry(entry["text"], entry["color"], UiStyle.format_time(float(event.tick) / source.state.tick_rate))


func _on_order_rejected(code: String, message: String) -> void:
	hud.event_log.add_entry("Orden rechazada (%s): %s" % [code, message], Palette.LOG_ERROR)


func _on_game_finished(result: String, reason: String, winner_id: String) -> void:
	_finished = true
	_cancel_command_mode()
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

func _on_primary_clicked(world_pos: Vector2) -> void:
	var clicked := division_layer.pick(world_pos)
	if _command_mode == Order.MOVE:
		_issue_move(world_pos)
		_cancel_command_mode()
	elif _command_mode == Order.ATTACK:
		if not clicked.is_empty() and _is_enemy(clicked):
			_issue(Order.attack(_commandable_selection(), clicked))
		else:
			hud.event_log.add_entry("Ataque cancelado: haz clic sobre una división enemiga", Palette.LOG_ERROR)
		_cancel_command_mode()
	elif clicked.is_empty():
		selection.clear()
	else:
		selection.select(clicked)


## Right click = contextual order: enemy -> ATTACK, ground -> MOVE.
func _on_secondary_clicked(world_pos: Vector2) -> void:
	if _commandable_selection().is_empty():
		return
	_cancel_command_mode()
	var clicked := division_layer.pick(world_pos)
	if clicked.is_empty():
		_issue_move(world_pos)
	elif _is_enemy(clicked):
		_issue(Order.attack(_commandable_selection(), clicked))


func _on_order_requested(order_type: String) -> void:
	var division_id := _commandable_selection()
	if division_id.is_empty():
		return
	if order_type == Order.MOVE:
		_set_command_mode(Order.MOVE, "Haz clic en el mapa para elegir el destino (Esc cancela)")
	elif order_type == Order.ATTACK:
		_set_command_mode(Order.ATTACK, "Haz clic en una división enemiga (Esc cancela)")
	elif order_type == Order.DEFEND:
		_issue(Order.defend(division_id))
	elif order_type == Order.RETREAT:
		_issue(Order.retreat(division_id))
	elif order_type == Order.HOLD:
		_issue(Order.hold(division_id))


func _on_cancel() -> void:
	if not _command_mode.is_empty():
		_cancel_command_mode()
	else:
		selection.clear()


func _on_selection_changed(ids: Array) -> void:
	_cancel_command_mode()
	division_layer.set_selection(ids)
	_refresh_panel()


func _on_zoom_changed(zoom_level: float) -> void:
	division_layer.set_label_scale(clampf(1.0 / zoom_level, 0.6, 2.5))


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

func _issue_move(world_pos: Vector2) -> void:
	var division_id := _commandable_selection()
	if division_id.is_empty():
		return
	if source.map_data != null and not source.map_data.is_passable(world_pos):
		hud.event_log.add_entry("Destino intransitable", Palette.LOG_ERROR)
		return
	_issue(Order.move(division_id, world_pos))


func _issue(order: Order) -> void:
	if order.division_id.is_empty():
		return
	source.submit_order(order)


## Selected division if the local player can command it right now, else "".
func _commandable_selection() -> String:
	var id := selection.primary()
	if id.is_empty() or _finished or source.state.status != GameTypes.STATUS_RUNNING:
		return ""
	var d := source.state.get_division(id)
	if d == null or not d.is_alive() or d.player_id != source.local_player_id:
		return ""
	return id


func _is_enemy(division_id: String) -> bool:
	var d := source.state.get_division(division_id)
	return d != null and d.is_alive() and d.player_id != source.local_player_id


func _set_command_mode(mode: String, hint: String) -> void:
	_command_mode = mode
	hud.division_panel.set_mode_hint(hint)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)


func _cancel_command_mode() -> void:
	_command_mode = ""
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
		hud.division_panel.show_empty()
		return
	var own := d.player_id == source.local_player_id
	var owner_text := "Tu división" if own else "División enemiga (%s)" % state.player_name(d.player_id)
	hud.division_panel.show_division(d, owner_text, Palette.side_color(state.side_of(d.player_id)),
		EventFormatter.describe_order(d.order, state), not _commandable_selection().is_empty())


func _process(_delta: float) -> void:
	if not _debug or source == null:
		return
	var state := source.state
	var mouse := get_global_mouse_position()
	var terrain := source.map_data.terrain_at(mouse) if source.map_data != null else "-"
	hud.debug_overlay.set_lines(PackedStringArray([
		"FPS: %d" % Engine.get_frames_per_second(),
		"Fuente: %s" % source.source_name(),
		"Partida: %s  estado: %s  tick: %d" % [state.game_id, state.status, state.tick],
		"Divisiones: %d vivas / %d" % [state.alive_count(), state.division_ids.size()],
		"Batallas activas: %d" % state.battles.size(),
		"Jugador local: %s" % source.local_player_id,
		"Zoom: %.2f" % camera.zoom.x,
		"Cursor: (%d, %d) %s" % [roundi(mouse.x), roundi(mouse.y), terrain],
	]))
	division_layer.set_debug(true, state)
