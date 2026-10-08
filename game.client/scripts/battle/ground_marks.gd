class_name GroundMarks
extends Node2D
## Flat marks painted on the ground, below every object: the grid, the map
## border, order routes, the movement radius of the selected division and,
## while an order waits for its target click, a preview line to the cursor.

var division_layer: DivisionLayer
## Divisions whose order is waiting for a target click (empty = none).
var preview_division_ids: Array = []
var preview_order_type := ""
var _map: MapData
var _projection: IsoProjection
var _show_grid := true


func setup(map: MapData, projection: IsoProjection, config: VisualConfig) -> void:
	_map = map
	_projection = projection
	_show_grid = config.show_grid
	queue_redraw()


func _process(_delta: float) -> void:
	if division_layer != null:
		queue_redraw()


func _draw() -> void:
	if _map == null or _projection == null:
		return
	if _show_grid:
		_draw_grid()
	var border := _projection.footprint(Vector2i.ZERO, Vector2i(_map.cols, _map.rows))
	border.append(border[0])
	draw_polyline(border, Palette.MAP_BORDER, 3.0)
	if division_layer == null:
		return
	for view in division_layer.views():
		_draw_division_marks(view)
	_draw_preview()


func _draw_preview() -> void:
	if preview_division_ids.is_empty():
		return
	var color := _order_color(preview_order_type)
	var cursor := get_global_mouse_position()
	for id in preview_division_ids:
		var view := division_layer.view(id)
		if view != null:
			draw_dashed_line(view.position, cursor, Color(color, 0.6), 2.0, 6.0)
	PlaceholderPainter.ellipse_outline(self, cursor, Vector2(14, 7), color, 2.0)


func _draw_grid() -> void:
	for col in range(1, _map.cols):
		draw_line(_projection.grid_to_screen(Vector2(col, 0)), _projection.grid_to_screen(Vector2(col, _map.rows)), Palette.GRID, 1.0)
	for row in range(1, _map.rows):
		draw_line(_projection.grid_to_screen(Vector2(0, row)), _projection.grid_to_screen(Vector2(_map.cols, row)), Palette.GRID, 1.0)


func _draw_division_marks(view: DivisionView) -> void:
	var radius := view.move_radius()
	if radius > 0.0 and division_layer.selected_count() == 1:  # one circle per group would clutter
		PlaceholderPainter.ellipse_outline(self, view.position, _projection.ground_radii(radius), Palette.MOVE_RADIUS, 1.5)
	var reach := view.attack_range()
	if reach > 0.0:
		PlaceholderPainter.ellipse_outline(self, view.position, _projection.ground_radii(reach), Palette.RANGE_MARK, 2.0)
	var d := view.data
	if d == null or not d.is_alive() or view.route_world.is_empty() or not (view.is_own or view.selected):
		return
	var color := _order_color(d.order_type())
	var from := view.position
	for p in view.route_world:
		var to := _projection.world_to_screen(p)
		draw_dashed_line(from, to, color, 2.0, 10.0)
		from = to
	PlaceholderPainter.ellipse(self, from, Vector2(6, 3), color)


static func _order_color(order_type: String) -> Color:
	match order_type:
		"ATTACK":
			return Palette.ORDER_ATTACK_LINE
		"RETREAT":
			return Palette.ORDER_RETREAT_LINE
		"MERGE":
			return Palette.ORDER_MERGE_LINE
	return Palette.ORDER_MOVE_LINE
