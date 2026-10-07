class_name DivisionView
extends Node2D
## Visual representation of one division. It only displays DivisionData:
## positions come from the game source and are smoothed between snapshots.
## Draws the selection radius and the current order route under the body.

const SMOOTHING := 12.0
const SNAP_DISTANCE := 250.0
const PICK_RADIUS := 34.0
## The "movement radius" shows how far the division gets in this many seconds.
const MOVE_RADIUS_SECONDS := 10.0

var data: DivisionData
var side := 0
var is_own := false
var selected := false

var _target_position := Vector2.ZERO
var _initialized := false
var _order_points: PackedVector2Array = PackedVector2Array()  # world space

@onready var shape: DivisionShape = $Shape
@onready var overlay: DivisionOverlay = $Overlay


func apply(p_data: DivisionData, p_side: int, own: bool) -> void:
	data = p_data
	side = p_side
	is_own = own
	_target_position = p_data.position
	if not _initialized or position.distance_to(p_data.position) > SNAP_DISTANCE:
		position = p_data.position
		_initialized = true
	z_index = 0 if p_data.is_alive() else -1
	_refresh()


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	_refresh()


## Route of the current order in world coordinates (empty = none).
func set_order_points(points: PackedVector2Array) -> void:
	_order_points = points
	queue_redraw()


func set_label_scale(value: float) -> void:
	overlay.scale = Vector2(value, value)


func set_debug_lines(lines: PackedStringArray) -> void:
	overlay.set_debug_lines(lines)


func division_id() -> String:
	return data.id if data != null else ""


func _refresh() -> void:
	if data == null:
		return
	shape.configure(data, Palette.side_color(side), selected)
	overlay.configure(data, Palette.side_color(side))
	queue_redraw()


func _process(delta: float) -> void:
	if position.distance_squared_to(_target_position) > 0.01:
		position = position.lerp(_target_position, 1.0 - exp(-SMOOTHING * delta))
		if not _order_points.is_empty() or selected:
			queue_redraw()


func _draw() -> void:
	if data == null or not data.is_alive():
		return
	if selected and is_own:
		draw_arc(Vector2.ZERO, data.speed * MOVE_RADIUS_SECONDS, 0.0, TAU, 72, Palette.MOVE_RADIUS, 1.5)
	if _order_points.is_empty() or not (is_own or selected):
		return
	var color := _order_color()
	var from := Vector2.ZERO
	for p in _order_points:
		var to := p - position
		draw_dashed_line(from, to, color, 2.0, 10.0)
		from = to
	draw_circle(from, 5.0, color)


func _order_color() -> Color:
	match data.order_type():
		"ATTACK":
			return Palette.ORDER_ATTACK_LINE
		"RETREAT":
			return Palette.ORDER_RETREAT_LINE
	return Palette.ORDER_MOVE_LINE
