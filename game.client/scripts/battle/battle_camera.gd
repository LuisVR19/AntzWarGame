class_name BattleCamera
extends Camera2D
## Zoom (mouse wheel, centered on the cursor), pan (WASD / arrows / middle
## mouse drag) and clamping to the map bounds.

signal zoom_level_changed(zoom_level: float)

@export var pan_speed := 900.0
@export var min_zoom := 0.35
@export var max_zoom := 3.0
@export var zoom_step := 1.12

var _bounds := Rect2()
var _dragging := false


func set_bounds(bounds: Rect2) -> void:
	_bounds = bounds
	position = bounds.get_center()
	var view := get_viewport_rect().size
	var fit := minf(view.x / bounds.size.x, view.y / bounds.size.y) * 0.95
	_set_zoom_level(clampf(fit, min_zoom, max_zoom))
	_clamp_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(zoom_step, get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(1.0 / zoom_step, get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		position -= motion.relative / zoom.x
		_clamp_position()


func _process(delta: float) -> void:
	var dir := Input.get_vector(InputActions.CAM_LEFT, InputActions.CAM_RIGHT, InputActions.CAM_UP, InputActions.CAM_DOWN)
	if dir != Vector2.ZERO:
		position += dir * pan_speed * delta / zoom.x
		_clamp_position()


func _zoom_at(factor: float, anchor: Vector2) -> void:
	var old := zoom.x
	var target := clampf(old * factor, min_zoom, max_zoom)
	if is_equal_approx(target, old):
		return
	# Keep the world point under the cursor fixed while zooming.
	position = anchor + (position - anchor) * (old / target)
	_set_zoom_level(target)
	_clamp_position()


func _set_zoom_level(level: float) -> void:
	zoom = Vector2(level, level)
	zoom_level_changed.emit(level)


func _clamp_position() -> void:
	if not _bounds.has_area():
		return
	var half := get_viewport_rect().size / zoom.x * 0.5
	position.x = _clamp_axis(position.x, _bounds.position.x, _bounds.end.x, half.x)
	position.y = _clamp_axis(position.y, _bounds.position.y, _bounds.end.y, half.y)


## Centers the axis if the map is smaller than the view, else clamps.
static func _clamp_axis(value: float, low: float, high: float, half: float) -> float:
	if high - low <= half * 2.0:
		return (low + high) * 0.5
	return clampf(value, low + half, high - half)
