class_name UnitTypes
extends RefCounted
## Ant types (data/definitions/unit_types.json): base stats, ranged attack
## and how their ants are drawn.

const WORKER := "WORKER"
const SOLDIER := "SOLDIER"
const ARCHER := "ARCHER"
const TANK := "TANK"
const SCOUT := "SCOUT"
const DEFAULT := WORKER


static func ids() -> Array:
	return Definitions.unit_types().keys()


static func exists(id: String) -> bool:
	return Definitions.unit_types().has(id)


static func get_def(id: String) -> Dictionary:
	var all := Definitions.unit_types()
	return all.get(id, all.get(DEFAULT, {}))


static func label(id: String) -> String:
	return str(get_def(id).get("name", id))


static func description(id: String) -> String:
	return str(get_def(id).get("description", ""))


static func is_ranged(id: String) -> bool:
	return get_def(id).has("ranged")


## Reach of the ranged attack in world units (0 = melee only).
static func attack_range(id: String) -> float:
	var ranged: Dictionary = get_def(id).get("ranged", {})
	return float(ranged.get("range", 0.0))


static func ranged_attack(id: String) -> float:
	var ranged: Dictionary = get_def(id).get("ranged", {})
	return float(ranged.get("attack", 0.0))


## {ant_size, head, mark} used by DivisionShape.
static func look(id: String) -> Dictionary:
	return get_def(id).get("look", {})
