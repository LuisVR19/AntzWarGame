class_name DivisionPanel
extends PanelContainer
## Right panel: stats of the selected division and the order buttons.
## Buttons only emit `order_requested(type)`; they contain no game logic.

signal order_requested(order_type: String)

const WIDTH := 290.0
const STATS := [
	["units", "Cantidad"],
	["attack", "Fuerza"],
	["defense", "Defensa"],
	["morale", "Moral"],
	["speed", "Velocidad"],
	["fatigue", "Fatiga"],
	["experience", "Experiencia"],
	["terrain", "Terreno"],
	["state", "Estado"],
	["order", "Orden actual"],
]
const BUTTONS := [
	["MOVE", "MOVER [1]"],
	["ATTACK", "ATACAR [2]"],
	["DEFEND", "DEFENDER [3]"],
	["RETREAT", "RETIRARSE [4]"],
	["HOLD", "MANTENER [5]"],
]

var _title: Label
var _owner: Label
var _empty: Label
var _details: VBoxContainer
var _values: Dictionary = {}  # stat key -> Label
var _buttons: Dictionary = {}  # order type -> Button
var _hint: Label


func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH - 10.0
	offset_right = -10.0
	offset_top = 56.0
	UiStyle.apply_panel(self)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	_title = UiStyle.label("División", 18)
	_owner = UiStyle.label("", 13, Palette.TEXT_DIM)
	box.add_child(_title)
	box.add_child(_owner)

	_empty = UiStyle.label("Haz clic en una división para seleccionarla.\nClic derecho: mover / atacar.", 13, Palette.TEXT_DIM)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	_empty.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	box.add_child(_empty)

	_details = VBoxContainer.new()
	box.add_child(_details)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	_details.add_child(grid)
	for stat in STATS:
		grid.add_child(UiStyle.label(stat[1], 13, Palette.TEXT_DIM))
		var value := UiStyle.label("-", 13)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD
		value.custom_minimum_size = Vector2(150, 0)
		grid.add_child(value)
		_values[stat[0]] = value

	_details.add_child(HSeparator.new())
	for entry in BUTTONS:
		var order_type: String = entry[0]
		var b := UiStyle.button(entry[1])
		b.pressed.connect(func() -> void: order_requested.emit(order_type))
		_details.add_child(b)
		_buttons[order_type] = b

	_hint = UiStyle.label("", 13, Palette.SELECTION)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	box.add_child(_hint)
	show_empty()


func show_empty() -> void:
	_title.text = "Ninguna división"
	_owner.text = ""
	_empty.visible = true
	_details.visible = false
	set_mode_hint("")


## `can_command` enables the order buttons (own, alive, game running).
func show_division(d: DivisionData, owner_text: String, side_color: Color, order_text: String, can_command: bool) -> void:
	_title.text = d.display_name
	_title.add_theme_color_override("font_color", side_color.lightened(0.3))
	_owner.text = owner_text
	_empty.visible = false
	_details.visible = true
	_set_value("units", "%d / %d" % [d.unit_count, d.max_unit_count])
	_set_value("attack", "%.1f" % d.attack)
	_set_value("defense", "%.1f" % d.defense)
	_set_value("morale", "%.0f%%%s" % [d.morale, " (desbandada)" if d.routed else ""])
	_set_value("speed", "%.0f" % d.speed)
	_set_value("fatigue", "%.0f%%" % d.fatigue)
	_set_value("experience", "%.1f" % d.experience)
	_set_value("terrain", GameTypes.terrain_label(d.terrain))
	_set_value("state", GameTypes.state_label(d.state) + (" · en combate" if d.in_battle else ""))
	_set_value("order", order_text)
	for order_type in _buttons.keys():
		_buttons[order_type].disabled = not can_command


func set_mode_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = not text.is_empty()


func _set_value(key: String, text: String) -> void:
	var l: Label = _values[key]
	l.text = text
