class_name MapData
extends RefCounted
## Battlefield description: a grid of terrain tiles plus the bases (spawns).
## World coordinates go from (0, 0) to size(); tile (col, row) covers
## [col * cell_size, (col + 1) * cell_size).

const CODE_TO_TYPE := {
	"P": TerrainTable.PLAIN,
	"F": TerrainTable.FOREST,
	"H": TerrainTable.HILL,
	"W": TerrainTable.WATER,
}

var cell_size := 50.0
var cols := 0
var rows := 0
var tiles: PackedStringArray = PackedStringArray()
var spawns: Array[Vector2] = []
var terrain: TerrainTable = TerrainTable.new()


static func from_definitions() -> MapData:
	var raw := Definitions.default_map()
	var map := _from_raw(raw)
	map.terrain = TerrainTable.from_dict(Definitions.terrain())
	return map


## Builds a map from the server's "map" object (game_created / game_joined).
static func from_protocol(raw: Dictionary) -> MapData:
	var map := _from_raw(raw)
	var terrain_raw: Variant = raw.get("terrain")
	if terrain_raw is Dictionary and not terrain_raw.is_empty():
		map.terrain = TerrainTable.from_dict(terrain_raw)
	else:
		map.terrain = TerrainTable.from_dict(Definitions.terrain())
	return map


static func _from_raw(raw: Dictionary) -> MapData:
	var map := MapData.new()
	map.cell_size = float(raw.get("cell_size", 50.0))
	var tiles_raw: Variant = raw.get("tiles", [])
	if tiles_raw is Array:
		for row in tiles_raw:
			map.tiles.append(str(row))
	map.rows = map.tiles.size()
	map.cols = map.tiles[0].length() if map.rows > 0 else 0
	var spawns_raw: Variant = raw.get("spawns", [])
	if spawns_raw is Array:
		for s in spawns_raw:
			map.spawns.append(Protocol.vec_from(s))
	return map


func size() -> Vector2:
	return Vector2(cols * cell_size, rows * cell_size)


func bounds() -> Rect2:
	return Rect2(Vector2.ZERO, size())


func in_bounds(p: Vector2) -> bool:
	var s := size()
	return p.x >= 0.0 and p.y >= 0.0 and p.x < s.x and p.y < s.y


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / cell_size), floori(p.y / cell_size))


func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * cell_size, Vector2(cell_size, cell_size))


func type_at_cell(cell: Vector2i) -> String:
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows:
		return TerrainTable.WATER
	var code := tiles[cell.y].substr(cell.x, 1)
	return str(CODE_TO_TYPE.get(code, TerrainTable.PLAIN))


func terrain_at(p: Vector2) -> String:
	if not in_bounds(p):
		return TerrainTable.WATER
	return type_at_cell(cell_of(p))


func is_passable(p: Vector2) -> bool:
	return in_bounds(p) and terrain.is_passable(terrain_at(p))


func to_protocol() -> Dictionary:
	var spawn_list := []
	for s in spawns:
		spawn_list.append({"x": s.x, "y": s.y})
	return {
		"width": size().x,
		"height": size().y,
		"cell_size": cell_size,
		"cols": cols,
		"rows": rows,
		"tiles": Array(tiles),
		"spawns": spawn_list,
		"terrain": terrain.to_protocol(),
	}
