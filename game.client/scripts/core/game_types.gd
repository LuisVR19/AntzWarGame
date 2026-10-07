class_name GameTypes
extends RefCounted
## Shared enumerations. Internally values are UPPERCASE (as in the design
## docs); on the wire (JSON) the Go server sends them in lowercase.

const STATE_IDLE := "IDLE"
const STATE_MOVING := "MOVING"
const STATE_ATTACKING := "ATTACKING"
const STATE_DEFENDING := "DEFENDING"
const STATE_RETREATING := "RETREATING"
const STATE_DESTROYED := "DESTROYED"

const STATUS_WAITING := "WAITING"
const STATUS_STARTING := "STARTING"
const STATUS_RUNNING := "RUNNING"
const STATUS_FINISHED := "FINISHED"

const STATE_LABELS := {
	"IDLE": "En espera",
	"MOVING": "En movimiento",
	"ATTACKING": "Atacando",
	"DEFENDING": "Defendiendo",
	"RETREATING": "En retirada",
	"DESTROYED": "Destruida",
}

const TERRAIN_LABELS := {
	"PLAIN": "Llanura",
	"FOREST": "Bosque",
	"HILL": "Colina",
	"WATER": "Agua",
}


static func from_wire(value: String) -> String:
	return value.to_upper()


static func to_wire(value: String) -> String:
	return value.to_lower()


static func state_label(state: String) -> String:
	return str(STATE_LABELS.get(state, state))


static func terrain_label(terrain: String) -> String:
	return str(TERRAIN_LABELS.get(terrain, terrain))
