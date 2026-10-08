class_name Formations
extends RefCounted
## Formation definitions (data/definitions/formations.json) and the geometry
## of a blow: whether it lands on the front, a flank or the rear of a division.

const LINE := "LINE"
const SHIELD_WALL := "SHIELD_WALL"
const WEDGE := "WEDGE"
const SQUARE := "SQUARE"
const COLUMN := "COLUMN"
const DEFAULT := LINE

const FRONT := "front"
const FLANK := "flank"
const REAR := "rear"
const FRONT_ARC := PI / 3.0  # up to 60 degrees from the facing
const REAR_ARC := PI * 2.0 / 3.0  # from 120 degrees
const SIDE_LABELS := {FRONT: "frente", FLANK: "flanco", REAR: "retaguardia"}


static func ids() -> Array:
	return Definitions.formations().keys()


static func exists(id: String) -> bool:
	return Definitions.formations().has(id)


static func get_def(id: String) -> Dictionary:
	var all := Definitions.formations()
	return all.get(id, all.get(DEFAULT, {}))


static func stat(id: String, key: String, fallback := 1.0) -> float:
	return float(get_def(id).get(key, fallback))


static func label(id: String) -> String:
	return str(get_def(id).get("name", id))


static func short_label(id: String) -> String:
	return str(get_def(id).get("short", label(id)))


static func tooltip(id: String) -> String:
	return "%s\n%s\nAtaque x%.2f · Defensa frente x%.2f / flanco x%.2f / retaguardia x%.2f\nVelocidad x%.2f · Lucha con hasta %d soldados a la vez" % [
		label(id), str(get_def(id).get("description", "")),
		stat(id, "attack"), stat(id, "defense_front"), stat(id, "defense_flank"), stat(id, "defense_rear"),
		stat(id, "speed"), int(stat(id, "frontage", 0.0)),
	]


## Next formation in file order (for the cycle hotkey).
static func next(id: String) -> String:
	var all := ids()
	if all.is_empty():
		return id
	return all[(all.find(id) + 1) % all.size()]


## Side of a division facing `facing` (radians, world space) that is hit by a
## blow coming from `from_direction` (vector from the division to the enemy).
static func exposure(facing: float, from_direction: Vector2) -> String:
	if from_direction.length_squared() < 0.0001:
		return FRONT
	var diff := absf(angle_difference(facing, from_direction.angle()))
	if diff <= FRONT_ARC:
		return FRONT
	if diff >= REAR_ARC:
		return REAR
	return FLANK


static func defense_multiplier(id: String, side: String) -> float:
	return stat(id, "defense_" + side)


static func attack_multiplier(id: String, enemy_id: String) -> float:
	var bonus: Dictionary = get_def(id).get("bonus_vs", {})
	return stat(id, "attack") * float(bonus.get(enemy_id, 1.0))


static func side_label(side: String) -> String:
	return str(SIDE_LABELS.get(side, side))
