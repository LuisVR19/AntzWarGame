class_name MovementSystem
extends RefCounted
## Straight-line movement used by the local simulation. It is isolated so it
## can be replaced by a navigation/pathfinding system later. (The Go server
## already uses A* and sends the resulting path to the client.)


## Moves from `from` towards `to` for `delta` seconds at `speed` units/s,
## applying the terrain movement modifier of the current position.
## Returns {position: Vector2, moved: float, arrived: bool, blocked: bool}.
func step(map: MapData, from: Vector2, to: Vector2, speed: float, delta: float) -> Dictionary:
	var pos := from
	var moved := 0.0
	var blocked := false
	var budget := speed * map.terrain.movement(map.terrain_at(from)) * delta
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
	return {
		"position": pos,
		"moved": moved,
		"arrived": pos.distance_to(to) < 0.001,
		"blocked": blocked,
	}
