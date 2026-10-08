class_name GroundMarker
extends Node2D
## A flat shape lying on the ground under an entity: an ellipse (shadow,
## unit selection ring) or a polygon (building footprint).

var radii := Vector2(20, 10)
var polygon := PackedVector2Array()
var color := Color.WHITE
var filled := false
var width := 2.0


func set_ellipse(p_radii: Vector2, p_color: Color, p_filled := false, p_width := 2.0) -> void:
	radii = p_radii
	polygon = PackedVector2Array()
	_set_style(p_color, p_filled, p_width)


func set_polygon(points: PackedVector2Array, p_color: Color, p_filled := false, p_width := 2.0) -> void:
	polygon = points
	_set_style(p_color, p_filled, p_width)


func _set_style(p_color: Color, p_filled: bool, p_width: float) -> void:
	color = p_color
	filled = p_filled
	width = p_width
	queue_redraw()


func _draw() -> void:
	if not polygon.is_empty():
		if filled:
			draw_colored_polygon(polygon, color)
		else:
			var closed := polygon.duplicate()
			closed.append(polygon[0])
			draw_polyline(closed, color, width, true)
	elif filled:
		PlaceholderPainter.ellipse(self, Vector2.ZERO, radii, color)
	else:
		PlaceholderPainter.ellipse_outline(self, Vector2.ZERO, radii, color, width)
