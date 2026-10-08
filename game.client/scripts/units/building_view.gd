class_name BuildingView
extends Node2D
## View of one BuildingData. Its origin is the center of the footprint, which
## is the point used for depth sorting against units and decorations.
## The label/HP bar is shown only while selected, to keep the map readable.

var data: BuildingData
var _silhouette := PackedVector2Array()  # screen polygon used for clicks

@onready var selection_indicator: GroundMarker = $SelectionIndicator
@onready var visual: EntityVisual = $Visual
@onready var health_bar: EntityOverlay = $HealthBar


func setup(p_data: BuildingData, projection: IsoProjection, config: VisualConfig) -> void:
	data = p_data
	name = data.id
	position = projection.grid_to_screen(data.center_grid())
	var fp := projection.footprint(data.origin, data.size)
	for i in fp.size():
		fp[i] -= position
	var height := config.building_height_per_tile * maxi(data.size.x, data.size.y) * config.building_scale
	var color := Palette.side_color(data.side)

	visual.texture = VisualConfig.load_texture(data.asset)
	visual.texture_width = (fp[1].x - fp[3].x) * config.building_scale
	visual.texture_anchor = fp[2]
	if data.shape == "mound":
		visual.painter = func(c: CanvasItem) -> void: PlaceholderPainter.mound(c, fp, height * 0.7, color)
	else:
		visual.painter = func(c: CanvasItem) -> void: PlaceholderPainter.iso_box(c, fp, height, color)
	visual.queue_redraw()

	var up := Vector2(0, -height)
	_silhouette = PackedVector2Array([fp[3], fp[3] + up, fp[0] + up, fp[1] + up, fp[1], fp[2]])
	var ring := PackedVector2Array()
	for p in fp:
		ring.append(p * 1.15)
	selection_indicator.set_polygon(ring, Palette.SELECTION, false, config.selection_line_width)
	selection_indicator.visible = false

	health_bar.top = fp[0].y - height - 28.0
	health_bar.set_info(data.display_name, "", color.lightened(0.4), [[data.hp_ratio(), Palette.BAR_STRENGTH]])
	health_bar.visible = false


func entity_id() -> String:
	return data.id if data != null else ""


func set_selected(value: bool) -> void:
	selection_indicator.visible = value
	health_bar.visible = value


func set_label_scale(value: float) -> void:
	health_bar.scale = Vector2(value, value)


## Click score: 0 inside the building silhouette, INF outside.
func hit_test(screen_point: Vector2) -> float:
	return 0.5 if Geometry2D.is_point_in_polygon(screen_point - position, _silhouette) else INF
