class_name IsoProjection
extends RefCounted
## The ONLY place that converts between coordinate spaces:
##
##   world  - gameplay units used by the simulation and the server (pixels of
##            the old top-down map; one cell = cell_size world units)
##   grid   - world / cell_size; cell (c, r) covers [c, c+1) x [r, r+1)
##   screen - isometric canvas position where the views are drawn
##
##   screen.x = (grid.x - grid.y) * tile_width / 2
##   screen.y = (grid.x + grid.y) * tile_height / 2
##
## Camera zoom is applied by Camera2D on top of "screen", so it never affects
## these conversions.

var cell_size := 50.0
var tile_width := 64.0
var tile_height := 32.0


func _init(p_cell_size := 50.0, p_tile_width := 64.0, p_tile_height := 32.0) -> void:
	cell_size = p_cell_size
	tile_width = p_tile_width
	tile_height = p_tile_height


func world_to_grid(world: Vector2) -> Vector2:
	return world / cell_size


func grid_to_world(grid: Vector2) -> Vector2:
	return grid * cell_size


func grid_to_screen(grid: Vector2) -> Vector2:
	return Vector2((grid.x - grid.y) * tile_width * 0.5, (grid.x + grid.y) * tile_height * 0.5)


func screen_to_grid(screen: Vector2) -> Vector2:
	var a := screen.x / (tile_width * 0.5)
	var b := screen.y / (tile_height * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


func world_to_screen(world: Vector2) -> Vector2:
	return grid_to_screen(world_to_grid(world))


func screen_to_world(screen: Vector2) -> Vector2:
	return grid_to_world(screen_to_grid(screen))


func screen_to_cell(screen: Vector2) -> Vector2i:
	var g := screen_to_grid(screen)
	return Vector2i(floori(g.x), floori(g.y))


## Screen position of the center of a cell (where its tile is drawn).
func cell_center(cell: Vector2i) -> Vector2:
	return grid_to_screen(Vector2(cell) + Vector2(0.5, 0.5))


## Screen corners (top, right, bottom, left) of a rectangle of cells.
func footprint(origin: Vector2i, size: Vector2i) -> PackedVector2Array:
	var o := Vector2(origin)
	var s := Vector2(size)
	return PackedVector2Array([
		grid_to_screen(o),
		grid_to_screen(o + Vector2(s.x, 0)),
		grid_to_screen(o + s),
		grid_to_screen(o + Vector2(0, s.y)),
	])


## A circle of `world_radius` on the ground is an ellipse on screen; returns
## its horizontal and vertical radii.
func ground_radii(world_radius: float) -> Vector2:
	var r := world_radius / cell_size * sqrt(2.0) * 0.5
	return Vector2(r * tile_width, r * tile_height)


## Screen bounding rectangle of a cols x rows map (a diamond).
func map_rect(cols: int, rows: int) -> Rect2:
	var hw := tile_width * 0.5
	var hh := tile_height * 0.5
	return Rect2(Vector2(-rows * hw, 0.0), Vector2((cols + rows) * hw, (cols + rows) * hh))


## Polygon approximating an ellipse centered at `center`.
static func ellipse_points(center: Vector2, radii: Vector2, segments := 32) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments + 1:
		var a := TAU * i / segments
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return points
