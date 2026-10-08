class_name TerrainTileSet
extends RefCounted
## Builds the isometric TileSet used by the Ground TileMapLayer.
## If VisualConfig.terrain_atlas exists it is used as the atlas (one row per
## terrain in ROWS order, one tile variant per column). Otherwise placeholder
## diamond tiles are generated in memory, so no image files are needed yet.

const ROWS := [TerrainTable.PLAIN, TerrainTable.FOREST, TerrainTable.HILL, TerrainTable.WATER]
const PLACEHOLDER_VARIANTS := 3
const SOURCE_ID := 0


static func build(config: VisualConfig) -> TileSet:
	var size := Vector2i(roundi(config.tile_width), roundi(config.tile_height))
	var texture := VisualConfig.load_texture(config.terrain_atlas)
	if texture == null:
		texture = ImageTexture.create_from_image(_placeholder_atlas(size))
	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = size
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = size
	var grid := source.get_atlas_grid_size()
	for row in mini(grid.y, ROWS.size()):
		for col in grid.x:
			source.create_tile(Vector2i(col, row))
	tile_set.add_source(source, SOURCE_ID)
	return tile_set


## Atlas tile for a terrain type; the variant is picked per cell.
static func atlas_coords(tile_set: TileSet, type: String, cell: Vector2i) -> Vector2i:
	var source := tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	var columns := maxi(source.get_atlas_grid_size().x, 1)
	var col := mini(int(PlaceholderPainter.noise(cell, 41) * columns), columns - 1)
	return Vector2i(col, maxi(ROWS.find(type), 0))


static func _placeholder_atlas(size: Vector2i) -> Image:
	var img := Image.create(size.x * PLACEHOLDER_VARIANTS, size.y * ROWS.size(), false, Image.FORMAT_RGBA8)
	var half := Vector2(size) * 0.5
	for row in ROWS.size():
		var type: String = ROWS[row]
		for variant in PLACEHOLDER_VARIANTS:
			var origin := Vector2i(variant * size.x, row * size.y)
			for y in size.y:
				for x in size.x:
					var d := absf(x + 0.5 - half.x) / half.x + absf(y + 0.5 - half.y) / half.y
					if d <= 1.04:  # slightly larger than the diamond: no seams
						img.set_pixel(origin.x + x, origin.y + y, _texel(type, origin + Vector2i(x, y), d))
	return img


static func _texel(type: String, p: Vector2i, edge: float) -> Color:
	var n := PlaceholderPainter.noise(p, 13)
	var c := Palette.terrain_color(type)
	c = c.lightened((n - 0.5) * 0.08) if n > 0.5 else c.darkened((0.5 - n) * 0.08)
	match type:
		TerrainTable.PLAIN:
			if n > 0.95:
				c = c.lightened(0.18)
		TerrainTable.FOREST:
			if n > 0.85:
				c = Palette.TREE
		TerrainTable.HILL:
			if n > 0.88:
				c = Palette.ROCK_DARK
			elif n < 0.06:
				c = Palette.HILL_LIGHT
		TerrainTable.WATER:
			if sin(p.x * 0.35 + p.y * 1.1) > 0.93:
				c = Palette.WATER_WAVE
	if edge > 0.93:
		c = c.darkened(0.08)
	c.a = 1.0
	return c
