class_name MapObjects
extends RefCounted
## Buildings and resources of a map, built from data/definitions. They are
## client-side only for now: the simulation and the server ignore them.

var buildings: Array[BuildingData] = []
var resources: Array[ResourceNodeData] = []


## A base building is centered on every spawn (works for any map, including
## the server's). Extra objects come from the layout of maps.json whose size
## matches the map.
static func for_map(map: MapData) -> MapObjects:
	var objects := MapObjects.new()
	var layout := Definitions.map_objects_for(map.cols, map.rows)
	var building_defs := Definitions.buildings()
	var base_type := str(layout.get("base_building", "anthill"))
	if building_defs.has(base_type):
		var base_def: Dictionary = building_defs[base_type]
		for side in map.spawns.size():
			var b := BuildingData.create("", base_type, base_def, side, Vector2i.ZERO)
			b.origin = map.cell_of(map.spawns[side]) - b.size / 2
			objects._add_building(b)
	if int(layout.get("cols", -1)) != map.cols or int(layout.get("rows", -1)) != map.rows:
		return objects
	for raw in layout.get("buildings", []):
		var type := str(raw.get("type", ""))
		if building_defs.has(type):
			objects._add_building(BuildingData.create("", type, building_defs[type], int(raw.get("side", 0)), _cell(raw)))
	var resource_defs := Definitions.resource_types()
	for raw in layout.get("resources", []):
		var type := str(raw.get("type", ""))
		if resource_defs.has(type):
			var r := ResourceNodeData.create("resource-%d" % (objects.resources.size() + 1), type, resource_defs[type],
				_cell(raw), int(raw.get("amount", 0)))
			objects.resources.append(r)
	return objects


func building(id: String) -> BuildingData:
	for b in buildings:
		if b.id == id:
			return b
	return null


func resource(id: String) -> ResourceNodeData:
	for r in resources:
		if r.id == id:
			return r
	return null


## True if a building or resource sits on the cell (keeps decorations off).
func is_occupied(cell: Vector2i) -> bool:
	for b in buildings:
		if b.occupies(cell):
			return true
	for r in resources:
		if r.cell == cell:
			return true
	return false


func _add_building(b: BuildingData) -> void:
	b.id = "building-%d" % (buildings.size() + 1)
	buildings.append(b)


static func _cell(raw: Dictionary) -> Vector2i:
	var c: Variant = raw.get("cell", {})
	if c is Dictionary:
		return Vector2i(int(c.get("x", 0)), int(c.get("y", 0)))
	return Vector2i.ZERO
