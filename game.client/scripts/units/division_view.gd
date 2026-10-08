class_name DivisionView
extends Node2D
## Visual representation of one division. It only displays DivisionData.
## Positions come from the game source in WORLD units, are smoothed in world
## space and projected to the isometric screen with IsoProjection. The node
## origin is the division's ground point (its depth-sorting point).
## The order route and movement radius are drawn on the ground by GroundMarks.

const SMOOTHING := 12.0
const SNAP_DISTANCE := 250.0  # world units
## The "movement radius" shows how far the division gets in this many seconds.
const MOVE_RADIUS_SECONDS := 10.0

var data: DivisionData
var side := 0
var is_own := false
var selected := false
## Smoothed position in world units.
var world_position := Vector2.ZERO
## Current order route in world units (empty = none).
var route_world := PackedVector2Array()

var _target_position := Vector2.ZERO
var _initialized := false
var _projection: IsoProjection
var _config: VisualConfig
var _texture: Texture2D
var _radii := Vector2(20, 10)
var _size_key := -1  # radius (x10) the current size was computed for

@onready var shadow: GroundMarker = $Shadow
@onready var selection_indicator: GroundMarker = $SelectionIndicator
@onready var shape: DivisionShape = $Visual
@onready var overlay: EntityOverlay = $HealthBar


func setup(projection: IsoProjection, config: VisualConfig) -> void:
	_projection = projection
	_config = config
	_texture = VisualConfig.load_texture(config.unit_texture)
	_size_key = -1
	_update_size()
	_sync_position()


## Screen radius for a number of soldiers (see VisualConfig.unit_size_*).
static func size_radius(config: VisualConfig, soldiers: int) -> float:
	var growth := pow(maxf(soldiers, 1.0) / config.unit_size_reference, config.unit_size_exponent)
	return clampf(config.unit_radius * growth, config.unit_radius_min, config.unit_radius_max) * config.unit_scale


## Resizes body, shadow, selection ring and label. The size is the physical
## radius sent by the simulation (what collides) when available; otherwise
## (Go server) the visual formula of VisualConfig.
func _update_size() -> void:
	if _projection == null or _config == null:
		return
	var r_world := 0.0
	if data != null and data.radius > 0.0:
		r_world = data.radius * _config.unit_scale
	else:
		var soldiers := int(_config.unit_size_reference)
		if data != null and data.is_alive():
			soldiers = data.unit_count
		r_world = size_radius(_config, soldiers) * _projection.cell_size * 2.0 / (sqrt(2.0) * _projection.tile_width)
	var key := roundi(r_world * 10.0)
	if key == _size_key:
		return
	_size_key = key
	_radii = _projection.ground_radii(r_world)
	var basis := Transform2D(_projection.world_to_screen(Vector2(r_world, 0)), _projection.world_to_screen(Vector2(0, r_world)), Vector2.ZERO)
	shadow.set_ellipse(_radii * 1.15, Palette.SHADOW, true)
	shadow.position = Vector2(3, 2)
	selection_indicator.set_ellipse(_radii * 1.3 + Vector2(6, 3), Palette.SELECTION, false, _config.selection_line_width)
	shape.setup(_radii, basis, _texture, _radii.x * 2.4)
	overlay.top = -(_radii.y * 1.3 + 40.0)


func _ant_count() -> int:
	var per_ant := _config.unit_soldiers_per_ant if _config != null else 60.0
	return clampi(ceili(data.unit_count / per_ant), 3, 90)


func apply(p_data: DivisionData, p_side: int, own: bool) -> void:
	data = p_data
	side = p_side
	is_own = own
	_target_position = p_data.position
	if not _initialized or world_position.distance_to(p_data.position) > SNAP_DISTANCE:
		world_position = p_data.position
		_initialized = true
		_sync_position()
	z_index = 0 if p_data.is_alive() else -1
	_update_size()
	_refresh()


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	_refresh()


func set_label_scale(value: float) -> void:
	overlay.scale = Vector2(value, value)


func set_debug_lines(lines: PackedStringArray) -> void:
	overlay.set_debug_lines(lines)


func division_id() -> String:
	return data.id if data != null else ""


## Movement radius in world units (0 when it should not be shown).
func move_radius() -> float:
	if data == null or not data.is_alive() or not selected or not is_own:
		return 0.0
	return data.speed * MOVE_RADIUS_SECONDS


## Reach of a selected ranged division in world units (0 = none to show).
func attack_range() -> float:
	if data == null or not data.is_alive() or not selected:
		return 0.0
	return UnitTypes.attack_range(data.unit_type)


## Click score: normalized distance inside the body's ellipse, INF outside.
func hit_test(screen_point: Vector2) -> float:
	if data == null or not data.is_alive():
		return INF
	var d := ((screen_point - position) / (_radii * 1.4)).length()
	return d if d <= 1.0 else INF


func _refresh() -> void:
	if data == null:
		return
	var color := Palette.side_color(side)
	shape.configure(data, color, _ant_count())
	shadow.visible = data.is_alive()
	selection_indicator.visible = selected and data.is_alive()
	var title_color := color.lightened(0.4) if data.is_alive() else Palette.DESTROYED
	var bars: Array = []
	var units := ""
	if data.is_alive():
		units = "%s · %s" % [EntityOverlay.format_units(data.unit_count), UnitTypes.label(data.unit_type)]
		var strength_color := Palette.BAR_STRENGTH.lerp(Palette.BAR_STRENGTH_LOW, 1.0 - data.strength_ratio())
		bars = [[data.strength_ratio(), strength_color], [clampf(data.morale / 100.0, 0.0, 1.0), Palette.BAR_MORALE]]
	overlay.set_info(data.display_name, units, title_color, bars)


func _process(delta: float) -> void:
	if world_position.distance_squared_to(_target_position) > 0.01:
		world_position = world_position.lerp(_target_position, 1.0 - exp(-SMOOTHING * delta))
		_sync_position()


func _sync_position() -> void:
	if _projection != null:
		position = _projection.world_to_screen(world_position)
