class_name Definitions
extends RefCounted
## Loads the JSON files in res://data/definitions. They are the single source
## of gameplay values on the client (terrain, maps, armies, unit types, local
## rules...). In network mode the server sends its own map/terrain, which
## take priority.

const TERRAIN_PATH := "res://data/definitions/terrain.json"
const RULES_PATH := "res://data/definitions/rules.json"
const MAPS_PATH := "res://data/definitions/maps.json"
const ARMIES_PATH := "res://data/definitions/armies.json"
const UNIT_TYPES_PATH := "res://data/definitions/unit_types.json"
const BUILDINGS_PATH := "res://data/definitions/buildings.json"
const RESOURCES_PATH := "res://data/definitions/resources.json"
const FORMATIONS_PATH := "res://data/definitions/formations.json"

static var _cache: Dictionary = {}


static func terrain() -> Dictionary:
	return _dict(TERRAIN_PATH)


static func rules() -> Dictionary:
	return _dict(RULES_PATH)


## Map catalog: id -> {name, description, file, objects}. The first is the default.
static func maps() -> Dictionary:
	return _dict(MAPS_PATH)


## Starting armies: id -> {name, description, divisions}. The first is the default.
static func armies() -> Dictionary:
	return _dict(ARMIES_PATH)


static func unit_types() -> Dictionary:
	return _dict(UNIT_TYPES_PATH)


static func buildings() -> Dictionary:
	return _dict(BUILDINGS_PATH)


static func resource_types() -> Dictionary:
	return _dict(RESOURCES_PATH)


static func formations() -> Dictionary:
	return _dict(FORMATIONS_PATH)


## Tiles and spawns of a map ("" = the default map).
static func map_def(id := "") -> Dictionary:
	return _dict(str(_entry(maps(), id).get("file", "")))


static func default_map() -> Dictionary:
	return map_def("")


## Buildings/resources layout designed for a cols x rows map, or {}.
static func map_objects_for(cols: int, rows: int) -> Dictionary:
	for entry in maps().values():
		var layout := _dict(str(entry.get("objects", "")))
		if int(layout.get("cols", -1)) == cols and int(layout.get("rows", -1)) == rows:
			return layout
	return {}


## Divisions of a starting army ("" = the default army).
static func army(id := "") -> Array:
	var divisions: Variant = _entry(armies(), id).get("divisions", [])
	return divisions if divisions is Array else []


## Catalog entry by id, or the first one when the id is empty or unknown.
static func _entry(catalog: Dictionary, id: String) -> Dictionary:
	if catalog.has(id):
		return catalog[id]
	return catalog.values()[0] if not catalog.is_empty() else {}


## Loads a JSON object and drops the "_comment" key.
static func _dict(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	var data: Variant = _load(path)
	if not data is Dictionary:
		return {}
	var result: Dictionary = data.duplicate()
	result.erase("_comment")
	return result


static func _load(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Definitions: cannot read %s" % path)
		return null
	var data: Variant = JSON.parse_string(text)
	if data == null:
		push_error("Definitions: invalid JSON in %s" % path)
		return null
	_cache[path] = data
	return data
