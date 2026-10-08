class_name PlaceholderPainter
extends RefCounted
## Primitive-shape placeholders for every map entity, drawn on the isometric
## canvas. All functions draw relative to the entity's ground point (0, 0).
## When real art exists, EntityVisual draws a texture instead of calling these.


## Pseudo-random but deterministic value in [0, 1) for a cell.
static func noise(cell: Vector2i, salt: int) -> float:
	return float(posmod(hash(Vector3i(cell.x, cell.y, salt)), 1000)) / 1000.0


## Draws `texture` with its bottom-center on `anchor`, scaled to `width`.
static func texture_on_ground(canvas: CanvasItem, texture: Texture2D, width: float, anchor: Vector2, tint := Color.WHITE) -> void:
	var size := texture.get_size() * (width / maxf(texture.get_size().x, 1.0))
	canvas.draw_texture_rect(texture, Rect2(anchor - Vector2(size.x * 0.5, size.y), size), false, tint)


## `segments`: use few (6-8) for tiny shapes such as ants; they are drawn by the thousand.
static func ellipse(canvas: CanvasItem, center: Vector2, radii: Vector2, color: Color, segments := 24) -> void:
	var points := IsoProjection.ellipse_points(center, radii, segments)
	points.remove_at(points.size() - 1)
	canvas.draw_colored_polygon(points, color)


static func ellipse_outline(canvas: CanvasItem, center: Vector2, radii: Vector2, color: Color, width := 1.5) -> void:
	canvas.draw_polyline(IsoProjection.ellipse_points(center, radii, 40), color, width, true)


static func rock(canvas: CanvasItem, s: float, seed_value: int) -> void:
	var points := PackedVector2Array()
	for i in 7:
		var a := PI + PI * i / 6.0
		var r := 1.0 - 0.25 * noise(Vector2i(seed_value, i), 3)
		points.append(Vector2(cos(a) * 7.0 * r, sin(a) * 6.0 * r) * s)
	points.append(Vector2(5.0, 1.5) * s)
	points.append(Vector2(-5.0, 1.5) * s)
	canvas.draw_colored_polygon(points, Palette.ROCK)
	canvas.draw_polyline(points, Palette.ROCK_DARK, 1.0)
	canvas.draw_circle(Vector2(-2.0, -3.5) * s, 1.6 * s, Palette.HILL_LIGHT)


## Box building over an isometric footprint (corners: top, right, bottom,
## left; relative to the entity origin). Light comes from the left.
static func iso_box(canvas: CanvasItem, fp: PackedVector2Array, height: float, accent: Color) -> void:
	var up := Vector2(0, -height)
	canvas.draw_colored_polygon(PackedVector2Array([fp[3], fp[2], fp[2] + up, fp[3] + up]), Palette.WALL_LIGHT)
	canvas.draw_colored_polygon(PackedVector2Array([fp[2], fp[1], fp[1] + up, fp[2] + up]), Palette.WALL_DARK)
	var roof := PackedVector2Array([fp[0] + up, fp[1] + up, fp[2] + up, fp[3] + up])
	canvas.draw_colored_polygon(roof, Palette.ROOF)
	# Owner stripe on the roof and a dark door on the light wall.
	var center := (fp[0] + fp[2]) * 0.5 + up
	var inner := PackedVector2Array()
	for p in roof:
		inner.append(center + (p - center) * 0.45)
	canvas.draw_colored_polygon(inner, accent)
	var door_base := fp[3].lerp(fp[2], 0.5)
	var door_h := minf(height * 0.6, 14.0)
	canvas.draw_colored_polygon(PackedVector2Array([
		door_base + Vector2(-4, -2), door_base + Vector2(4, 2), door_base + Vector2(4, 2 - door_h), door_base + Vector2(-4, -2 - door_h),
	]), Palette.NEST_HOLE)
	var outline := PackedVector2Array([fp[3], fp[3] + up, fp[0] + up, fp[1] + up, fp[1], fp[2], fp[3]])
	canvas.draw_polyline(outline, Palette.MAP_BORDER, 1.0)
	canvas.draw_line(fp[2], fp[2] + up, Palette.MAP_BORDER, 1.0)


## Anthill: an earth dome over the footprint with an entrance on top and a
## ring in the owner's color.
static func mound(canvas: CanvasItem, fp: PackedVector2Array, height: float, accent: Color) -> void:
	var center := (fp[0] + fp[2]) * 0.5
	var base := Vector2((fp[1].x - fp[3].x) * 0.42, (fp[2].y - fp[0].y) * 0.42)
	ellipse(canvas, center + Vector2(4, 3), base * 1.05, Palette.SHADOW)
	ellipse_outline(canvas, center, base * 1.08, accent, 3.0)
	var dome := PackedVector2Array()
	for i in 25:
		var a := PI * i / 24.0  # lower half: front edge on the ground
		dome.append(center + Vector2(cos(a) * base.x, sin(a) * base.y))
	for i in range(1, 24):
		var t := float(i) / 24.0
		var x := cos(PI * t) * base.x
		var y := -sin(PI * t) * (height + base.y * 0.3)
		dome.append(center + Vector2(-x, y))
	canvas.draw_colored_polygon(dome, Palette.NEST)
	ellipse(canvas, center + Vector2(-base.x * 0.2, -height * 0.55), base * Vector2(0.45, 0.35), Palette.NEST.lightened(0.15))
	ellipse(canvas, center + Vector2(0, -height * 0.8), base * Vector2(0.16, 0.12), Palette.NEST_HOLE)


static func resource_pile(canvas: CanvasItem, type: String, s: float) -> void:
	var color := Palette.resource_color(type)
	ellipse(canvas, Vector2.ZERO, Vector2(14, 7) * s, Palette.SHADOW)
	match type:
		ResourceNodeData.WOOD:
			for i in 3:
				var y := (-3.0 - i * 4.0) * s
				var x := (i - 1) * 2.0 * s
				canvas.draw_line(Vector2(x - 10 * s, y), Vector2(x + 8 * s, y - 3 * s), color, 4.0 * s)
				canvas.draw_circle(Vector2(x + 8 * s, y - 3 * s), 2.2 * s, color.lightened(0.35))
		ResourceNodeData.STONE:
			rock(canvas, s * 1.1, 11)
			canvas.draw_set_transform(Vector2(7, 1) * s)
			rock(canvas, s * 0.7, 23)
			canvas.draw_set_transform(Vector2.ZERO)
		ResourceNodeData.FOOD:
			for i in 9:
				var p := Vector2(noise(Vector2i(i, 1), 5) - 0.5, noise(Vector2i(i, 2), 5) - 0.5) * Vector2(18, 8) * s
				ellipse(canvas, p - Vector2(0, 2 * s), Vector2(2.6, 1.8) * s, color)
				canvas.draw_circle(p - Vector2(0.8, 2.8) * s, 0.8 * s, color.lightened(0.4))
		_:
			for i in 6:
				var p := Vector2(noise(Vector2i(i, 3), 9) - 0.5, noise(Vector2i(i, 4), 9) - 0.6) * Vector2(16, 10) * s
				canvas.draw_circle(p, 3.0 * s, color.darkened(0.15))
				canvas.draw_circle(p - Vector2(1, 1) * s, 1.4 * s, color.lightened(0.5))
