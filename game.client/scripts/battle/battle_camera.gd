class_name BattleCamera
extends Camera2D
## RTS camera: pan with WASD/arrows, screen-edge scrolling, middle-mouse
## drag and right-mouse drag (BattleInput -> pan_screen); zoom with the wheel
## towards the cursor; clamped to the map bounds.
## Values come from VisualConfig (configure()).

signal zoom_level_changed(zoom_level: float)

var min_zoom := 0.45
var max_zoom := 3.0
var zoom_step := 1.12
var move_speed := 900.0
var edge_scroll_enabled := true
var edge_scroll_margin := 12.0

var _bounds := Rect2()
var _dragging := false
var _mouse_inside := false  # edge scrolling only while the mouse is in the window


func _ready() -> void:
	var window := get_window()
	window.mouse_exited.connect(func() -> void: _mouse_inside = false)
	window.focus_exited.connect(func() -> void: _mouse_inside = false)


func configure(config: VisualConfig) -> void:
	min_zoom = config.camera_min_zoom
	max_zoom = config.camera_max_zoom
	zoom_step = config.camera_zoom_step
	move_speed = config.camera_move_speed
	edge_scroll_enabled = config.camera_edge_scroll_enabled
	edge_scroll_margin = config.camera_edge_scroll_margin


## Bounds in screen (isometric) coordinates; centers and fits the map.
func set_bounds(bounds: Rect2) -> void:
	_bounds = bounds
	position = bounds.get_center()
	var view := get_viewport_rect().size
	var fit := minf(view.x / bounds.size.x, view.y / bounds.size.y) * 0.95
	_set_zoom_level(clampf(fit, min_zoom, max_zoom))
	_clamp_position()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_inside = true


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
		pan_screen((event as InputEventMouseMotion).relative)


## Drags the map by a mouse movement in screen pixels ("grab the map").
func pan_screen(screen_delta: Vector2) -> void:
	position -= screen_delta / zoom.x
	_clamp_position()


func _process(delta: float) -> void:
	var dir := Input.get_vector(InputActions.CAM_LEFT, InputActions.CAM_RIGHT, InputActions.CAM_UP, InputActions.CAM_DOWN)
	dir = (dir + _edge_direction()).limit_length(1.0)
	if dir != Vector2.ZERO:
		position += dir * move_speed * delta / zoom.x
		_clamp_position()


func _edge_direction() -> Vector2:
	if not edge_scroll_enabled or not _mouse_inside or _dragging:
		return Vector2.ZERO
	var mouse := get_viewport().get_mouse_position()
	var size := get_viewport_rect().size
	var dir := Vector2.ZERO
	if mouse.x <= edge_scroll_margin:
		dir.x = -1.0
	elif mouse.x >= size.x - edge_scroll_margin:
		dir.x = 1.0
	if mouse.y <= edge_scroll_margin:
		dir.y = -1.0
	elif mouse.y >= size.y - edge_scroll_margin:
		dir.y = 1.0
	return dir


func _zoom_at(factor: float, anchor: Vector2) -> void:
	var old := zoom.x
	var target := clampf(old * factor, min_zoom, max_zoom)
	if is_equal_approx(target, old):
		return
	# Keep the point under the cursor fixed while zooming.
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
