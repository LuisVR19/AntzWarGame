class_name BuildingData
extends RefCounted
## A building placed on the grid. Pure data: its view lives in
## scripts/units/building_view.gd. Position = footprint in cells.

var id := ""
var type := ""
var display_name := ""
var side := 0
var origin := Vector2i.ZERO  # top cell of the footprint
var size := Vector2i.ONE  # footprint in cells
var hp := 0
var max_hp := 0
var shape := "box"
var asset := ""


static func create(p_id: String, p_type: String, def: Dictionary, p_side: int, p_origin: Vector2i) -> BuildingData:
	var b := BuildingData.new()
	b.id = p_id
	b.type = p_type
	b.display_name = str(def.get("name", p_type))
	b.side = p_side
	b.origin = p_origin
	var size_raw: Variant = def.get("size", [1, 1])
	if size_raw is Array and size_raw.size() == 2:
		b.size = Vector2i(int(size_raw[0]), int(size_raw[1]))
	b.max_hp = int(def.get("max_hp", 100))
	b.hp = b.max_hp
	b.shape = str(def.get("shape", "box"))
	b.asset = str(def.get("asset", ""))
	return b


## Center of the footprint in grid coordinates (the depth-sorting point).
func center_grid() -> Vector2:
	return Vector2(origin) + Vector2(size) * 0.5


func occupies(cell: Vector2i) -> bool:
	return Rect2i(origin, size).has_point(cell)


func hp_ratio() -> float:
	return float(hp) / float(max_hp) if max_hp > 0 else 0.0
