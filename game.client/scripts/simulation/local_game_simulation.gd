class_name LocalGameSimulation
extends RefCounted
## In-process mock of the Go server, for developing the client without it.
## It speaks the same protocol: handle() takes client messages and step()
## returns server messages. The UI never sees these objects directly.
## Movement uses grid A* (Pathfinder) like the server. Splitting and merging
## divisions exist only here for now (the Go server implements formations,
## unit types and volleys, but not split/merge, physical space or assist).

const GAME_ID := "local"
const PLAYER_1 := "player-1"
const PLAYER_2 := "player-2"
const ORDER_BY_MESSAGE := {
	"move_division": "MOVE",
	"attack_division": "ATTACK",
	"defend_division": "DEFEND",
	"retreat_division": "RETREAT",
	"hold_division": "HOLD",
	"merge_division": "MERGE",
}


class SimDivision:
	var id := ""
	var player_id := ""
	var name := ""
	var position := Vector2.ZERO
	var home := Vector2.ZERO
	var destination := Vector2.ZERO
	var unit_count := 0
	var max_unit_count := 0
	var attack := 0.0
	var defense := 0.0
	var speed := 0.0
	var morale := 0.0
	var experience := 0.0
	var fatigue := 0.0
	var state := GameTypes.STATE_IDLE
	var order: Dictionary = {}  # protocol order object; empty = no order
	var routed := false
	var moved := 0.0
	## Remaining waypoints (world units) towards `destination`.
	var path := PackedVector2Array()
	var blocked_ticks := 0
	var formation := Formations.DEFAULT
	var facing := 0.0  # radians, world space; where the front looks
	var reform_ticks := 0  # > 0 while changing formation
	var unit_type := UnitTypes.DEFAULT
	var volley_cooldown := 0  # ticks until a ranged division can shoot again
	var best_distance := INF  # closest it got to its destination (stall detection)
	var stall_ticks := 0

	func alive() -> bool:
		return state != GameTypes.STATE_DESTROYED

	func order_type() -> String:
		return str(order.get("type", "")).to_upper()


class SimBattle:
	var id := ""
	var attacker: SimDivision
	var defender: SimDivision
	var position := Vector2.ZERO
	var started_tick := 0
	var rounds := 0
	var attacker_losses := 0
	var defender_losses := 0
	var active := true

	func involves(d: SimDivision) -> bool:
		return attacker == d or defender == d

	func opponent(d: SimDivision) -> SimDivision:
		return defender if attacker == d else attacker


var rules: Dictionary
var map: MapData
var movement := MovementSystem.new()
var pathfinder: Pathfinder
var combat: CombatResolver
var tick_rate := 10
var status := GameTypes.STATUS_WAITING
var tick := 0
var countdown := 0
var players: Array[Dictionary] = []
var divisions: Array[SimDivision] = []
var battles: Array[SimBattle] = []
var winner_id := ""
var finish_reason := ""

var _by_id: Dictionary = {}
var _pending: Array[Dictionary] = []
var _out: Array[Dictionary] = []
var _order_seq := 0
var _battle_seq := 0
var _division_seq := 0
var _pending_splits: Array[Dictionary] = []
var _pending_formations: Array[Dictionary] = []


func _init(p_rules: Dictionary, p_map: MapData, army: Array) -> void:
	rules = p_rules
	map = p_map
	tick_rate = int(rules.get("tick_rate", 10))
	var combat_params: Variant = rules.get("combat", {})
	combat = CombatResolver.new(combat_params if combat_params is Dictionary else {})
	players.append({"id": PLAYER_1, "name": "Jugador 1", "side": 0, "ready": true, "connected": true})
	players.append({"id": PLAYER_2, "name": "Jugador 2", "side": 1, "ready": true, "connected": true})
	pathfinder = Pathfinder.new(map)
	_deploy(army)
	_division_seq = divisions.size()


# --- Rules helpers -----------------------------------------------------------

func _rule(key: String, fallback: float) -> float:
	return float(rules.get(key, fallback))


func _dt() -> float:
	return 1.0 / float(tick_rate)


# --- Session -------------------------------------------------------------------

## The message a real server sends after create/join.
func joined_message(player_id: String) -> Dictionary:
	return {
		"type": Protocol.GAME_CREATED,
		"game_id": GAME_ID,
		"player_id": player_id,
		"session_token": "",
		"side": _player_side(player_id),
		"tick_rate": tick_rate,
		"map": map.to_protocol(),
		"state": snapshot(),
	}


## Both local players are ready: deploy and begin the countdown.
func start() -> Array:
	_out = []
	status = GameTypes.STATUS_STARTING
	countdown = int(rules.get("start_countdown_ticks", 0))
	_out.append(_lobby())
	if countdown <= 0:
		_begin()
	_out.append(snapshot())
	return _take()


## Each player gets the same army. Stats come from the unit type
## (unit_types.json) unless the army entry overrides them; entries without an
## offset are placed in columns in front of the spawn.
func _deploy(army: Array) -> void:
	var seq := 0
	for p in players:
		var side: int = p["side"]
		var per_type := {}
		for i in army.size():
			var t: Dictionary = army[i]
			seq += 1
			var type := str(t.get("type", UnitTypes.DEFAULT)).to_upper()
			if not UnitTypes.exists(type):
				type = UnitTypes.DEFAULT
			var base := UnitTypes.get_def(type)
			per_type[type] = int(per_type.get(type, 0)) + 1
			var offset := Protocol.vec_from(t["offset"]) if t.has("offset") else _deploy_slot(i, army.size())
			if side == 1:
				offset.x = -offset.x
			var d := SimDivision.new()
			d.id = "division-%d" % seq
			d.player_id = p["id"]
			d.unit_type = type
			d.name = str(t.get("name", "%da %s" % [per_type[type], UnitTypes.label(type)]))
			var spot: Vector2 = map.spawns[side] + offset
			d.position = spot if map.is_passable(spot) else _free_spot_near(spot)
			d.home = d.position
			d.destination = d.position
			d.unit_count = int(t.get("unit_count", 1000))
			d.max_unit_count = d.unit_count
			d.attack = float(t.get("attack", base.get("attack", 10)))
			d.defense = float(t.get("defense", base.get("defense", 10)))
			d.speed = float(t.get("speed", base.get("speed", 30)))
			d.morale = minf(float(t.get("morale", base.get("morale", 80))), _rule("max_morale", 100))
			d.experience = float(t.get("experience", base.get("experience", 0)))
			var formation := str(t.get("formation", Formations.DEFAULT)).to_upper()
			d.formation = formation if Formations.exists(formation) else Formations.DEFAULT
			d.facing = 0.0 if side == 0 else PI  # facing the enemy base
			divisions.append(d)
			_by_id[d.id] = d


