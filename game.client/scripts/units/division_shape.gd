class_name DivisionShape
extends Node2D
## Placeholder body of a division: a colony of small "ants" (dots) inside the
## division's area. The number of ants reflects remaining strength.
## Swap this node for a sprite/animated scene when assets exist.

const RADIUS := 24.0
const MAX_ANTS := 28
const ANT_SIZE := 2.6
const GOLDEN_ANGLE := 2.39996

var color := Color.WHITE
var selected := false
var state := GameTypes.STATE_IDLE
var in_battle := false
var routed := false
var _ants := 0
var _time := 0.0


func configure(data: DivisionData, side_color: Color, is_selected: bool) -> void:
	color = side_color
	selected = is_selected
	state = data.state
	in_battle = data.in_battle
	routed = data.routed
	_ants = 0
	if data.is_alive():
		_ants = clampi(ceili(MAX_ANTS * data.strength_ratio()), 1, MAX_ANTS)
	queue_redraw()


func _process(delta: float) -> void:
	if in_battle or state == GameTypes.STATE_MOVING or state == GameTypes.STATE_RETREATING:
		_time += delta
		queue_redraw()


func _draw() -> void:
	if state == GameTypes.STATE_DESTROYED:
		_draw_destroyed()
		return
	var body := color if not routed else color.darkened(0.4)
	draw_circle(Vector2.ZERO, RADIUS, Color(body, 0.18))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 40, Color(body, 0.6), 1.5)
	if selected:
		draw_arc(Vector2.ZERO, RADIUS + 5.0, 0.0, TAU, 48, Palette.SELECTION, 3.0)
	if in_battle:
		var pulse := sin(_time * 8.0) * 2.0
		draw_arc(Vector2.ZERO, RADIUS + 10.0 + pulse, 0.0, TAU, 48, Palette.BATTLE, 2.0)
	_draw_ants(body)
	_draw_state_mark(body)


func _draw_ants(body: Color) -> void:
	var jitter := 1.2 if state == GameTypes.STATE_MOVING or state == GameTypes.STATE_RETREATING else 0.0
	for i in _ants:
		var r := RADIUS * 0.85 * sqrt((i + 0.5) / MAX_ANTS)
		var a := i * GOLDEN_ANGLE
		var p := Vector2(cos(a), sin(a)) * r
		p += Vector2(sin(_time * 9.0 + i), cos(_time * 7.0 + i * 1.7)) * jitter
		draw_circle(p, ANT_SIZE, body.darkened(0.25))
		draw_circle(p + Vector2(ANT_SIZE * 0.9, 0), ANT_SIZE * 0.55, body.darkened(0.45))


## Small stance markers: shield square for DEFENDING, chevron for RETREATING.
func _draw_state_mark(body: Color) -> void:
	if state == GameTypes.STATE_DEFENDING:
		var s := RADIUS + 2.0
		draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), Color(body, 0.8), false, 2.0)
	elif state == GameTypes.STATE_RETREATING:
		var y := RADIUS + 6.0
		draw_polyline(PackedVector2Array([Vector2(-8, y), Vector2(0, y + 6), Vector2(8, y)]), Palette.ORDER_RETREAT_LINE, 2.0)


func _draw_destroyed() -> void:
	var s := RADIUS * 0.6
	draw_circle(Vector2.ZERO, RADIUS * 0.8, Color(Palette.DESTROYED, 0.25))
	draw_line(Vector2(-s, -s), Vector2(s, s), Palette.DESTROYED, 3.0)
	draw_line(Vector2(s, -s), Vector2(-s, s), Palette.DESTROYED, 3.0)
