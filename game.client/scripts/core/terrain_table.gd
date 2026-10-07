class_name TerrainTable
extends RefCounted
## Terrain modifiers by type (PLAIN, FOREST, HILL, WATER).

const PLAIN := "PLAIN"
const FOREST := "FOREST"
const HILL := "HILL"
const WATER := "WATER"
const TYPES := [PLAIN, FOREST, HILL, WATER]

const MOVEMENT := "movement_modifier"
const ATTACK := "attack_modifier"
const DEFENSE := "defense_modifier"
const VISIBILITY := "visibility_modifier"

var _mods: Dictionary = {}


## Accepts {"PLAIN": {...}} or the server's {"plain": {...}}.
static func from_dict(data: Dictionary) -> TerrainTable:
	var table := TerrainTable.new()
	for key in data.keys():
		var type := str(key).to_upper()
		var raw: Variant = data[key]
		if not TYPES.has(type) or not raw is Dictionary:
			continue
		table._mods[type] = {
			MOVEMENT: float(raw.get(MOVEMENT, 1.0)),
			ATTACK: float(raw.get(ATTACK, 1.0)),
			DEFENSE: float(raw.get(DEFENSE, 1.0)),
			VISIBILITY: float(raw.get(VISIBILITY, 1.0)),
		}
	return table


func modifier(type: String, key: String) -> float:
	var mods: Dictionary = _mods.get(type, {})
	return float(mods.get(key, 1.0))


func movement(type: String) -> float:
	return modifier(type, MOVEMENT)


func attack(type: String) -> float:
	return modifier(type, ATTACK)


func defense(type: String) -> float:
	return modifier(type, DEFENSE)


func visibility(type: String) -> float:
	return modifier(type, VISIBILITY)


func is_passable(type: String) -> bool:
	return movement(type) > 0.0


func to_protocol() -> Dictionary:
	var out := {}
	for type in _mods.keys():
		out[str(type).to_lower()] = _mods[type].duplicate()
	return out