## Automatic deployment slot: columns of up to 4 divisions, the first column
## closest to the enemy (x is mirrored for the second player).
func _deploy_slot(index: int, count: int) -> Vector2:
	var per_column := 4
	var column := index / per_column
	var in_column := mini(per_column, count - column * per_column)
	var row := index % per_column
	return Vector2(90.0 - column * 110.0, (row - (in_column - 1) * 0.5) * 120.0)


func _begin() -> void:
	status = GameTypes.STATUS_RUNNING
	_out.append({"type": Protocol.GAME_STARTED, "game_id": GAME_ID, "tick": tick, "state": snapshot()})


# --- Client messages -----------------------------------------------------------

func handle(player_id: String, msg: Dictionary) -> Array:
	var request_id := str(msg.get("request_id", ""))
	var msg_type := str(msg.get("type", ""))
	if msg_type == Protocol.READY:
		return []
	if msg_type == Protocol.SPLIT_DIVISION:
		return _handle_split(player_id, request_id, msg)
	if msg_type == Protocol.SET_FORMATION:
		return _handle_formation(player_id, request_id, msg)
	var order_type := str(ORDER_BY_MESSAGE.get(msg_type, ""))
	if order_type.is_empty():
		return [_error(request_id, "unknown_message_type", "Mensaje no soportado en modo local: %s" % msg_type)]

	var division_id := str(msg.get("division_id", ""))
	var has_pos := msg.has("x") and msg.has("y")
	var target_pos := Vector2(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)))
	var target_id := str(msg.get("target_division_id", ""))
	var problem := _validate(player_id, division_id, order_type, has_pos, target_pos, target_id)
	if not problem.is_empty():
		return [_error(request_id, problem["code"], problem["message"])]

	var d: SimDivision = _by_id[division_id]
	if order_type == Order.RETREAT and not has_pos:
		target_pos = d.home
		has_pos = true
	_order_seq += 1
	var order := {"id": "order-%d" % _order_seq, "type": order_type.to_lower()}
	if has_pos and (order_type == Order.MOVE or order_type == Order.RETREAT):
		order["target_position"] = Protocol.vec_to(target_pos)
	if order_type == Order.ATTACK or order_type == Order.MERGE:
		order["target_division_id"] = target_id
	_pending.append({"division": d, "order": order})
	return [{"type": Protocol.ORDER_ACCEPTED, "request_id": request_id, "division_id": division_id, "order": order}]


func _validate(player_id: String, division_id: String, order_type: String,
		has_pos: bool, target_pos: Vector2, target_id: String) -> Dictionary:
	if status != GameTypes.STATUS_RUNNING:
		return _problem("game_not_running", "La partida no está en curso")
	if not _by_id.has(division_id):
		return _problem("division_not_found", "La división no existe")
	var d: SimDivision = _by_id[division_id]
	if d.player_id != player_id:
		return _problem("not_owner", "Esa división pertenece al rival")
	if not d.alive():
		return _problem("division_destroyed", "La división está destruida")
	if d.routed and order_type != Order.RETREAT:
		return _problem("division_routed", "La división está desbandada: solo acepta RETIRARSE")
	if _engaged(d) and order_type in [Order.MOVE, Order.ATTACK, Order.MERGE]:
		return _problem("division_engaged", "En combate solo se puede DEFENDER, RETIRARSE o MANTENER")
	if order_type == Order.MOVE:
		if not has_pos:
			return _problem("target_required", "Falta el destino")
		return _check_route(d, target_pos)
	if order_type == Order.RETREAT and has_pos:
		return _check_route(d, target_pos)
	if order_type == Order.MERGE:
		return _check_merge_target(player_id, d, target_id)
	if order_type == Order.ATTACK:
		if target_id.is_empty():
			return _problem("target_required", "Falta la división objetivo")
		if not _by_id.has(target_id):
			return _problem("target_not_found", "La división objetivo no existe")
		var t: SimDivision = _by_id[target_id]
		if t.player_id == player_id:
			return _problem("target_friendly", "No se puede atacar a una división propia")
		if not t.alive():
			return _problem("target_destroyed", "La división objetivo ya fue destruida")
	return {}


func _check_position(p: Vector2) -> Dictionary:
	if not map.in_bounds(p):
		return _problem("invalid_position", "El destino está fuera del mapa")
	if not map.is_passable(p):
		return _problem("impassable_position", "El destino es intransitable (agua)")
	return {}


func _check_route(d: SimDivision, p: Vector2) -> Dictionary:
	var problem := _check_position(p)
	if problem.is_empty() and not pathfinder.is_reachable(d.position, p):
		return _problem("unreachable", "No hay camino hasta el destino")
	return problem


func _check_merge_target(player_id: String, d: SimDivision, target_id: String) -> Dictionary:
	if target_id.is_empty():
		return _problem("target_required", "Falta la división con la que unirse")
	if target_id == d.id:
		return _problem("merge_self", "Una división no puede unirse consigo misma")
	if not _by_id.has(target_id):
		return _problem("target_not_found", "La división objetivo no existe")
	var t: SimDivision = _by_id[target_id]
	if t.player_id != player_id:
		return _problem("target_not_friendly", "Solo se puede unir con divisiones propias")
	if t.unit_type != d.unit_type:
		return _problem("type_mismatch", "Solo se pueden unir divisiones del mismo tipo")
	if not t.alive():
		return _problem("target_destroyed", "La división objetivo ya fue destruida")
	return {}


