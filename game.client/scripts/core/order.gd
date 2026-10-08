class_name Order
extends RefCounted
## An order is DATA: UI buttons create Orders, a GameStateSource sends them
## (to the local simulation or to the Go server). No logic lives in buttons.

const MOVE := "MOVE"
const ATTACK := "ATTACK"
const DEFEND := "DEFEND"
const RETREAT := "RETREAT"
const HOLD := "HOLD"
## Splits the division in two (an instant action, not a lasting order).
const SPLIT := "SPLIT"
## Walks to a friendly division and absorbs it on arrival.
const MERGE := "MERGE"
## Changes the formation (an instant action; the division then reorganizes).
const FORMATION := "FORMATION"
const ALL := [MOVE, ATTACK, DEFEND, RETREAT, HOLD, SPLIT, MERGE, FORMATION]

const LABELS := {
	MOVE: "movimiento",
	ATTACK: "ataque",
	DEFEND: "defensa",
	RETREAT: "retirada",
	HOLD: "mantener posición",
	SPLIT: "división",
	MERGE: "unión",
	FORMATION: "formación",
}

var id := ""  # assigned by the server / simulation on acceptance
var type := ""
var division_id := ""
var target_position := Vector2.ZERO
var has_target_position := false
var target_division_id := ""
var formation := ""  # FORMATION: target formation id
var automatic := false  # given by the division itself (helping a friend), not by the player
var split_ratio := 0.5  # SPLIT: share of the units that goes to the new division
var timestamp := 0.0  # unix seconds, client side


static func create(p_type: String, p_division_id: String) -> Order:
	var order := Order.new()
	order.type = p_type
	order.division_id = p_division_id
	order.timestamp = Time.get_unix_time_from_system()
	return order


static func move(p_division_id: String, target: Vector2) -> Order:
	var order := create(MOVE, p_division_id)
	order.target_position = target
	order.has_target_position = true
	return order


static func attack(p_division_id: String, target_id: String) -> Order:
	var order := create(ATTACK, p_division_id)
	order.target_division_id = target_id
	return order


static func defend(p_division_id: String) -> Order:
	return create(DEFEND, p_division_id)


static func hold(p_division_id: String) -> Order:
	return create(HOLD, p_division_id)


static func split(p_division_id: String, ratio := 0.5) -> Order:
	var order := create(SPLIT, p_division_id)
	order.split_ratio = ratio
	return order


static func change_formation(p_division_id: String, p_formation: String) -> Order:
	var order := create(FORMATION, p_division_id)
	order.formation = p_formation
	return order


static func merge(p_division_id: String, target_id: String) -> Order:
	var order := create(MERGE, p_division_id)
	order.target_division_id = target_id
	return order


## Without a target the division retreats to its base.
static func retreat(p_division_id: String) -> Order:
	return create(RETREAT, p_division_id)


static func label(order_type: String) -> String:
	return str(LABELS.get(order_type, order_type))


## Parses the "order" object of a division or of an order_accepted message.
static func from_protocol(raw: Dictionary) -> Order:
	var order := Order.new()
	order.id = str(raw.get("id", ""))
	order.type = str(raw.get("type", "")).to_upper()
	order.division_id = str(raw.get("division_id", ""))
	order.target_division_id = str(raw.get("target_division_id", ""))
	order.automatic = bool(raw.get("auto", false))
	var target: Variant = raw.get("target_position")
	if target is Dictionary:
		order.target_position = Protocol.vec_from(target)
		order.has_target_position = true
	return order


## Client -> server message for this order.
func to_message() -> Dictionary:
	var msg := {"division_id": division_id}
	match type:
		MOVE:
			msg["type"] = Protocol.MOVE_DIVISION
			msg["x"] = target_position.x
			msg["y"] = target_position.y
		ATTACK:
			msg["type"] = Protocol.ATTACK_DIVISION
			msg["target_division_id"] = target_division_id
		DEFEND:
			msg["type"] = Protocol.DEFEND_DIVISION
		RETREAT:
			msg["type"] = Protocol.RETREAT_DIVISION
			if has_target_position:
				msg["x"] = target_position.x
				msg["y"] = target_position.y
		HOLD:
			msg["type"] = Protocol.HOLD_DIVISION
		SPLIT:
			msg["type"] = Protocol.SPLIT_DIVISION
			msg["ratio"] = split_ratio
		MERGE:
			msg["type"] = Protocol.MERGE_DIVISION
			msg["target_division_id"] = target_division_id
		FORMATION:
			msg["type"] = Protocol.SET_FORMATION
			msg["formation"] = GameTypes.to_wire(formation)
		_:
			push_error("Order: unknown type %s" % type)
	return msg
