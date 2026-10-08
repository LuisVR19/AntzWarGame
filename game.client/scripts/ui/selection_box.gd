class_name SelectionBox
extends Control
## The rubber-band rectangle drawn while dragging with the left button to
## select several divisions (viewport coordinates). Purely visual.

var _rect := Rect2()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func show_box(from: Vector2, to: Vector2) -> void:
	_rect = Rect2(from, Vector2.ZERO).expand(to)
	visible = true
	queue_redraw()


func hide_box() -> void:
	visible = false


func _draw() -> void:
	draw_rect(_rect, Color(Palette.SELECTION, 0.12))
	draw_rect(_rect, Color(Palette.SELECTION, 0.85), false, 1.5)
