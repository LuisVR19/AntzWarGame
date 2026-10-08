class_name ResourceView
extends Node2D
## View of one ResourceNodeData, centered on its cell. The label is shown
## only while the resource is selected, to keep the map readable.

var data: ResourceNodeData
var _hit_radii := Vector2(20, 14)

@onready var selection_indicator: GroundMarker = $SelectionIndicator
@onready var visual: EntityVisual = $Visual
@onready var health_bar: EntityOverlay = $HealthBar


func setup(p_data: ResourceNodeData, projection: IsoProjection, config: VisualConfig) -> void:
	data = p_data
	name = data.id
	position = projection.grid_to_screen(data.center_grid())
	var s := config.resource_scale
	visual.texture = VisualConfig.load_texture(data.asset)
	visual.texture_width = projection.tile_width * 0.7 * s
	var type := data.type
	visual.painter = func(c: CanvasItem) -> void: PlaceholderPainter.resource_pile(c, type, s)
	visual.queue_redraw()
	_hit_radii = Vector2(projection.tile_width * 0.32, projection.tile_height * 0.6) * s
	selection_indicator.set_ellipse(Vector2(projection.tile_width, projection.tile_height) * 0.36 * s,
		Palette.SELECTION, false, config.selection_line_width)
	selection_indicator.visible = false
	health_bar.top = -38.0 * s
	health_bar.set_info(data.display_name, "%d" % data.amount, Palette.resource_color(type),
		[[data.amount_ratio(), Palette.resource_color(type)]])
	health_bar.visible = false


func entity_id() -> String:
	return data.id if data != null else ""


func set_selected(value: bool) -> void:
	selection_indicator.visible = value
	health_bar.visible = value


func set_label_scale(value: float) -> void:
	health_bar.scale = Vector2(value, value)


## Click score: normalized distance inside the pile's ellipse, INF outside.
func hit_test(screen_point: Vector2) -> float:
	var d := ((screen_point - position - Vector2(0, -4)) / _hit_radii).length()
	return d if d <= 1.0 else INF
