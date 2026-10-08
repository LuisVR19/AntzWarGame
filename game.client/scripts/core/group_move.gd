class_name GroupMove
extends RefCounted
## Destinations for a MOVE order given to several divisions at once: instead
## of all of them heading to the same point, they line up in rows facing the
## direction of the march, centered on the clicked point. Front-most
## divisions take the front row, and within a row they keep their left/right
## order so their paths do not cross.

const MAX_PER_ROW := 5
const GAP := 14.0  # world units between neighbours


## `positions` and `radii` (world units) are aligned; returns one destination
## per division, in the same order.
static func slots(positions: Array, radii: Array, target: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var count := positions.size()
	if count == 0:
		return result
	result.resize(count)
	var centroid := Vector2.ZERO
	for p in positions:
		centroid += p
	centroid /= count
	var forward := (target - centroid).normalized()
	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT
	var lateral := Vector2(-forward.y, forward.x)

	var order: Array = range(count)
	order.sort_custom(func(a: int, b: int) -> bool: return positions[a].dot(forward) > positions[b].dot(forward))
	var row_start := 0
	var depth := 0.0  # distance of the current row behind the target
	while row_start < count:
		var row: Array = order.slice(row_start, mini(row_start + MAX_PER_ROW, count))
		row.sort_custom(func(a: int, b: int) -> bool: return positions[a].dot(lateral) < positions[b].dot(lateral))
		var width := 0.0
		var row_depth := 0.0
		for i in row:
			width += radii[i] * 2.0
			row_depth = maxf(row_depth, radii[i] * 2.0)
		width += GAP * (row.size() - 1)
		var cursor := -width * 0.5
		for i in row:
			cursor += radii[i]
			result[i] = target + lateral * cursor - forward * depth
			cursor += radii[i] + GAP
		depth += row_depth + GAP
		row_start += MAX_PER_ROW
	return result
