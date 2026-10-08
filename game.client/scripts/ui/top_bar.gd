class_name TopBar
extends PanelContainer
## Top strip: match status, elapsed time, controlled player, game id and the
## session buttons (ready, switch player in local mode, back to menu).

signal ready_pressed
signal switch_player_pressed
signal menu_pressed

var _status: Label
var _time: Label
var _player: Label
var _game: Label
var _ready_button: Button
var _switch_button: Button


func _ready() -> void:
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_bottom = 46.0
	UiStyle.apply_panel(self, Palette.PANEL_BG, 8.0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)

	_status = UiStyle.label("Conectando...", 16)
	_time = UiStyle.label("00:00", 16)
	_player = UiStyle.label("", 16)
	_game = UiStyle.label("", 13, Palette.TEXT_DIM)
	row.add_child(_status)
	row.add_child(_time)
	row.add_child(_player)
	row.add_child(_game)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_ready_button = UiStyle.button("¡Listo!", 110)
	_ready_button.visible = false
	_ready_button.pressed.connect(_on_ready_pressed)
	row.add_child(_ready_button)

	_switch_button = UiStyle.button("Cambiar jugador [Tab]", 190)
	_switch_button.visible = false
	_switch_button.pressed.connect(func() -> void: switch_player_pressed.emit())
	row.add_child(_switch_button)

	var menu := UiStyle.button("Menú", 80)
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	row.add_child(menu)


func set_status(status: String, players_count: int, countdown_seconds: float) -> void:
	if status == GameTypes.STATUS_WAITING:
		_status.text = "Esperando jugadores (%d/2)" % players_count
	elif status == GameTypes.STATUS_STARTING:
		_status.text = "Comienza en %ds" % ceili(countdown_seconds)
	elif status == GameTypes.STATUS_RUNNING:
		_status.text = "Batalla en curso"
	elif status == GameTypes.STATUS_FINISHED:
		_status.text = "Partida finalizada"
	else:
		_status.text = status


## Free text status, e.g. while the session is being set up.
func set_status_text(text: String) -> void:
	_status.text = text


func set_elapsed(seconds: float) -> void:
	_time.text = "Tiempo " + UiStyle.format_time(seconds)


func set_player(player_name: String, side: int) -> void:
	_player.text = "Jugador: %s (%s)" % [player_name, Palette.side_name(side)]
	_player.add_theme_color_override("font_color", Palette.side_color(side).lightened(0.3))


func set_game_id(game_id: String) -> void:
	_game.text = "Partida: %s" % game_id if not game_id.is_empty() else ""


func set_ready_visible(value: bool) -> void:
	_ready_button.visible = value


func set_switch_visible(value: bool) -> void:
	_switch_button.visible = value


func _on_ready_pressed() -> void:
	_ready_button.disabled = true
	_ready_button.text = "Esperando rival..."
	ready_pressed.emit()
