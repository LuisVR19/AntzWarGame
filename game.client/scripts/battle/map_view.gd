class_name MapView
extends Node2D
## Renders the battlefield (terrain + bases) from MapData. Redrawn only when
## the map changes.

const BASE_RADIUS := 70.0

var _map: MapData


func set_map(map: MapData) -> void:
	_map = map
	queue_redraw()


func _draw() -> void:
	if _map == null:
		return
	for row in _map.rows:
		for col in _map.cols:
			var cell := Vector2i(col, row)
			TerrainPainter.paint_tile(self, _map.type_at_cell(cell), _map.cell_rect(cell), cell)
	_draw_grid()
	for side in _map.spawns.size():
		_draw_base(_map.spawns[side], side)
	draw_rect(_map.bounds(), Palette.MAP_BORDER, false, 6.0)


func _draw_grid() -> void:
	var size := _map.size()
	for col in range(1, _map.cols):
		var x := col * _map.cell_size
		draw_line(Vector2(x, 0), Vector2(x, size.y), Palette.GRID, 1.0)
	for row in range(1, _map.rows):
		var y := row * _map.cell_size
		draw_line(Vector2(0, y), Vector2(size.x, y), Palette.GRID, 1.0)


## A base is an anthill: a mound with the entrance in the middle.
func _draw_base(center: Vector2, side: int) -> void:
	var color := Palette.side_color(side)
	draw_circle(center, BASE_RADIUS, Palette.NEST)
	draw_arc(center, BASE_RADIUS, 0.0, TAU, 64, color, 5.0)
	draw_circle(center, BASE_RADIUS * 0.45, Palette.NEST.lightened(0.15))
	draw_circle(center, BASE_RADIUS * 0.18, Palette.NEST_HOLE)
	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-BASE_RADIUS, BASE_RADIUS + 22), "Base %s" % Palette.side_name(side),
		HORIZONTAL_ALIGNMENT_CENTER, BASE_RADIUS * 2.0, 16, color)
