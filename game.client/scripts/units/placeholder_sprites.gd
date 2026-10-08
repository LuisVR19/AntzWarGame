class_name PlaceholderSprites
extends RefCounted
## Placeholder shapes rasterized ONCE into textures (cached). Drawing a
## texture is one batched draw call, while drawing the same shape with
## primitives costs several calls per tree or ant: on big maps with hundreds
## of trees and thousands of ants that is what limits the frame rate.
## A sprite is {texture, origin, size}: `origin` is the anchor (the ground
## point of the shape) inside the drawn rect, both in screen pixels.

const SUPERSAMPLE := 3.0  # texture pixels per screen pixel (crisp when zooming in)
const ANT_DIRECTIONS := 8
const ROCK_VARIANTS := 4

static var _cache: Dictionary = {}


## Sprite for a real asset: bottom-center anchored, scaled to `width`.
static func from_texture(texture: Texture2D, width: float) -> Dictionary:
	var size := texture.get_size() * (width / maxf(texture.get_size().x, 1.0))
	return {"texture": texture, "origin": Vector2(size.x * 0.5, size.y), "size": size}


static func draw(canvas: CanvasItem, sprite: Dictionary, at: Vector2, tint := Color.WHITE) -> void:
	canvas.draw_texture_rect(sprite["texture"], Rect2(at - sprite["origin"], sprite["size"]), false, tint)


static func tree(s: float) -> Dictionary:
	var key := "tree:%.2f" % s
	if not _cache.has(key):
		var bounds := Rect2(-9.5, -24.5, 19, 29)
		var img := _canvas(bounds, s)
		_ellipse(img, Vector2(0, 0), Vector2(9, 4.5), Palette.SHADOW)
		_rect(img, Rect2(-1.5, -9, 3, 9), Palette.TRUNK)
		_ellipse(img, Vector2(0, -15), Vector2(8, 8), Palette.TREE)
		_ellipse(img, Vector2(-3, -19), Vector2(5.5, 5.5), Palette.TREE_LIGHT)
		_ellipse(img, Vector2(3, -13), Vector2(4, 4), Palette.TREE.darkened(0.15))
		_cache[key] = _finish(img, bounds, s)
	return _cache[key]


static func rock(s: float, seed_value: int) -> Dictionary:
	var variant := posmod(seed_value, ROCK_VARIANTS)
	var key := "rock:%.2f:%d" % [s, variant]
	if not _cache.has(key):
		var bounds := Rect2(-8, -8, 16, 11)
		var img := _canvas(bounds, s)
		var points := PackedVector2Array()
		for i in 7:
			var a := PI + PI * i / 6.0
			var r := 1.0 - 0.25 * PlaceholderPainter.noise(Vector2i(variant, i), 3)
			points.append(Vector2(cos(a) * 7.0 * r, sin(a) * 6.0 * r))
		points.append(Vector2(5.0, 1.5))
		points.append(Vector2(-5.0, 1.5))
		_polygon(img, points, Palette.ROCK)
		_ellipse(img, Vector2(-2.0, -3.5), Vector2(1.6, 1.6), Palette.HILL_LIGHT)
		_cache[key] = _finish(img, bounds, s)
	return _cache[key]


## Atlas of one ant type in ANT_DIRECTIONS directions (screen angles), drawn
## in grays so it can be tinted with the side color. `marks` = the untinted
## extras (the archers' acid). Returns {texture, marks, origin, size, cell}.
static func ants(look: Dictionary) -> Dictionary:
	var s := float(look.get("ant_size", 2.3))
	var head := float(look.get("head", 0.55))
	var mark := str(look.get("mark", ""))
	var key := "ants:%.2f:%.2f:%s" % [s, head, mark]
	if _cache.has(key):
		return _cache[key]
	var half := ceilf(s * (1.0 + head) + s * 1.3) + 1.0
	var cell := Rect2(-half, -half, half * 2.0, half * 2.0)
	var cell_px := int(ceilf(cell.size.x * SUPERSAMPLE))
	var base := Image.create(cell_px * ANT_DIRECTIONS, cell_px, false, Image.FORMAT_RGBA8)
	var marks := Image.create(cell_px * ANT_DIRECTIONS, cell_px, false, Image.FORMAT_RGBA8)
	var body := Vector2(s * 1.25, s * 0.6) if mark == "stripe" else Vector2(s, s * 0.75)
	for i in ANT_DIRECTIONS:
		var dir := Vector2.from_angle(TAU * i / ANT_DIRECTIONS)
		var c := -cell.position + Vector2(i * cell_px, 0) / SUPERSAMPLE  # cell center, unscaled units
		_ellipse_at(base, c, body, Color(0.75, 0.75, 0.75))
		if mark == "armor":
			_ring_at(base, c, body, Color(1, 1, 1))
		elif mark == "stripe":
			_rect_at(base, Rect2(c + Vector2(-0.5, -body.y), Vector2(1.0, body.y * 2.0)), Color(1, 1, 1))
		elif mark == "acid":
			_ellipse_at(marks, c - dir * s * 0.8, Vector2(s, s) * 0.45, Palette.ACID)
		_ellipse_at(base, c + dir * s, Vector2(s, s) * head, Color(0.55, 0.55, 0.55))
	var result := {
		"texture": ImageTexture.create_from_image(base),
		"marks": ImageTexture.create_from_image(marks) if mark == "acid" else null,
		"origin": -cell.position, "size": cell.size, "cell": float(cell_px),
	}
	_cache[key] = result
	return result


