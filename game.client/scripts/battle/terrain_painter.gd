class_name TerrainPainter
extends RefCounted
## Draws placeholder terrain with primitive shapes. To switch to real art,
## replace MapView's use of this class with a TileMapLayer; the map data
## (MapData) stays the same.


static func paint_tile(canvas: CanvasItem, type: String, rect: Rect2, cell: Vector2i) -> void:
	canvas.draw_rect(rect, _shade(Palette.terrain_color(type), cell))
	match type:
		"FOREST":
			_paint_forest(canvas, rect, cell)
		"HILL":
			_paint_hill(canvas, rect)
		"WATER":
			_paint_water(canvas, rect, cell)


## Pseudo-random but deterministic value in [0, 1) for a cell.
static func noise(cell: Vector2i, salt: int) -> float:
	return float(posmod(hash(Vector3i(cell.x, cell.y, salt)), 1000)) / 1000.0


static func _shade(base: Color, cell: Vector2i) -> Color:
	var n := noise(cell, 7) * 0.06 - 0.03
	return Color(base.r + n, base.g + n, base.b + n, base.a)


static func _paint_forest(canvas: CanvasItem, rect: Rect2, cell: Vector2i) -> void:
	var s := rect.size.x
	for i in 4:
		var offset := Vector2(noise(cell, i * 2), noise(cell, i * 2 + 1)) * (s * 0.7) + Vector2(s, s) * 0.15
		var radius := s * (0.14 + noise(cell, i + 20) * 0.08)
		canvas.draw_circle(rect.position + offset, radius, Palette.TREE)
		canvas.draw_circle(rect.position + offset + Vector2(-radius, -radius) * 0.25, radius * 0.55, Palette.TREE_LIGHT)


static func _paint_hill(canvas: CanvasItem, rect: Rect2) -> void:
	var c := rect.get_center()
	var s := rect.size.x
	canvas.draw_circle(c + Vector2(0, s * 0.05), s * 0.42, Palette.HILL_DARK)
	canvas.draw_circle(c, s * 0.3, Palette.terrain_color("HILL"))
	canvas.draw_circle(c - Vector2(s, s) * 0.06, s * 0.14, Palette.HILL_LIGHT)


static func _paint_water(canvas: CanvasItem, rect: Rect2, cell: Vector2i) -> void:
	var s := rect.size.x
	for i in 2:
		var y := rect.position.y + s * (0.3 + 0.4 * i) + noise(cell, i) * 4.0
		var x0 := rect.position.x + s * 0.15
		canvas.draw_line(Vector2(x0, y), Vector2(x0 + s * 0.3, y - 3), Palette.WATER_WAVE, 2.0)
		canvas.draw_line(Vector2(x0 + s * 0.3, y - 3), Vector2(x0 + s * 0.6, y), Palette.WATER_WAVE, 2.0)