## split_division: validated now, applied on the next tick (like orders).
func _handle_split(player_id: String, request_id: String, msg: Dictionary) -> Array:
	var division_id := str(msg.get("division_id", ""))
	var ratio := float(msg.get("ratio", 0.5))
	var problem := _validate_split(player_id, division_id, ratio)
	if not problem.is_empty():
		return [_error(request_id, problem["code"], problem["message"])]
	_pending_splits.append({"division": _by_id[division_id], "ratio": ratio})
	return []


## set_formation: validated now, applied on the next tick. The division then
## spends formation_change_seconds reorganizing (slower and weaker).
func _handle_formation(player_id: String, request_id: String, msg: Dictionary) -> Array:
	var division_id := str(msg.get("division_id", ""))
	var formation := GameTypes.from_wire(str(msg.get("formation", "")))
	var problem := _validate_formation(player_id, division_id, formation)
	if not problem.is_empty():
		return [_error(request_id, problem["code"], problem["message"])]
	_pending_formations.append({"division": _by_id[division_id], "formation": formation})
	return []


func _validate_formation(player_id: String, division_id: String, formation: String) -> Dictionary:
	if status != GameTypes.STATUS_RUNNING:
		return _problem("game_not_running", "La partida no está en curso")
	if not _by_id.has(division_id):
		return _problem("division_not_found", "La división no existe")
	var d: SimDivision = _by_id[division_id]
	if d.player_id != player_id:
		return _problem("not_owner", "Esa división pertenece al rival")
	if not d.alive():
		return _problem("division_destroyed", "La división está destruida")
	if d.routed:
		return _problem("division_routed", "Una división desbandada no puede formar")
	if not Formations.exists(formation):
		return _problem("invalid_formation", "Formación desconocida")
	if d.formation == formation:
		return _problem("same_formation", "La división ya está en esa formación")
	return {}


func _validate_split(player_id: String, division_id: String, ratio: float) -> Dictionary:
	if status != GameTypes.STATUS_RUNNING:
		return _problem("game_not_running", "La partida no está en curso")
	if not _by_id.has(division_id):
		return _problem("division_not_found", "La división no existe")
	var d: SimDivision = _by_id[division_id]
	if d.player_id != player_id:
		return _problem("not_owner", "Esa división pertenece al rival")
	if not d.alive():
		return _problem("division_destroyed", "La división está destruida")
	if d.routed:
		return _problem("division_routed", "Una división desbandada no puede dividirse")
	if _engaged(d):
		return _problem("division_engaged", "No se puede dividir en pleno combate")
	if ratio < 0.1 or ratio > 0.9:
		return _problem("invalid_ratio", "La proporción debe estar entre 0.1 y 0.9")
	var min_units := int(rules.get("min_split_units", 300))
	var part := floori(d.unit_count * ratio)
	if part < min_units or d.unit_count - part < min_units:
		return _problem("division_too_small", "Cada parte necesita al menos %d unidades" % min_units)
	return {}


func _problem(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message}


func _error(request_id: String, code: String, message: String) -> Dictionary:
	return {"type": Protocol.ERROR, "request_id": request_id, "code": code, "message": message}


# --- Game loop -------------------------------------------------------------------

## Advances one tick and returns the messages produced (events + snapshot).
func step() -> Array:
	_out = []
	if status == GameTypes.STATUS_STARTING:
		countdown -= 1
		if countdown <= 0:
			_begin()
	elif status == GameTypes.STATUS_RUNNING:
		tick += 1
		_process_orders()
		_update_movement()
		_update_formations()
		_separate_divisions()
		_check_stalled()
		_detect_encounters()
		_update_battles()
		_update_assist()
		_update_volleys()
		_update_morale_fatigue()
		_check_victory()
	else:
		return []
	_out.append(snapshot())
	return _take()


func _take() -> Array:
	var out := _out
	_out = []
	return out


func _process_orders() -> void:
	for pending in _pending:
		var d: SimDivision = pending["division"]
		var order: Dictionary = pending["order"]
		if not d.alive() or (d.routed and str(order["type"]) != "retreat"):
			continue
		d.order = order
		d.path = PackedVector2Array()
		d.blocked_ticks = 0
		d.best_distance = INF
		d.stall_ticks = 0
		if order.has("target_position"):
			d.destination = Protocol.vec_from(order["target_position"])
			d.path = pathfinder.find_path(d.position, d.destination)
		_refresh_state(d, "order", true)
	_pending.clear()
	for split in _pending_splits:
		var sd: SimDivision = split["division"]
		if _by_id.has(sd.id) and _validate_split(sd.player_id, sd.id, split["ratio"]).is_empty():
			_split(sd, split["ratio"])
	_pending_splits.clear()
	for change in _pending_formations:
		var fd: SimDivision = change["division"]
		if _by_id.has(fd.id) and _validate_formation(fd.player_id, fd.id, change["formation"]).is_empty():
			fd.formation = change["formation"]
			fd.reform_ticks = maxi(roundi(_rule("formation_change_seconds", 3.0) * tick_rate), 1)
			_refresh_state(fd, "formation_changed", true)
	_pending_formations.clear()


func _split(d: SimDivision, ratio: float) -> void:
	_division_seq += 1
	var n := SimDivision.new()
	n.id = "division-%d" % _division_seq
	n.player_id = d.player_id
	n.name = _split_name(d.name)
	n.unit_count = floori(d.unit_count * ratio)
	d.unit_count -= n.unit_count
	n.max_unit_count = maxi(roundi(d.max_unit_count * ratio), n.unit_count)
	d.max_unit_count = maxi(d.max_unit_count - n.max_unit_count, d.unit_count)
	for stat in ["attack", "defense", "speed", "morale", "experience", "fatigue", "home", "formation", "facing", "unit_type"]:
		n.set(stat, d.get(stat))
	n.position = _free_spot_near(d.position)
	n.destination = n.position
	d.order = {}
	d.path = PackedVector2Array()
	d.destination = d.position
	divisions.append(n)
	_by_id[n.id] = n
	d.state = _derive_state(d)
	n.state = _derive_state(n)
	_out.append({
		"type": Protocol.DIVISION_SPLIT, "tick": tick, "division_id": d.id, "new_division_id": n.id,
		"division": _division_dto(d), "new_division": _division_dto(n),
	})


