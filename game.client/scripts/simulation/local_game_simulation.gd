class_name LocalGameSimulation
extends RefCounted
## In-process mock of the Go server, for developing the client without it.
## It speaks the same protocol: handle() takes client messages and step()
## returns server messages. The UI never sees these objects directly.
## Deliberately simpler than the server (straight-line movement, no A*).

const GAME_ID := "local"
const PLAYER_1 := "player-1"
const PLAYER_2 := "player-2"
const ORDER_BY_MESSAGE := {
	"move_division": "MOVE",
	"attack_division": "ATTACK",
	"defend_division": "DEFEND",
	"retreat_division": "RETREAT",
	"hold_division": "HOLD",
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


func _init(p_rules: Dictionary, p_map: MapData, army: Array) -> void:
	rules = p_rules
	map = p_map
	tick_rate = int(rules.get("tick_rate", 10))
	var combat_params: Variant = rules.get("combat", {})
	combat = CombatResolver.new(combat_params if combat_params is Dictionary else {})
	players.append({"id": PLAYER_1, "name": "Jugador 1", "side": 0, "ready": true, "connected": true})
	players.append({"id": PLAYER_2, "name": "Jugador 2", "side": 1, "ready": true, "connected": true})
	_deploy(army)


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


func _deploy(army: Array) -> void:
	var seq := 0
	for p in players:
		var side: int = p["side"]
		for t in army:
			seq += 1
			var offset := Protocol.vec_from(t.get("offset", {}))
			if side == 1:
				offset.x = -offset.x
			var d := SimDivision.new()
			d.id = "division-%d" % seq
			d.player_id = p["id"]
			d.name = str(t.get("name", d.id))
			d.position = map.spawns[side] + offset
			d.home = d.position
			d.destination = d.position
			d.unit_count = int(t.get("unit_count", 1000))
			d.max_unit_count = d.unit_count
			d.attack = float(t.get("attack", 10))
			d.defense = float(t.get("defense", 10))
			d.speed = float(t.get("speed", 30))
			d.morale = minf(float(t.get("morale", 80)), _rule("max_morale", 100))
			d.experience = float(t.get("experience", 0))
			divisions.append(d)
			_by_id[d.id] = d


func _begin() -> void:
	status = GameTypes.STATUS_RUNNING
	_out.append({"type": Protocol.GAME_STARTED, "game_id": GAME_ID, "tick": tick, "state": snapshot()})


# --- Client messages -----------------------------------------------------------

func handle(player_id: String, msg: Dictionary) -> Array:
	var request_id := str(msg.get("request_id", ""))
	var msg_type := str(msg.get("type", ""))
	if msg_type == Protocol.READY:
		return []
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
	if order_type == Order.ATTACK:
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
	if _engaged(d) and (order_type == Order.MOVE or order_type == Order.ATTACK):
		return _problem("division_engaged", "En combate solo se puede DEFENDER, RETIRARSE o MANTENER")
	if order_type == Order.MOVE:
		if not has_pos:
			return _problem("target_required", "Falta el destino")
		return _check_position(target_pos)
	if order_type == Order.RETREAT and has_pos:
		return _check_position(target_pos)
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
		_detect_encounters()
		_update_battles()
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
		if order.has("target_position"):
			d.destination = Protocol.vec_from(order["target_position"])
		_refresh_state(d, "order", true)
	_pending.clear()


func _speed_multiplier(d: SimDivision) -> float:
	var min_factor := _rule("min_fatigue_speed_factor", 0.6)
	var m := 1.0 - (1.0 - min_factor) * clampf(d.fatigue, 0.0, 100.0) / 100.0
	if d.state == GameTypes.STATE_RETREATING:
		m *= _rule("retreat_speed_multiplier", 1.2)
	return m


func _update_movement() -> void:
	var engagement := _rule("engagement_range", 60)
	for d in divisions:
		d.moved = 0.0
		if not d.alive() or d.order.is_empty():
			continue
		if _engaged(d) and d.state != GameTypes.STATE_RETREATING:
			continue
		var ot := d.order_type()
		if ot == Order.DEFEND or ot == Order.HOLD:
			continue
		if ot == Order.ATTACK:
			var target: SimDivision = _by_id.get(str(d.order.get("target_division_id", "")))
			if target == null or not target.alive():
				_complete(d, "target_destroyed")
				continue
			if d.position.distance_to(target.position) <= engagement * 0.9:
				continue
			d.destination = target.position
		var res := movement.step(map, d.position, d.destination, d.speed * _speed_multiplier(d), _dt())
		d.position = res["position"]
		d.moved = res["moved"]
		if res["blocked"]:
			_complete(d, "blocked")
		elif res["arrived"] and ot != Order.ATTACK:
			_complete(d, "arrived")


func _complete(d: SimDivision, reason: String) -> void:
	d.order = {}
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
	var engagement := _rule("engagement_range", 60)
	for i in divisions.size():
		var a := divisions[i]
		if not a.alive():
			continue
		for j in range(i + 1, divisions.size()):
			var b := divisions[j]
			if not b.alive() or a.player_id == b.player_id:
				continue
			if a.position.distance_to(b.position) > engagement or _battle_between(a, b):
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
	})
	_refresh_state(attacker, "battle_started", false)
	_refresh_state(defender, "battle_started", false)


func _update_battles() -> void:
	var disengage := _rule("disengage_range", 90)
	var round_ticks := int(rules.get("combat_round_ticks", 10))
	for b in battles.duplicate():
		if not b.active:
			continue
		if not b.attacker.alive() or not b.defender.alive():
			_end_battle(b, "destroyed", _survivor(b.attacker, b.defender))
			continue
		if b.attacker.position.distance_to(b.defender.position) > disengage:
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


func _combatant(d: SimDivision) -> Dictionary:
	var terrain := map.terrain_at(d.position)
	return {
		"unit_count": d.unit_count, "attack": d.attack, "defense": d.defense,
		"morale": d.morale, "experience": d.experience, "fatigue": d.fatigue,
		"terrain_attack": map.terrain.attack(terrain), "terrain_defense": map.terrain.defense(terrain),
		"stance": _stance(d),
	}


func _resolve_round(b: SimBattle) -> void:
	var result := combat.resolve(_combatant(b.attacker), _combatant(b.defender))
	_apply_side(b.attacker, result["a"])
	_apply_side(b.defender, result["b"])
	b.rounds += 1
	b.attacker_losses += int(result["a"]["losses"])
	b.defender_losses += int(result["b"]["losses"])
	_out.append({
		"type": Protocol.BATTLE_UPDATED, "tick": tick, "battle_id": b.id, "round": b.rounds,
		"attacker": _side_report(b.attacker, result["a"]),
		"defender": _side_report(b.defender, result["b"]),
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


func _side_report(d: SimDivision, side: Dictionary) -> Dictionary:
	return {
		"division_id": d.id, "losses": side["losses"], "unit_count": d.unit_count,
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
		"player_id": d.player_id, "battle_id": battle.id,
	})
	for b in battles:
		if b.active and b.involves(d):
			_end_battle(b, "destroyed", b.opponent(d))


func _rout(d: SimDivision) -> void:
	d.routed = true
	_order_seq += 1
	d.order = {"id": "order-%d" % _order_seq, "type": "retreat", "target_position": Protocol.vec_to(d.home)}
	d.destination = d.home
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
	if ot == Order.MOVE:
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
	}
	if not d.order.is_empty():
		dto["order"] = d.order
		var ot := d.order_type()
		if ot == Order.MOVE or ot == Order.RETREAT:
			dto["path"] = [Protocol.vec_to(d.destination)]
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
