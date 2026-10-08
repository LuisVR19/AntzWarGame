class_name CommandData
extends RefCounted
## Client-side snapshot of a general or a commander (chain of command).
## It rides with its host division: its position is the division's.
## Pure data, as received from the server.

const ROLE_GENERAL := "GENERAL"
const ROLE_COMMANDER := "COMMANDER"

const STATUS_ACTIVE := "ACTIVE"
const STATUS_INCAPACITATED := "INCAPACITATED"
const STATUS_ELIMINATED := "ELIMINATED"

## How an order reaches a division right now (DivisionData.command_link).
const LINK_IN_RANGE := "IN_RANGE"
const LINK_OUT_OF_RANGE := "OUT_OF_RANGE"
const LINK_NO_COMMAND := "NO_COMMAND"

const STATUS_LABELS := {
	"ACTIVE": "Activo",
	"INCAPACITATED": "Incapacitado (su división se desbandó)",
	"ELIMINATED": "Eliminado",
}
const LINK_LABELS := {
	"IN_RANGE": "En rango: órdenes inmediatas",
	"OUT_OF_RANGE": "Fuera de rango: órdenes por mensajero",
	"NO_COMMAND": "Sin mando: conserva su última orden",
}

var id := ""
var player_id := ""
var role := ROLE_COMMANDER
var display_name := ""
var host_division_id := ""
var position := Vector2.ZERO
var status := STATUS_ACTIVE
var comm_radius := 0.0
var influence_radius := 0.0


static func from_protocol(raw: Dictionary) -> CommandData:
	var c := CommandData.new()
	c.id = str(raw.get("id", ""))
	c.player_id = str(raw.get("player_id", ""))
	c.role = GameTypes.from_wire(str(raw.get("role", "commander")))
	c.display_name = str(raw.get("name", c.id))
	c.host_division_id = str(raw.get("host_division_id", ""))
	c.position = Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)))
	c.status = GameTypes.from_wire(str(raw.get("status", "active")))
	c.comm_radius = float(raw.get("comm_radius", 0.0))
	c.influence_radius = float(raw.get("influence_radius", 0.0))
	return c


func is_general() -> bool:
	return role == ROLE_GENERAL


func is_active() -> bool:
	return status == STATUS_ACTIVE


func is_alive() -> bool:
	return status != STATUS_ELIMINATED


func role_label() -> String:
	return "General" if is_general() else "Comandante"


static func status_label(value: String) -> String:
	return str(STATUS_LABELS.get(value, value))


## "" (no chain of command) -> "-".
static func link_label(link: String) -> String:
	return str(LINK_LABELS.get(link, "-"))
