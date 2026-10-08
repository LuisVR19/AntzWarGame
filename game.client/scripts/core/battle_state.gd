class_name BattleState
extends RefCounted
## Latest known state of the match, rebuilt from protocol messages.
## Read by the battle scene and the UI; written only by GameStateSource.

var game_id := ""
var status := GameTypes.STATUS_WAITING
var tick := 0
var tick_rate := 10
var countdown_ticks := 0
var divisions: Dictionary = {}  # id -> DivisionData
var division_ids: Array[String] = []  # stable order
## Each battle: {id, attacker_id, defender_id, position: Vector2, rounds}
var battles: Array[Dictionary] = []
## Each player: {id, name, side, ready, connected, bot}
var players: Array[Dictionary] = []
## Chain of command (Go server): generals and commanders by id.
var commanders: Dictionary = {}  # id -> CommandData
var commander_ids: Array[String] = []  # stable order
## Own messengers in transit: {id, division_id, sender_id, position: Vector2, eta_ticks, order: Order}
var messengers: Array[Dictionary] = []
var winner_id := ""
var finish_reason := ""


func apply_snapshot(msg: Dictionary) -> void:
	tick = int(msg.get("tick", tick))
	status = GameTypes.from_wire(str(msg.get("status", GameTypes.to_wire(status))))
	countdown_ticks = int(msg.get("countdown_ticks", 0))
	var seen := {}
	var divisions_raw: Variant = msg.get("divisions", [])
	if divisions_raw is Array:
		for raw in divisions_raw:
			var d := DivisionData.from_protocol(raw)
			upsert_division(d)
			seen[d.id] = true
	for id in division_ids.duplicate():
		if not seen.has(id):
			divisions.erase(id)
			division_ids.erase(id)
	_apply_command(msg)
	battles.clear()
	var battles_raw: Variant = msg.get("battles", [])
	if battles_raw is Array:
		for raw in battles_raw:
			battles.append({
				"id": str(raw.get("id", "")),
				"attacker_id": str(raw.get("attacker_id", "")),
				"defender_id": str(raw.get("defender_id", "")),
				"position": Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0))),
				"rounds": int(raw.get("rounds", 0)),
			})


func _apply_command(msg: Dictionary) -> void:
	commanders.clear()
	commander_ids.clear()
	var commanders_raw: Variant = msg.get("commanders", [])
	if commanders_raw is Array:
		for raw in commanders_raw:
			var c := CommandData.from_protocol(raw)
			commanders[c.id] = c
			commander_ids.append(c.id)
	messengers.clear()
	var messengers_raw: Variant = msg.get("messengers", [])
	if messengers_raw is Array:
		for raw in messengers_raw:
			var order_raw: Variant = raw.get("order", {})
			messengers.append({
				"id": str(raw.get("id", "")),
				"division_id": str(raw.get("division_id", "")),
				"sender_id": str(raw.get("sender_id", "")),
				"position": Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0))),
				"eta_ticks": int(raw.get("eta_ticks", 0)),
				"order": Order.from_protocol(order_raw if order_raw is Dictionary else {}),
			})


func has_chain_of_command() -> bool:
	return not commanders.is_empty()


func get_command(id: String) -> CommandData:
	return commanders.get(id) as CommandData


func all_commands() -> Array[CommandData]:
	var out: Array[CommandData] = []
	for id in commander_ids:
		out.append(commanders[id])
	return out


## Alive divisions that report to a command unit (known for own divisions).
## A general also leads the divisions without commander and those whose
## commander is not active (the server sends their orders through it).
func subordinates(command_id: String) -> Array[DivisionData]:
	var out: Array[DivisionData] = []
	var command := get_command(command_id)
	for d in all_divisions():
		if not d.is_alive():
			continue
		if d.commander_id == command_id:
			out.append(d)
		elif command != null and command.is_general() and d.player_id == command.player_id and _reports_to_general(d):
			out.append(d)
	return out


func _reports_to_general(d: DivisionData) -> bool:
	if d.commander_id.is_empty():
		return true
	var own := get_command(d.commander_id)
	return own != null and not own.is_active() and not own.is_general()


func command_name(id: String) -> String:
	var c := get_command(id)
	return c.display_name if c != null else id


## Applies a command_updated event until the next snapshot arrives.
func set_command_status(id: String, status: String, role: String) -> void:
	var c := get_command(id)
	if c != null:
		c.status = status
		c.role = role


## Seconds for a number of ticks at the server tick rate.
func ticks_to_seconds(ticks: int) -> float:
	return float(ticks) / float(maxi(tick_rate, 1))


func upsert_division(d: DivisionData) -> void:
	if not divisions.has(d.id):
		division_ids.append(d.id)
	divisions[d.id] = d


func remove_division(id: String) -> void:
	divisions.erase(id)
	division_ids.erase(id)


func get_division(id: String) -> DivisionData:
	return divisions.get(id) as DivisionData


func all_divisions() -> Array[DivisionData]:
	var out: Array[DivisionData] = []
	for id in division_ids:
		out.append(divisions[id])
	return out


func alive_count() -> int:
	var n := 0
	for d in all_divisions():
		if d.is_alive():
			n += 1
	return n


func set_players(list: Variant) -> void:
	players.clear()
	if not list is Array:
		return
	for raw in list:
		players.append({
			"id": str(raw.get("id", "")),
			"name": str(raw.get("name", "")),
			"side": int(raw.get("side", 0)),
			"ready": bool(raw.get("ready", false)),
			"connected": bool(raw.get("connected", true)),
			"bot": bool(raw.get("bot", false)),
		})


func get_player(player_id: String) -> Dictionary:
	for p in players:
		if p["id"] == player_id:
			return p
	return {}


func player_name(player_id: String) -> String:
	var p := get_player(player_id)
	return str(p.get("name", player_id))


## Side (0 or 1) of a player; drives colors and base assignment.
func side_of(player_id: String) -> int:
	var p := get_player(player_id)
	if not p.is_empty():
		return int(p["side"])
	return 0 if player_id.ends_with("1") else 1


func division_name(id: String) -> String:
	var d := get_division(id)
	return d.display_name if d != null else id


func elapsed_seconds() -> float:
	return float(tick) / float(maxi(tick_rate, 1))
