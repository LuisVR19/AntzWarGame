class_name MapView
extends Node2D
## The battlefield ground: the terrain TileMapLayer (Ground) and the flat
## marks painted over it (GroundMarks). Objects that stand on the ground
## (trees, buildings, units) live in the Y-sorted World node, not here.

var _map: MapData

@onready var ground: TileMapLayer = $Ground
@onready var marks: GroundMarks = $GroundMarks


func setup(map: MapData, projection: IsoProjection, config: VisualConfig) -> void:
	_map = map
	ground.tile_set = TerrainTileSet.build(config)
	ground.clear()
	for row in map.rows:
		for col in map.cols:
			var cell := Vector2i(col, row)
			var coords := TerrainTileSet.atlas_coords(ground.tile_set, map.type_at_cell(cell), cell)
			ground.set_cell(cell, TerrainTileSet.SOURCE_ID, coords)
	# Align the TileMapLayer's cell centers with IsoProjection's.
	ground.position = projection.cell_center(Vector2i.ZERO) - ground.map_to_local(Vector2i.ZERO)
	marks.setup(map, projection, config)
