class_name FormationLayout
extends RefCounted
## Shape of each formation in "ground units": x points forward (the facing),
## y to the side, and 1 = the division's radius. DivisionShape rotates these
## by the facing and projects them to the isometric screen.


## Outline polygon of the formation (for the ground marking).
static func outline(formation: String) -> PackedVector2Array:
	match formation:
		Formations.SHIELD_WALL:
			return _rect(0.28, 1.15)
		Formations.WEDGE:
			return PackedVector2Array([Vector2(1.0, 0), Vector2(-0.65, 0.95), Vector2(-0.65, -0.95)])
		Formations.SQUARE:
			return _rect(0.8, 0.8)
		Formations.COLUMN:
			return _rect(1.15, 0.32)
	return _rect(0.38, 1.0)


## Positions of `count` ants inside the formation.
static func points(formation: String, count: int) -> PackedVector2Array:
	match formation:
		Formations.SHIELD_WALL:
			return _grid(count, 0.22, 1.08)
		Formations.WEDGE:
			return _wedge(count)
		Formations.SQUARE:
			return _ring(count)
		Formations.COLUMN:
			return _grid(count, 1.08, 0.24)
	return _grid(count, 0.3, 0.92)


static func _rect(half_depth: float, half_width: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(half_depth, -half_width), Vector2(half_depth, half_width),
		Vector2(-half_depth, half_width), Vector2(-half_depth, -half_width),
	])


## Rows x columns filling a rectangle with the given half sizes.
static func _grid(count: int, half_depth: float, half_width: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if count <= 0:
		return out
	var cols := maxi(ceili(sqrt(count * half_width / half_depth)), 1)
	var rows := ceili(float(count) / cols)
	for i in count:
		var r := i / cols
		var c := i % cols
		var in_row := mini(cols, count - r * cols)
		var y := 0.0 if in_row == 1 else lerpf(-half_width, half_width, float(c) / (in_row - 1))
		var x := 0.0 if rows == 1 else lerpf(half_depth, -half_depth, float(r) / (rows - 1))
		out.append(Vector2(x, y))
	return out


## Triangle rows: 1 ant at the tip, then 2, 3...
static func _wedge(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rows := 1
	while rows * (rows + 1) / 2 < count:
		rows += 1
	var placed := 0
	for r in rows:
		var t := 0.0 if rows == 1 else float(r) / (rows - 1)
		var x := lerpf(0.85, -0.55, t)
		var half := 0.85 * t
		for k in r + 1:
			if placed >= count:
				return out
			var y := 0.0 if r == 0 else lerpf(-half, half, float(k) / r)
			out.append(Vector2(x, y))
			placed += 1
	return out


## Hollow square: ants on the perimeter (and an inner ring when crowded).
static func _ring(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var outer := mini(count, 28)
	_square_perimeter(out, outer, 0.68)
	if count > outer:
		_square_perimeter(out, count - outer, 0.4)
	return out


static func _square_perimeter(out: PackedVector2Array, count: int, half: float) -> void:
	for i in count:
		var t := 4.0 * i / count
		var side := int(t)
		var f := lerpf(-half, half, t - side)
		match side:
			0:
				out.append(Vector2(half, f))
			1:
				out.append(Vector2(-f, half))
			2:
				out.append(Vector2(-half, -f))
			_:
				out.append(Vector2(f, -half))
