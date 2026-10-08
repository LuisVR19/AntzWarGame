class_name DecorationLayer
extends Node2D
## Trees on forest tiles and rocks on hill tiles, depth-sorted together with
## units and buildings (World has Y-sort). Purely visual: the terrain
## modifiers come from the tile type.
## For performance the decorations of one isometric diagonal (cells with the
## same col + row, i.e. the same screen depth) share a single node, instead of
## one node per tree: big maps have hundreds of trees.

const TREES_PER_FOREST_TILE := 2
const ROCK_CHANCE := 0.45
const TREE_SIZE := 1.3


## All the decorations of one diagonal, drawn back to front.
class DecorationRow:
	extends Node2D
	var items: Array = []  # [{pos (layer space), sprite (PlaceholderSprites)}]

	func _draw() -> void:
		for item in items:
			PlaceholderSprites.draw(self, item["sprite"], item["pos"] - position)


var _items := 0


func setup(map: MapData, objects: MapObjects, projection: IsoProjection, config: VisualConfig) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_items = 0
	var rows := {}  # diagonal (col + row) -> Array of items
	var tree_texture := VisualConfig.load_texture(config.tree_texture)
	var rock_texture := VisualConfig.load_texture(config.rock_texture)
	var s := config.decoration_scale
	var tree_sprite := PlaceholderSprites.tree(s * TREE_SIZE)
	if tree_texture != null:
		tree_sprite = PlaceholderSprites.from_texture(tree_texture, projection.tile_width * 0.5 * s)
	for row in map.rows:
		for col in map.cols:
			var cell := Vector2i(col, row)
			if objects.is_occupied(cell):
				continue
			var type := map.type_at_cell(cell)
			if type == TerrainTable.FOREST:
				for i in TREES_PER_FOREST_TILE:
					var offset := Vector2(PlaceholderPainter.noise(cell, i * 2), PlaceholderPainter.noise(cell, i * 2 + 1)) * 0.6 + Vector2(0.2, 0.2)
					_add(rows, col + row, projection.grid_to_screen(Vector2(cell) + offset), tree_sprite)
			elif type == TerrainTable.HILL and PlaceholderPainter.noise(cell, 5) < ROCK_CHANCE:
				var rock_sprite := PlaceholderSprites.rock(s, col * 1000 + row)
				if rock_texture != null:
					rock_sprite = PlaceholderSprites.from_texture(rock_texture, projection.tile_width * 0.3 * s)
				_add(rows, col + row, projection.cell_center(cell), rock_sprite)
	for diagonal in rows.keys():
		var items: Array = rows[diagonal]
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["pos"].y < b["pos"].y)
		var node := DecorationRow.new()
		node.items = items
		# Sorting point: the middle of the diagonal band on screen.
		node.position = Vector2(0.0, (diagonal + 1) * projection.tile_height * 0.5)
		add_child(node)


## Number of trees and rocks (not nodes).
func item_count() -> int:
	return _items


func _add(rows: Dictionary, diagonal: int, pos: Vector2, sprite: Dictionary) -> void:
	if not rows.has(diagonal):
		rows[diagonal] = []
	rows[diagonal].append({"pos": pos, "sprite": sprite})
	_items += 1
