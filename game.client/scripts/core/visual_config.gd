class_name VisualConfig
extends Resource
## Central visual configuration (tile size, camera, scales, asset paths).
## The instance used by the game is res://resources/visual_config.tres and can
## be edited in the inspector. Colors live in Palette.

@export_group("Tiles")
@export var tile_width := 64.0
@export var tile_height := 32.0
@export var show_grid := true

@export_group("Camera")
@export var camera_min_zoom := 0.45
@export var camera_max_zoom := 3.0
@export var camera_zoom_step := 1.12
@export var camera_move_speed := 900.0
@export var camera_edge_scroll_enabled := true
@export var camera_edge_scroll_margin := 12.0
## Pixels the mouse must move with the right button held before it pans
## (shorter right clicks are orders).
@export var camera_drag_threshold := 6.0

@export_group("Scales")
## Size of the units/buildings/resources placeholders and sprites.
@export var unit_scale := 1.0
@export var unit_radius := 20.0
## A division's size grows with its soldiers:
## radius = unit_radius * (soldiers / unit_size_reference) ^ unit_size_exponent,
## clamped to [unit_radius_min, unit_radius_max]. 0.5 = drawn area proportional
## to the soldiers; higher values exaggerate the difference (default 0.75).
@export var unit_size_reference := 2000.0
@export var unit_size_exponent := 0.75
@export var unit_radius_min := 8.0
@export var unit_radius_max := 56.0
## Soldiers represented by each drawn ant.
@export var unit_soldiers_per_ant := 60.0
@export var building_scale := 1.0
## Height of a placeholder building per footprint tile (screen pixels).
@export var building_height_per_tile := 18.0
@export var resource_scale := 1.0
@export var decoration_scale := 1.0
## Labels/bars scale inversely to the zoom, clamped to this range.
@export var label_scale_min := 0.6
@export var label_scale_max := 2.5
@export var selection_line_width := 2.5

@export_group("Assets")
## Optional textures (SVG/PNG/WebP). If the file exists it replaces the
## placeholder shape; gameplay code never changes. Building and resource
## textures are set per type in data/definitions/*.json.
@export_file("*.svg", "*.png", "*.webp") var unit_texture := "res://assets/units/division.svg"
@export_file("*.svg", "*.png", "*.webp") var tree_texture := "res://assets/decorations/tree.svg"
@export_file("*.svg", "*.png", "*.webp") var rock_texture := "res://assets/decorations/rock.svg"
## Atlas with one row per terrain (PLAIN, FOREST, HILL, WATER) and one tile
## variant per column, each tile_width x tile_height.
@export_file("*.svg", "*.png", "*.webp") var terrain_atlas := "res://assets/terrain/terrain_atlas.png"


func projection(cell_size: float) -> IsoProjection:
	return IsoProjection.new(cell_size, tile_width, tile_height)


func label_scale_for_zoom(zoom_level: float) -> float:
	return clampf(1.0 / zoom_level, label_scale_min, label_scale_max)


## Loads an optional texture; returns null (=> use the placeholder) if absent.
static func load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
