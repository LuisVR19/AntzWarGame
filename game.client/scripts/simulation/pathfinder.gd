class_name Pathfinder
extends RefCounted
## Grid A* for the local simulation, equivalent to the Go server's
## movement.FindPath: water is solid, no corner cutting on diagonals, a tile
## costs 1 / its movement modifier (forest and hills are avoided when a faster
## way exists) and the grid route is smoothed into few straight segments.

var _map: MapData
var _grid := AStarGrid2D.new()
var _sample_step := 6.25  # world units between terrain samples on a segment
var _movement := PackedFloat32Array()  # movement modifier per cell (row-major)


func _init(map: MapData) -> void:
	_map = map
	_sample_step = map.cell_size / 8.0
	_grid.region = Rect2i(0, 0, map.cols, map.rows)
	_grid.cell_size = Vector2(map.cell_size, map.cell_size)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_grid.update()
	_movement.resize(map.cols * map.rows)
	for row in map.rows:
		for col in map.cols:
			var cell := Vector2i(col, row)
			var modifier := map.terrain.movement(map.type_at_cell(cell))
			_movement[row * map.cols + col] = modifier
			if modifier <= 0.0:
				_grid.set_point_solid(cell, true)
			else:
				_grid.set_point_weight_scale(cell, 1.0 / modifier)


## Waypoints in world units from `from` to `to`, excluding `from` and ending
## exactly at `to`. Empty when `to` is impassable or unreachable.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not _map.is_passable(to):
		return result
	var start := _map.cell_of(from)
	var goal := _map.cell_of(to)
	if start == goal or not _grid.is_in_boundsv(start) or _grid.is_point_solid(start):
		result.append(to)
		return result
	var cells := _grid.get_id_path(start, goal)
	if cells.is_empty():
		return result
	for i in range(1, cells.size() - 1):  # skip the start cell; end on the exact target
		result.append(_map.cell_rect(cells[i]).get_center())
	result.append(to)
	return _smooth(from, result)


## True if `to` can be reached from `from`.
func is_reachable(from: Vector2, to: Vector2) -> bool:
	return not find_path(from, to).is_empty()


## Drops intermediate waypoints ("string pulling"): from each anchor the
## straight segment is extended while it stays passable and not slower than
## the terrain the grid route crossed (same rule as the server).
func _smooth(from: Vector2, points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var anchor := from
	var i := 0
	while i < points.size():
		var best := i
		var slowest := _movement_at(points[i])
		for j in range(i + 1, points.size()):
			slowest = minf(slowest, _movement_at(points[j]))
			if not _segment_ok(anchor, points[j], slowest):
				break
			best = j
		out.append(points[best])
		anchor = points[best]
		i = best + 1
	return out


func _segment_ok(a: Vector2, b: Vector2, min_movement: float) -> bool:
	var steps := maxi(ceili(a.distance_to(b) / _sample_step), 1)
	for k in steps + 1:
		var m := _movement_at(a.lerp(b, float(k) / steps))
		if m <= 0.0 or m < min_movement:
			return false
	return true


func _movement_at(p: Vector2) -> float:
	var col := floori(p.x / _map.cell_size)
	var row := floori(p.y / _map.cell_size)
	if col < 0 or row < 0 or col >= _map.cols or row >= _map.rows:
		return 0.0
	return _movement[row * _map.cols + col]
