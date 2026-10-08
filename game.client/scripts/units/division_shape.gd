class_name DivisionShape
extends EntityVisual
## Placeholder body of a division: its ants lying on the ground in the shape
## of its formation (FormationLayout), rotated to its facing and projected to
## the isometric screen. An arrow marks the front, which matters for flanking.
## If VisualConfig.unit_texture exists it is drawn instead of the ants.

var color := Color.WHITE
var state := GameTypes.STATE_IDLE
var in_battle := false
var routed := false
var reforming := false
var formation := Formations.DEFAULT
var unit_type := UnitTypes.DEFAULT
var _ant_size := 2.3
## Pre-rendered ants of this type (PlaceholderSprites.ants), tinted per side.
var _atlas: Dictionary = {}
var facing := 0.0  # radians, world space
var radii := Vector2(20, 10)
## Maps ground units (world axes, 1 = division radius) to screen pixels.
var basis := Transform2D()
var _ants := 0
var _time := 0.0
var _layout := PackedVector2Array()
var _layout_key := ""


func setup(p_radii: Vector2, p_basis: Transform2D, p_texture: Texture2D, p_texture_width: float) -> void:
	radii = p_radii
	basis = p_basis
	texture = p_texture
	texture_width = p_texture_width
	queue_redraw()


func configure(data: DivisionData, side_color: Color, ants: int) -> void:
	color = side_color
	state = data.state
	in_battle = data.in_battle
	routed = data.routed
	reforming = data.reforming
	formation = data.formation
	if unit_type != data.unit_type or _atlas.is_empty():
		unit_type = data.unit_type
		var look := UnitTypes.look(unit_type)
		_ant_size = float(look.get("ant_size", 2.3))
		_atlas = PlaceholderSprites.ants(look)
	facing = data.facing
	_ants = ants if data.is_alive() else 0
	queue_redraw()


func _process(delta: float) -> void:
	if in_battle or reforming or state == GameTypes.STATE_MOVING or state == GameTypes.STATE_RETREATING:
		_time += delta
		queue_redraw()


## Ground point (x forward, y to the side) -> screen offset from the origin.
func to_screen(p: Vector2) -> Vector2:
	var forward := Vector2.from_angle(facing)
	var side := Vector2(-forward.y, forward.x)
	return basis * (forward * p.x + side * p.y)


func _draw() -> void:
	if state == GameTypes.STATE_DESTROYED:
		_draw_destroyed()
		return
	var body := color if not routed else color.darkened(0.4)
	var outline := PackedVector2Array()
	for p in FormationLayout.outline(formation):
		outline.append(to_screen(p))
	draw_colored_polygon(outline, Color(body, 0.16))
	outline.append(outline[0])
	draw_polyline(outline, Color(body, 0.55), 1.5, true)
	if in_battle:
		var pulse := 1.0 + sin(_time * 8.0) * 0.06
		PlaceholderPainter.ellipse_outline(self, Vector2.ZERO, radii * 1.35 * pulse, Palette.BATTLE, 2.0)
	if texture != null:
		PlaceholderPainter.texture_on_ground(self, texture, texture_width, Vector2.ZERO, body)
	else:
		_draw_ants(body)
	if formation == Formations.SHIELD_WALL:
		draw_line(to_screen(Vector2(0.3, -1.15)), to_screen(Vector2(0.3, 1.15)), body.lightened(0.45), 3.0)
	_draw_front_arrow(body)
	if state == GameTypes.STATE_RETREATING:
		var y := radii.y + 8.0
		draw_polyline(PackedVector2Array([Vector2(-8, y), Vector2(0, y + 5), Vector2(8, y)]), Palette.ORDER_RETREAT_LINE, 2.0)


## Ants drawn back to front; while reforming they shuffle around.
## Ants drawn back to front from the type's atlas (one batched texture);
## while reforming they shuffle around.
func _draw_ants(body: Color) -> void:
	var key := "%s:%d" % [formation, _ants]
	if key != _layout_key:
		_layout = FormationLayout.points(formation, _ants)
		_layout_key = key
	var moving := state == GameTypes.STATE_MOVING or state == GameTypes.STATE_RETREATING
	var jitter := 2.5 if reforming else (1.0 if moving else 0.0)
	var points: Array[Vector2] = []
	for i in _layout.size():
		var p := to_screen(_layout[i])
		p += Vector2(sin(_time * 9.0 + i), cos(_time * 7.0 + i * 1.7) * 0.5) * jitter
		points.append(p)
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	var tint := body
	if reforming:
		tint.a = 0.65
	var cell: float = _atlas["cell"]
	var src := Rect2(PlaceholderSprites.ant_direction(to_screen(Vector2(1, 0))) * cell, 0.0, cell, cell)
	var size: Vector2 = _atlas["size"]
	var offset: Vector2 = -(_atlas["origin"] as Vector2) - Vector2(0, _ant_size * 0.5)
	for p in points:
		draw_texture_rect_region(_atlas["texture"], Rect2(p + offset, size), src, tint)
	if _atlas["marks"] != null:
		for p in points:
			draw_texture_rect_region(_atlas["marks"], Rect2(p + offset, size), src)


func _draw_front_arrow(body: Color) -> void:
	var tip := to_screen(Vector2(1.45, 0))
	var arrow := PackedVector2Array([to_screen(Vector2(1.15, -0.28)), tip, to_screen(Vector2(1.15, 0.28))])
	draw_polyline(arrow, body.lightened(0.5), 2.5, true)


func _draw_destroyed() -> void:
	var s := radii * 0.6
	PlaceholderPainter.ellipse(self, Vector2.ZERO, radii * 0.8, Color(Palette.DESTROYED, 0.25))
	draw_line(Vector2(-s.x, -s.y), Vector2(s.x, s.y), Palette.DESTROYED, 3.0)
	draw_line(Vector2(s.x, -s.y), Vector2(-s.x, s.y), Palette.DESTROYED, 3.0)
