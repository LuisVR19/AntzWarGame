class_name Definitions
extends RefCounted
## Loads the JSON files in res://data/definitions. They are the single source
## of gameplay values on the client (terrain, starting army, local rules, map).
## In network mode the server sends its own map/terrain, which take priority.

const TERRAIN_PATH := "res://data/definitions/terrain.json"
const ARMY_PATH := "res://data/definitions/army.json"
const RULES_PATH := "res://data/definitions/rules.json"
const MAP_PATH := "res://data/definitions/map_default.json"

static var _cache: Dictionary = {}


static func terrain() -> Dictionary:
	var data: Variant = _load(TERRAIN_PATH)
	return data if data is Dictionary else {}


static func army() -> Array:
	var data: Variant = _load(ARMY_PATH)
	return data if data is Array else []


static func rules() -> Dictionary:
	var data: Variant = _load(RULES_PATH)
	return data if data is Dictionary else {}


static func default_map() -> Dictionary:
	var data: Variant = _load(MAP_PATH)
	return data if data is Dictionary else {}


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
