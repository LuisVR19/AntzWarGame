class_name MovementSystem
extends RefCounted
## Moves divisions along straight segments: step() towards one point and
## follow() along a list of waypoints produced by Pathfinder.


## Moves from `from` towards `to` for `delta` seconds at `speed` units/s,
## applying the terrain movement modifier of the current position.
## Returns {position: Vector2, moved: float, arrived: bool, blocked: bool}.
func step(map: MapData, from: Vector2, to: Vector2, speed: float, delta: float) -> Dictionary:
	var res := _advance(map, from, to, speed * map.terrain.movement(map.terrain_at(from)) * delta)
	res["arrived"] = (res["position"] as Vector2).distance_to(to) < 0.001
	return res


## Moves along `path` (waypoints, world units) for `delta` seconds. Reached
## waypoints are removed. Returns {position, moved, path, arrived, blocked}.
func follow(map: MapData, from: Vector2, path: PackedVector2Array, speed: float, delta: float) -> Dictionary:
	var pos := from
	var moved := 0.0
	var blocked := false
	var remaining := path.duplicate()
	var budget := speed * map.terrain.movement(map.terrain_at(from)) * delta
	while budget > 0.0001 and not remaining.is_empty():
		var res := _advance(map, pos, remaining[0], budget)
		pos = res["position"]
		moved += res["moved"]
		budget -= res["moved"]
		if res["blocked"]:
			blocked = true
			break
		if pos.distance_to(remaining[0]) < 0.001:
			remaining.remove_at(0)
		else:
			break
	return {"position": pos, "moved": moved, "path": remaining, "arrived": remaining.is_empty(), "blocked": blocked}


## Straight movement towards `to` spending at most `budget` world units.
func _advance(map: MapData, from: Vector2, to: Vector2, budget: float) -> Dictionary:
	var pos := from
	var moved := 0.0
	var blocked := false
	# Sub-steps no longer than a quarter tile so thin water cannot be skipped.
	var max_sub := map.cell_size / 4.0
	while budget > 0.0001:
		var remaining := pos.distance_to(to)
		if remaining < 0.001:
			break
		var step_len := minf(minf(budget, max_sub), remaining)
		var next := pos.move_toward(to, step_len)
		if not map.is_passable(next):
			blocked = true
			break
		budget -= step_len
		moved += step_len
		pos = next
	return {"position": pos, "moved": moved, "blocked": blocked}