## "1a Division Obrera" -> "1a Division Obrera (2)", "(3)"...
func _split_name(name: String) -> String:
	var base := name
	var open := name.rfind(" (")
	if open > 0 and name.ends_with(")"):
		base = name.substr(0, open)
	var n := 2
	var taken := {}
	for d in divisions:
		taken[d.name] = true
	while taken.has("%s (%d)" % [base, n]):
		n += 1
	return "%s (%d)" % [base, n]


## A passable spot next to `p` for a newly split division.
func _free_spot_near(p: Vector2) -> Vector2:
	var r := map.cell_size
	for offset in [Vector2(0, r), Vector2(r, 0), Vector2(0, -r), Vector2(-r, 0),
			Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
		if map.is_passable(p + offset):
			return p + offset
	return p


## `d` absorbs `t`: units add up, stats are averaged by unit count and the
## speed is the slowest one. `t` disappears from the game.
func _merge(d: SimDivision, t: SimDivision) -> void:
	var total := d.unit_count + t.unit_count
	var w := float(d.unit_count) / float(maxi(total, 1))
	for stat in ["attack", "defense", "morale", "experience", "fatigue"]:
		d.set(stat, float(d.get(stat)) * w + float(t.get(stat)) * (1.0 - w))
	d.speed = minf(d.speed, t.speed)
	d.unit_count = total
	d.max_unit_count += t.max_unit_count
	d.position = t.position
	d.destination = d.position
	d.path = PackedVector2Array()
	d.order = {}
	divisions.erase(t)
	_by_id.erase(t.id)
	for i in range(_pending.size() - 1, -1, -1):
		if _pending[i]["division"] == t:
			_pending.remove_at(i)
	for i in range(_pending_splits.size() - 1, -1, -1):
		if _pending_splits[i]["division"] == t:
			_pending_splits.remove_at(i)
	# Whoever was chasing (or joining) the absorbed division now follows the result.
	for o in divisions:
		if o != d and str(o.order.get("target_division_id", "")) == t.id:
			o.order["target_division_id"] = d.id
	d.state = _derive_state(d)
	_out.append({
		"type": Protocol.DIVISIONS_MERGED, "tick": tick, "division_id": d.id,
		"merged_division_id": t.id, "merged_division_name": t.name, "division": _division_dto(d),
	})


func _speed_multiplier(d: SimDivision) -> float:
	var min_factor := _rule("min_fatigue_speed_factor", 0.6)
	var m := 1.0 - (1.0 - min_factor) * clampf(d.fatigue, 0.0, 100.0) / 100.0
	if d.state == GameTypes.STATE_RETREATING:
		m *= _rule("retreat_speed_multiplier", 1.2)
	m *= Formations.stat(d.formation, "speed")
	if d.reform_ticks > 0:
		m *= _rule("reform_speed_factor", 0.5)
	return m


func _update_movement() -> void:
	var merges: Array = []  # [[absorber, absorbed], ...] applied after the loop
	for d in divisions:
		d.moved = 0.0
		if not d.alive() or d.order.is_empty():
			continue
		if _engaged(d) and d.state != GameTypes.STATE_RETREATING:
			continue
		var ot := d.order_type()
		if ot == Order.DEFEND or ot == Order.HOLD:
			continue
		var chasing := ot == Order.ATTACK or ot == Order.MERGE
		if chasing:
			var target: SimDivision = _by_id.get(str(d.order.get("target_division_id", "")))
			if target == null or not target.alive():
				_complete(d, "target_destroyed" if ot == Order.ATTACK else "merge_target_lost")
				continue
			# Distances between divisions are measured edge to edge: they cannot overlap.
			var reach := _contact(d, target) + _rule("merge_margin", 10)
			if ot == Order.ATTACK:
				# Ranged divisions stop when the target is within their range.
				reach = _contact(d, target) + _rule("engagement_margin", 10) * 0.5
				if UnitTypes.is_ranged(d.unit_type):
					reach = UnitTypes.attack_range(d.unit_type) * 0.9
			if d.position.distance_to(target.position) <= reach:
				if ot == Order.MERGE:
					merges.append([d, target])
				continue
			_chase(d, target.position)
		_move_along_path(d, chasing)
	for pair in merges:
		var a: SimDivision = pair[0]
		var b: SimDivision = pair[1]
		if not _by_id.has(a.id) or not _by_id.has(b.id):
			continue  # one of them was already merged this tick
		if _engaged(a) or _engaged(b):
			_complete(a, "merge_failed")
		else:
			_merge(a, b)


## Re-plans the route of a chase when the target moved away from its end.
func _chase(d: SimDivision, goal: Vector2) -> void:
	if d.path.is_empty() or goal.distance_to(d.destination) > _rule("path_recompute_distance", 40):
		d.destination = goal
		d.path = pathfinder.find_path(d.position, goal)


func _move_along_path(d: SimDivision, chasing: bool) -> void:
	if d.path.is_empty() and d.position.distance_to(d.destination) > 0.5:
		d.path = pathfinder.find_path(d.position, d.destination)
		if d.path.is_empty():
			_complete(d, "blocked")
			return
	var before := d.position
	var res := movement.follow(map, d.position, d.path, d.speed * _speed_multiplier(d), _dt())
	d.position = res["position"]
	if d.position.distance_squared_to(before) > 0.0001:
		d.facing = (d.position - before).angle()  # the front looks where it marches
	d.path = res["path"]
	d.moved = res["moved"]
	if res["blocked"]:
		# Re-plan from here next tick; give up only if it keeps failing.
		d.path = PackedVector2Array()
		d.blocked_ticks += 1
		if d.blocked_ticks > 3:
			_complete(d, "blocked")
	elif d.path.is_empty() and not chasing:
		_complete(d, "arrived")
	else:
		d.blocked_ticks = 0


## Reorganization countdown, and engaged divisions turning their front
## towards their main opponent (at the formation's turn rate).
func _update_formations() -> void:
	for d in divisions:
		if not d.alive():
			continue
		if d.reform_ticks > 0:
			d.reform_ticks -= 1
			if d.reform_ticks == 0:
				_refresh_state(d, "formation_ready", true)
		if d.state == GameTypes.STATE_RETREATING or not _engaged(d):
			continue
		var opponent := _primary_opponent(d)
		if opponent != null:
			var target := (opponent.position - d.position).angle()
			var max_turn := deg_to_rad(Formations.stat(d.formation, "turn_rate", 60.0)) * _dt()
			d.facing = wrapf(d.facing + clampf(angle_difference(d.facing, target), -max_turn, max_turn), -PI, PI)


## Opponent of the oldest active battle of `d`.
func _primary_opponent(d: SimDivision) -> SimDivision:
	for b in battles:
		if b.active and b.involves(d):
			return b.opponent(d)
	return null


## Side of `d` hit by `enemy`: "front", "flank" or "rear".
func _exposure(d: SimDivision, enemy: SimDivision) -> String:
	return Formations.exposure(d.facing, enemy.position - d.position)


## Idle divisions near a friend in combat go to help it, attacking its
## opponent (they often arrive on its flank). Divisions told to HOLD (or to
## DEFEND, unless assist_while_defending) stay put; busy ones keep their order.
func _update_assist() -> void:
	if tick % maxi(int(rules.get("assist_check_ticks", 5)), 1) != 0:
		return
	var radius := _rule("assist_radius", 350)
	var while_defending := bool(rules.get("assist_while_defending", false))
	for d in divisions:
		if not d.alive() or d.routed or _engaged(d):
			continue
		var ot := d.order_type()
		if not (ot.is_empty() or (ot == Order.DEFEND and while_defending)):
			continue
		var target := _enemy_of_nearby_fight(d, radius)
		if target == null:
			continue
		_order_seq += 1
		d.order = {"id": "order-%d" % _order_seq, "type": "attack", "target_division_id": target.id, "auto": true}
		d.path = PackedVector2Array()
		d.blocked_ticks = 0
		_refresh_state(d, "assisting", true)


## Opponent of the closest friend of `d` fighting within `radius`, or null.
func _enemy_of_nearby_fight(d: SimDivision, radius: float) -> SimDivision:
	var best: SimDivision = null
	var best_dist := radius
	for b in battles:
		if not b.active:
			continue
		for friend: SimDivision in [b.attacker, b.defender]:
			if friend == d or friend.player_id != d.player_id:
				continue
			var dist := d.position.distance_to(friend.position)
			if dist <= best_dist:
				best_dist = dist
				best = b.opponent(friend)
	return best


## Ranged divisions shoot once per combat round at an enemy in range, when
## they are not marching, retreating or caught in melee.
func _update_volleys() -> void:
	var round_ticks := int(rules.get("combat_round_ticks", 10))
	for d in divisions:
		if not d.alive() or not UnitTypes.is_ranged(d.unit_type):
			continue
		if d.volley_cooldown > 0:
			d.volley_cooldown -= 1
			continue
		if d.routed or d.state == GameTypes.STATE_RETREATING or d.moved > 0.0 or _engaged(d):
			continue
		var target := _volley_target(d)
		if target == null:
			continue
		d.facing = (target.position - d.position).angle()
		_volley(d, target)
		d.volley_cooldown = round_ticks


## The attack target if it is in range, otherwise the closest enemy in range.
func _volley_target(d: SimDivision) -> SimDivision:
	var reach := UnitTypes.attack_range(d.unit_type)
	var ordered: SimDivision = _by_id.get(str(d.order.get("target_division_id", "")))
	if d.order_type() == Order.ATTACK and ordered != null and ordered.alive() \
			and d.position.distance_to(ordered.position) <= reach:
		return ordered
	var best: SimDivision = null
	var best_dist := reach
	for o in divisions:
		if o.alive() and o.player_id != d.player_id:
			var dist := d.position.distance_to(o.position)
			if dist <= best_dist:
				best = o
				best_dist = dist
	return best


func _volley(d: SimDivision, target: SimDivision) -> void:
	var shooter := _combatant(d, target)
	shooter["attack"] = UnitTypes.ranged_attack(d.unit_type)
	shooter["stance"] = CombatResolver.STANCE_HOLDING
	var victim := _combatant(target, d)
	var result := combat.resolve_volley(shooter, victim)
	_apply_side(target, result)
	d.experience = clampf(d.experience + float(rules.get("combat", {}).get("experience_per_round", 0.4)) * 0.5, 0.0, 100.0)
	_out.append({
		"type": Protocol.VOLLEY, "tick": tick, "shooter_id": d.id, "target_id": target.id,
		"losses": result["losses"], "unit_count": target.unit_count, "exposure": victim["exposure"],
		"from": Protocol.vec_to(d.position), "to": Protocol.vec_to(target.position),
	})
	if target.unit_count <= int(rules.get("destroyed_unit_threshold", 100)):
		_destroy(target, null)
	elif not target.routed and target.morale <= _rule("rout_morale_threshold", 20):
		_rout(target)


# --- Physical space ---------------------------------------------------------------

## Radius of the ground a division occupies (world units). It grows with its
## soldiers with the same curve the client draws, so what you see collides.
func _radius(d: SimDivision) -> float:
	var reference := _rule("division_radius_reference_units", 3000)
	var r := _rule("division_radius", 25) * pow(maxf(d.unit_count, 1.0) / reference, _rule("division_radius_exponent", 0.75))
	return clampf(r, _rule("division_radius_min", 10), _rule("division_radius_max", 60))


## Distance between the centers of two divisions that just touch.
func _contact(a: SimDivision, b: SimDivision) -> float:
	return _radius(a) + _radius(b)


## Pushes apart divisions that overlap (friends and foes). Whoever is
## marching yields to whoever stands still, fights or holds; nobody is pushed
## into the water.
func _separate_divisions() -> void:
	var alive: Array[SimDivision] = []
	for d in divisions:
		if d.alive():
			alive.append(d)
	for _iteration in int(_rule("separation_iterations", 2)):
		for i in alive.size():
			for j in range(i + 1, alive.size()):
				_push_apart(alive[i], alive[j])


func _push_apart(a: SimDivision, b: SimDivision) -> void:
	var min_dist := _contact(a, b)
	var delta := b.position - a.position
	var dist := delta.length()
	if dist >= min_dist:
		return
	var dir := delta / dist if dist > 0.001 else Vector2.from_angle(float(posmod(hash(a.id + b.id), 628)) / 100.0)
	var wa := _push_weight(a)
	var wb := _push_weight(b)
	var push_a := -dir
	var push_b := dir
	if wa == 1.0 and wb == 1.0:
		# Both marching: a slight sideways component lets them slide past each other.
		push_a = push_a.rotated(0.5 if a.id < b.id else -0.5)
		push_b = push_b.rotated(0.5 if a.id < b.id else -0.5)
	elif wa > wb:
		push_a = _sidestep(a, push_a)
	elif wb > wa:
		push_b = _sidestep(b, push_b)
	var overlap := min_dist - dist
	var move_a := push_a * overlap * wa / (wa + wb)
	var move_b := push_b * overlap * wb / (wa + wb)
	var a_ok := map.is_passable(a.position + move_a)
	var b_ok := map.is_passable(b.position + move_b)
	if a_ok and not b_ok:
		move_a = push_a * overlap
		move_b = Vector2.ZERO
		a_ok = map.is_passable(a.position + move_a)
	elif b_ok and not a_ok:
		move_b = push_b * overlap
		move_a = Vector2.ZERO
		b_ok = map.is_passable(b.position + move_b)
	if a_ok:
		a.position += move_a
	if b_ok:
		b.position += move_b


## A marching division that bumps into one standing still is pushed mostly
## sideways (relative to where it is heading), so it walks around it instead
## of being stopped head-on.
func _sidestep(mover: SimDivision, away: Vector2) -> Vector2:
	var next := mover.path[0] if not mover.path.is_empty() else mover.destination
	var heading := next - mover.position
	if heading.length_squared() < 0.01:
		return away
	heading = heading.normalized()
	var side := Vector2(-heading.y, heading.x)
	if side.dot(away) < 0.0:
		side = -side
	return (away + side * 1.5).normalized()


## How easily a division is pushed: marching ones yield, the rest stand firm.
func _push_weight(d: SimDivision) -> float:
	var ot := d.order_type()
	if d.moved <= 0.0 or _engaged(d) or ot == Order.DEFEND or ot == Order.HOLD:
		return 0.25
	return 1.0


## A MOVE/RETREAT that stops getting closer (its destination is taken by
## other divisions) ends where it is instead of pushing forever.
func _check_stalled() -> void:
	var limit := int(_rule("stall_ticks", 15))
	for d in divisions:
		var ot := d.order_type()
		if not d.alive() or (ot != Order.MOVE and ot != Order.RETREAT) or _engaged(d):
			continue
		var dist := _remaining_route(d)
		if dist < d.best_distance - 0.1:
			d.best_distance = dist
			d.stall_ticks = 0
			continue
		d.stall_ticks += 1
		if d.stall_ticks >= limit and d.position.distance_to(d.destination) <= _radius(d) * 4.0:
			_complete(d, "arrived")
		elif d.stall_ticks >= limit * 4:
			_complete(d, "blocked")


## Length still to walk along the planned route (detours included, so
## going around a river does not look like a lack of progress).
func _remaining_route(d: SimDivision) -> float:
	if d.path.is_empty():
		return d.position.distance_to(d.destination)
	var total := 0.0
	var from := d.position
	for p in d.path:
		total += from.distance_to(p)
		from = p
	return total


func _complete(d: SimDivision, reason: String) -> void:
	d.order = {}
	d.path = PackedVector2Array()
	d.blocked_ticks = 0
	_refresh_state(d, reason, true)


func _engaged(d: SimDivision) -> bool:
	for b in battles:
		if b.active and b.involves(d):
			return true
	return false


func _initiated_battle(d: SimDivision) -> bool:
	for b in battles:
		if b.active and b.attacker == d:
			return true
	return false


func _battle_between(a: SimDivision, b: SimDivision) -> bool:
	for bt in battles:
		if bt.active and bt.involves(a) and bt.involves(b):
			return true
	return false


func _targets(a: SimDivision, b: SimDivision) -> bool:
	return a.order_type() == Order.ATTACK and str(a.order.get("target_division_id", "")) == b.id


func _detect_encounters() -> void:
	var margin := _rule("engagement_margin", 10)
	for i in divisions.size():
		var a := divisions[i]
		if not a.alive():
			continue
		for j in range(i + 1, divisions.size()):
			var b := divisions[j]
			if not b.alive() or a.player_id == b.player_id:
				continue
			if a.position.distance_to(b.position) > _contact(a, b) + margin or _battle_between(a, b):
				continue
			var attacker := a
			var defender := b
			if _targets(b, a) and not _targets(a, b):
				attacker = b
				defender = a
			elif not _targets(a, b) and b.state == GameTypes.STATE_MOVING and a.state != GameTypes.STATE_MOVING:
				attacker = b
				defender = a
			_start_battle(attacker, defender)


func _start_battle(attacker: SimDivision, defender: SimDivision) -> void:
	_battle_seq += 1
	var b := SimBattle.new()
	b.id = "battle-%d" % _battle_seq
	b.attacker = attacker
	b.defender = defender
	b.position = (attacker.position + defender.position) * 0.5
	b.started_tick = tick
	battles.append(b)
	_out.append({
		"type": Protocol.BATTLE_STARTED, "tick": tick, "battle_id": b.id,
		"attacker_id": attacker.id, "defender_id": defender.id,
		"x": b.position.x, "y": b.position.y,
		"attacker_exposure": _exposure(attacker, defender), "defender_exposure": _exposure(defender, attacker),
	})
	_refresh_state(attacker, "battle_started", false)
	_refresh_state(defender, "battle_started", false)


func _update_battles() -> void:
	var disengage := _rule("disengage_margin", 40)
	var round_ticks := int(rules.get("combat_round_ticks", 10))
	for b: SimBattle in battles.duplicate():
		if not b.active:
			continue
		if not b.attacker.alive() or not b.defender.alive():
			_end_battle(b, "destroyed", _survivor(b.attacker, b.defender))
			continue
		if b.attacker.position.distance_to(b.defender.position) > _contact(b.attacker, b.defender) + disengage:
			_end_battle(b, "disengaged", _non_retreating(b.attacker, b.defender))
			continue
		var elapsed := tick - b.started_tick
		if elapsed > 0 and elapsed % round_ticks == 0:
			_resolve_round(b)
	var still_active: Array[SimBattle] = []
	for b in battles:
		if b.active:
			still_active.append(b)
	battles = still_active


func _stance(d: SimDivision) -> String:
	if d.state == GameTypes.STATE_RETREATING:
		return CombatResolver.STANCE_RETREATING
	if d.state == GameTypes.STATE_ATTACKING:
		return CombatResolver.STANCE_ATTACKING
	if d.state == GameTypes.STATE_DEFENDING and d.order_type() == Order.DEFEND:
		return CombatResolver.STANCE_DEFENDING
	return CombatResolver.STANCE_HOLDING


func _combatant(d: SimDivision, opponent: SimDivision) -> Dictionary:
	var terrain := map.terrain_at(d.position)
	var side := _exposure(d, opponent)
	var reform := _rule("reform_penalty", 0.75) if d.reform_ticks > 0 else 1.0
	return {
		"unit_count": d.unit_count, "attack": d.attack, "defense": d.defense,
		"morale": d.morale, "experience": d.experience, "fatigue": d.fatigue,
		"terrain_attack": map.terrain.attack(terrain), "terrain_defense": map.terrain.defense(terrain),
		"stance": _stance(d),
		"formation_attack": Formations.attack_multiplier(d.formation, opponent.formation) * reform,
		"formation_defense": Formations.defense_multiplier(d.formation, side) * reform,
		"frontage": int(Formations.stat(d.formation, "frontage", float(d.unit_count))),
		"exposure": side,
	}


func _resolve_round(b: SimBattle) -> void:
	var ca := _combatant(b.attacker, b.defender)
	var cb := _combatant(b.defender, b.attacker)
	var result := combat.resolve(ca, cb)
	_apply_side(b.attacker, result["a"])
	_apply_side(b.defender, result["b"])
	b.rounds += 1
	b.attacker_losses += int(result["a"]["losses"])
	b.defender_losses += int(result["b"]["losses"])
	_out.append({
		"type": Protocol.BATTLE_UPDATED, "tick": tick, "battle_id": b.id, "round": b.rounds,
		"attacker": _side_report(b.attacker, result["a"], ca["exposure"]),
		"defender": _side_report(b.defender, result["b"], cb["exposure"]),
	})
	var threshold := int(rules.get("destroyed_unit_threshold", 100))
	for d in [b.attacker, b.defender]:
		if d.alive() and d.unit_count <= threshold:
			_destroy(d, b)
	for d in [b.attacker, b.defender]:
		if d.alive() and not d.routed and d.morale <= _rule("rout_morale_threshold", 20):
			_rout(d)


func _apply_side(d: SimDivision, side: Dictionary) -> void:
	d.unit_count = maxi(d.unit_count - int(side["losses"]), 0)
	d.morale = clampf(d.morale + float(side["morale_delta"]), 0.0, _rule("max_morale", 100))
	d.fatigue = clampf(d.fatigue + float(side["fatigue_delta"]), 0.0, 100.0)
	d.experience = clampf(d.experience + float(side["experience_delta"]), 0.0, 100.0)


func _side_report(d: SimDivision, side: Dictionary, exposure: String) -> Dictionary:
	return {
		"division_id": d.id, "losses": side["losses"], "unit_count": d.unit_count, "exposure": exposure,
		"morale": d.morale, "fatigue": d.fatigue,
		"effective_attack": side["attack"], "effective_defense": side["defense"],
	}


func _end_battle(b: SimBattle, reason: String, winner: SimDivision) -> void:
	if not b.active:
		return
	b.active = false
	_out.append({
		"type": Protocol.BATTLE_ENDED, "tick": tick, "battle_id": b.id,
		"attacker_id": b.attacker.id, "defender_id": b.defender.id,
		"reason": reason, "winner_division_id": winner.id if winner != null else "",
	})
	for d in [b.attacker, b.defender]:
		if d.alive():
			_refresh_state(d, "battle_ended", false)


func _destroy(d: SimDivision, battle: SimBattle) -> void:
	d.unit_count = 0
	d.state = GameTypes.STATE_DESTROYED
	d.order = {}
	d.routed = false
	_out.append({
		"type": Protocol.DIVISION_DESTROYED, "tick": tick, "division_id": d.id,
		"player_id": d.player_id, "battle_id": battle.id if battle != null else "",
	})
	for b in battles:
		if b.active and b.involves(d):
			_end_battle(b, "destroyed", b.opponent(d))


func _rout(d: SimDivision) -> void:
	d.routed = true
	_order_seq += 1
	d.order = {"id": "order-%d" % _order_seq, "type": "retreat", "target_position": Protocol.vec_to(d.home)}
	d.destination = d.home
	d.path = pathfinder.find_path(d.position, d.home)
	d.best_distance = INF
	d.stall_ticks = 0
	_refresh_state(d, "routed", true)


func _survivor(a: SimDivision, b: SimDivision) -> SimDivision:
	if a.alive() and not b.alive():
		return a
	if b.alive() and not a.alive():
		return b
	return null


func _non_retreating(a: SimDivision, b: SimDivision) -> SimDivision:
	var ar := a.state == GameTypes.STATE_RETREATING
	var br := b.state == GameTypes.STATE_RETREATING
	if ar and not br:
		return b
	if br and not ar:
		return a
	return null


func _update_morale_fatigue() -> void:
	var dt := _dt()
	for d in divisions:
		if not d.alive():
			continue
		var engaged := _engaged(d)
		if d.moved > 0.0:
			d.fatigue += _rule("fatigue_move_per_second", 0.5) * dt
		elif not engaged:
			d.fatigue -= _rule("fatigue_recovery_per_second", 1.0) * dt
		d.fatigue = clampf(d.fatigue, 0.0, 100.0)
		if not engaged:
			d.morale = clampf(d.morale + _rule("morale_recovery_per_second", 1.0) * dt, 0.0, _rule("max_morale", 100))
		if d.routed and d.morale >= _rule("rally_morale_threshold", 50):
			d.routed = false
			if d.position.distance_to(d.destination) < 1.0:
				d.order = {}
			_refresh_state(d, "rallied", true)


func _check_victory() -> void:
	if status != GameTypes.STATUS_RUNNING:
		return
	var alive := {PLAYER_1: 0, PLAYER_2: 0}
	var strength := {PLAYER_1: 0, PLAYER_2: 0}
	for d in divisions:
		if d.alive():
			alive[d.player_id] += 1
			strength[d.player_id] += d.unit_count
	if alive[PLAYER_1] == 0 and alive[PLAYER_2] == 0:
		_finish("", "mutual_annihilation")
	elif alive[PLAYER_1] == 0:
		_finish(PLAYER_2, "annihilation")
	elif alive[PLAYER_2] == 0:
		_finish(PLAYER_1, "annihilation")
	else:
		var max_ticks := int(rules.get("max_duration_ticks", 0))
		if max_ticks > 0 and tick >= max_ticks:
			if strength[PLAYER_1] > strength[PLAYER_2]:
				_finish(PLAYER_1, "time_limit")
			elif strength[PLAYER_2] > strength[PLAYER_1]:
				_finish(PLAYER_2, "time_limit")
			else:
				_finish("", "time_limit")


func _finish(winner: String, reason: String) -> void:
	status = GameTypes.STATUS_FINISHED
	winner_id = winner
	finish_reason = reason
	_pending.clear()
	_out.append({"type": Protocol.GAME_FINISHED, "tick": tick, "winner_player_id": winner, "reason": reason})


# --- State derivation & serialization ---------------------------------------------

func _derive_state(d: SimDivision) -> String:
	if not d.alive():
		return GameTypes.STATE_DESTROYED
	var ot := d.order_type()
	if d.routed or ot == Order.RETREAT:
		return GameTypes.STATE_RETREATING
	if _engaged(d):
		if ot == Order.ATTACK or _initiated_battle(d):
			return GameTypes.STATE_ATTACKING
		return GameTypes.STATE_DEFENDING
	if ot == Order.ATTACK:
		return GameTypes.STATE_ATTACKING
	if ot == Order.DEFEND:
		return GameTypes.STATE_DEFENDING
	if ot == Order.MOVE or ot == Order.MERGE:
		return GameTypes.STATE_MOVING
	return GameTypes.STATE_IDLE


func _refresh_state(d: SimDivision, reason: String, force: bool) -> void:
	var s := _derive_state(d)
	if s == d.state and not force:
		return
	d.state = s
	_out.append({"type": Protocol.DIVISION_UPDATED, "tick": tick, "reason": reason, "division": _division_dto(d)})


func _division_dto(d: SimDivision) -> Dictionary:
	var dto := {
		"id": d.id, "player_id": d.player_id, "name": d.name,
		"x": d.position.x, "y": d.position.y,
		"unit_count": d.unit_count, "max_unit_count": d.max_unit_count,
		"attack": d.attack, "defense": d.defense, "speed": d.speed,
		"morale": d.morale, "experience": d.experience, "fatigue": d.fatigue,
		"state": GameTypes.to_wire(d.state), "routed": d.routed, "in_battle": _engaged(d),
		"terrain": GameTypes.to_wire(map.terrain_at(d.position)),
		"formation": GameTypes.to_wire(d.formation), "facing": d.facing, "reforming": d.reform_ticks > 0,
		"unit_type": GameTypes.to_wire(d.unit_type), "radius": _radius(d),
	}
	if not d.order.is_empty():
		dto["order"] = d.order
		if not d.path.is_empty():
			var path := []
			for p in d.path:
				path.append(Protocol.vec_to(p))
			dto["path"] = path
	return dto


func snapshot() -> Dictionary:
	var divs := []
	for d in divisions:
		divs.append(_division_dto(d))
	var bts := []
	for b in battles:
		if b.active:
			bts.append({
				"id": b.id, "attacker_id": b.attacker.id, "defender_id": b.defender.id,
				"x": b.position.x, "y": b.position.y, "started_tick": b.started_tick,
				"rounds": b.rounds, "attacker_losses": b.attacker_losses, "defender_losses": b.defender_losses,
			})
	return {
		"type": Protocol.GAME_STATE, "game_id": GAME_ID, "status": GameTypes.to_wire(status),
		"tick": tick, "countdown_ticks": maxi(countdown, 0), "divisions": divs, "battles": bts,
	}


func _lobby() -> Dictionary:
	return {
		"type": Protocol.LOBBY_UPDATED, "game_id": GAME_ID,
		"status": GameTypes.to_wire(status), "players": players.duplicate(true),
	}


func _player_side(player_id: String) -> int:
	for p in players:
		if p["id"] == player_id:
			return int(p["side"])
	return 0
