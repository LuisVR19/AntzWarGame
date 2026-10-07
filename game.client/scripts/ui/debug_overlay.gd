class_name DebugOverlay
extends PanelContainer
## Debug info (F3): FPS, division count, tick, source, cursor terrain...
## Per-division debug text is drawn in the world by DivisionOverlay.

var _label: Label


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	offset_left = 10.0
	offset_top = 56.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_panel(self, Color(0, 0, 0, 0.6), 6.0)
	_label = UiStyle.label("", 12, Palette.LOG_GOOD)
	add_child(_label)
	visible = false


func set_lines(lines: PackedStringArray) -> void:
	_label.text = "\n".join(lines)
