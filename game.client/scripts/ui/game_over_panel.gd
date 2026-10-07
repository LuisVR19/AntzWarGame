class_name GameOverPanel
extends PanelContainer
## Centered result panel shown when the match ends or the connection drops.

signal back_pressed
signal close_pressed

var _title: Label
var _subtitle: Label


func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -220.0
	offset_right = 220.0
	offset_top = -90.0
	offset_bottom = 90.0
	UiStyle.apply_panel(self, Color(0.05, 0.05, 0.06, 0.95), 18.0)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	_title = UiStyle.label("", 32)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle = UiStyle.label("", 15, Palette.TEXT_DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_title)
	box.add_child(_subtitle)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var back := UiStyle.button("Volver al menú", 150)
	back.pressed.connect(func() -> void: back_pressed.emit())
	buttons.add_child(back)
	var stay := UiStyle.button("Ver el mapa", 120)
	stay.pressed.connect(_on_close)
	buttons.add_child(stay)
	visible = false


func show_result(title: String, subtitle: String, color: Color) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", color)
	_subtitle.text = subtitle
	visible = true


func _on_close() -> void:
	visible = false
	close_pressed.emit()
