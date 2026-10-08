class_name FormationPicker
extends GridContainer
## One small button per formation (from formations.json). Only emits
## formation_requested(id); the tooltip explains strengths and weaknesses.

signal formation_requested(formation: String)

var _buttons: Dictionary = {}  # formation id -> Button
var _current := ""


func _ready() -> void:
	columns = 3
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)
	for id in Formations.ids():
		var formation: String = id
		var b := UiStyle.button(Formations.short_label(formation))
		b.custom_minimum_size = Vector2(0, 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = Formations.tooltip(formation)
		b.pressed.connect(func() -> void: formation_requested.emit(formation))
		add_child(b)
		_buttons[formation] = b


## Highlights the formation the division is in.
func set_current(formation: String) -> void:
	_current = formation
	for id in _buttons.keys():
		var b: Button = _buttons[id]
		if id == formation:
			b.add_theme_color_override("font_color", Palette.SELECTION)
			b.add_theme_color_override("font_disabled_color", Palette.SELECTION)
		else:
			b.remove_theme_color_override("font_color")
			b.remove_theme_color_override("font_disabled_color")


func set_enabled(enabled: bool) -> void:
	for b in _buttons.values():
		b.disabled = not enabled