## Atlas column for a screen direction.
static func ant_direction(screen_dir: Vector2) -> int:
	return posmod(roundi(screen_dir.angle() / (TAU / ANT_DIRECTIONS)), ANT_DIRECTIONS)


# --- Tiny rasterizer (anti-aliased edges, src-over blending) -----------------

static func _canvas(bounds: Rect2, s: float) -> Image:
	var px := (bounds.size * s * SUPERSAMPLE).ceil()
	var img := Image.create(maxi(int(px.x), 1), maxi(int(px.y), 1), false, Image.FORMAT_RGBA8)
	img.set_meta("origin", -bounds.position)
	img.set_meta("scale", s * SUPERSAMPLE)
	return img


static func _finish(img: Image, bounds: Rect2, s: float) -> Dictionary:
	return {"texture": ImageTexture.create_from_image(img), "origin": -bounds.position * s, "size": bounds.size * s}


## Shape coordinates (screen pixels at scale 1, origin = anchor) -> image pixels.
static func _to_img(img: Image, p: Vector2) -> Vector2:
	return (p + img.get_meta("origin")) * float(img.get_meta("scale"))


static func _ellipse(img: Image, center: Vector2, radii: Vector2, color: Color) -> void:
	var k := float(img.get_meta("scale"))
	_fill_ellipse(img, _to_img(img, center), radii * k, color)


static func _rect(img: Image, rect: Rect2, color: Color) -> void:
	var k := float(img.get_meta("scale"))
	_fill_rect(img, Rect2(_to_img(img, rect.position), rect.size * k), color)


static func _polygon(img: Image, points: PackedVector2Array, color: Color) -> void:
	var mapped := PackedVector2Array()
	for p in points:
		mapped.append(_to_img(img, p))
	var box := Rect2(mapped[0], Vector2.ZERO)
	for p in mapped:
		box = box.expand(p)
	for y in range(maxi(int(box.position.y), 0), mini(int(box.end.y) + 1, img.get_height())):
		for x in range(maxi(int(box.position.x), 0), mini(int(box.end.x) + 1, img.get_width())):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), mapped):
				_blend(img, x, y, color, 1.0)


## Same as _ellipse/_rect but in unscaled atlas units (for the ant cells).
static func _ellipse_at(img: Image, center: Vector2, radii: Vector2, color: Color) -> void:
	_fill_ellipse(img, center * SUPERSAMPLE, radii * SUPERSAMPLE, color)


static func _ring_at(img: Image, center: Vector2, radii: Vector2, color: Color) -> void:
	var c := center * SUPERSAMPLE
	var r := radii * SUPERSAMPLE
	for y in range(maxi(int(c.y - r.y - 2), 0), mini(int(c.y + r.y + 2), img.get_height())):
		for x in range(maxi(int(c.x - r.x - 2), 0), mini(int(c.x + r.x + 2), img.get_width())):
			var d := ((Vector2(x + 0.5, y + 0.5) - c) / r).length()
			var edge := absf(d - 1.0) * minf(r.x, r.y)
			if edge < 1.5:
				_blend(img, x, y, color, clampf(1.5 - edge, 0.0, 1.0))


static func _rect_at(img: Image, rect: Rect2, color: Color) -> void:
	_fill_rect(img, Rect2(rect.position * SUPERSAMPLE, rect.size * SUPERSAMPLE), color)


static func _fill_ellipse(img: Image, c: Vector2, r: Vector2, color: Color) -> void:
	for y in range(maxi(int(c.y - r.y - 1), 0), mini(int(c.y + r.y + 2), img.get_height())):
		for x in range(maxi(int(c.x - r.x - 1), 0), mini(int(c.x + r.x + 2), img.get_width())):
			var d := ((Vector2(x + 0.5, y + 0.5) - c) / r).length()
			# about one pixel of anti-aliased edge
			var coverage := clampf((1.0 - d) * minf(r.x, r.y) + 0.5, 0.0, 1.0)
			if coverage > 0.0:
				_blend(img, x, y, color, coverage)


static func _fill_rect(img: Image, rect: Rect2, color: Color) -> void:
	for y in range(maxi(int(rect.position.y), 0), mini(int(ceilf(rect.end.y)), img.get_height())):
		for x in range(maxi(int(rect.position.x), 0), mini(int(ceilf(rect.end.x)), img.get_width())):
			_blend(img, x, y, color, 1.0)


static func _blend(img: Image, x: int, y: int, color: Color, coverage: float) -> void:
	var a := color.a * coverage
	var dst := img.get_pixel(x, y)
	var out_a := a + dst.a * (1.0 - a)
	if out_a <= 0.0:
		return
	var rgb := (Vector3(color.r, color.g, color.b) * a + Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - a)) / out_a
	img.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, out_a))
