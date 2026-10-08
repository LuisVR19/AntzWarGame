class_name DivisionActionMenu
extends PanelContainer
## Floating order menu that opens next to an own division when it is
## clicked, and follows it on screen. Buttons only emit order_requested(type);
## BattleController decides what each order means (MOVE/ATTACK wait for a click).

signal order_requested(order_type: String)
signal formation_requested(formation: String)

## Offset from the division's screen position to the menu's top-left corner.
const OFFSET := Vector2(70, -50)
const MARGIN := 6.0

var _title: Label
var _buttons: Dictionary = {}  # order type -> Button
var _formations: FormationPicker
var _formations_title: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiStyle.apply_panel(self, Palette.PANEL_BG, 8.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_title = UiStyle.label("", 13, Palette.SELECTION)
	box.add_child(_title)
	for entry in DivisionPanel.BUTTONS:
		var order_type: String = entry[0]
		var b := UiStyle.button(entry[1], 150.0)
		b.pressed.connect(func() -> void: order_requested.emit(order_type))
		box.add_child(b)
		_buttons[order_type] = b
	_formations_title = UiStyle.label("Formación", 12, Palette.TEXT_DIM)
	box.add_child(_formations_title)
	_formations = FormationPicker.new()
	_formations.formation_requested.connect(func(f: String) -> void: formation_requested.emit(f))
	box.add_child(_formations)


func set_formations_available(available: bool) -> void:
	_formations_title.visible = available
	_formations.visible = available


func set_current_formation(formation: String) -> void:
	_formations.set_current(formation)


func set_split_merge_available(available: bool) -> void:
	for order_type in DivisionPanel.SPLIT_MERGE:
		_buttons[order_type].visible = available


func set_command_available(available: bool) -> void:
	for order_type in DivisionPanel.COMMAND_ONLY:
		_buttons[order_type].visible = available


func open(title: String, screen_point: Vector2) -> void:
	_title.text = title
	show()
	reset_size()
	follow(screen_point)


func close() -> void:
	hide()


## Places the menu next to `screen_point`, kept inside the viewport.
func follow(screen_point: Vector2) -> void:
	var view := get_viewport_rect().size
	var pos := screen_point + OFFSET
	pos.x = clampf(pos.x, MARGIN, maxf(view.x - size.x - MARGIN, MARGIN))
	pos.y = clampf(pos.y, MARGIN, maxf(view.y - size.y - MARGIN, MARGIN))
	position = pos
