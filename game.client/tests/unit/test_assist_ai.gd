extends "res://tests/framework/test_case.gd"
## Idle divisions help nearby friends in combat (unless told to HOLD/DEFEND).
## Army: player 1 owns division-1 and division-2, player 2 division-3 and -4.

const P1 := LocalGameSimulation.PLAYER_1
const PAIR := [
	{"name": "A", "offset": {"x": 0, "y": 0}, "unit_count": 3000},
	{"name": "B", "offset": {"x": 0, "y": 300}, "unit_count": 3000},
]


## division-1 fights division-3; division-2 stands at `helper_at`.
func _fight(helper_at: Vector2) -> LocalGameSimulation:
	var rules: Dictionary = Definitions.rules().duplicate(true)
	rules["start_countdown_ticks"] = 0
	var sim := LocalGameSimulation.new(rules, MapData.from_definitions(), PAIR)
	sim.start()
	for entry in [["division-1", Vector2(500, 1100)], ["division-3", Vector2(555, 1100)], ["division-2", helper_at]]:
		sim._by_id[entry[0]].position = entry[1]
		sim._by_id[entry[0]].destination = entry[1]
	return sim


func _run(sim: LocalGameSimulation, ticks: int) -> Array:
	var out := []
	for i in ticks:
		out.append_array(sim.step())
	return out


func test_idle_friend_comes_to_help() -> bool:
	var sim := _fight(Vector2(500, 900))
	var helper = sim._by_id["division-2"]
	var msgs := _run(sim, 10)
	check_eq(sim.battles.size(), 1, "combate entre division-1 y division-3")
	check_eq(helper.order_type(), Order.ATTACK, "la aliada en espera recibe una orden de ataque")
	check_eq(helper.order.get("target_division_id"), "division-3", "contra el enemigo de su compañera")
	check(bool(helper.order.get("auto", false)), "marcada como automática")
	var assisting := false
	for m in msgs:
		if m["type"] == "division_updated" and m.get("reason") == "assisting":
			assisting = true
	check(assisting, "evento 'assisting' para el registro")
	for i in 400:
		sim.step()
		if sim.battles.size() >= 2:
			break
	check_eq(sim.battles.size(), 2, "llega y se une al combate")
	check(sim._engaged(helper), "la ayudante está combatiendo")
	return done()


func test_hold_and_defend_stay_put() -> bool:
	for order in [Order.hold("division-2"), Order.defend("division-2")]:
		var sim := _fight(Vector2(500, 900))
		var helper = sim._by_id["division-2"]
		sim.handle(P1, order.to_message())
		_run(sim, 40)
		check_eq(helper.order_type(), order.type, "%s: mantiene su orden" % order.type)
		check(helper.position.distance_to(Vector2(500, 900)) < 1.0, "%s: no se mueve" % order.type)
	return done()


func test_far_friend_does_not_react() -> bool:
	var sim := _fight(Vector2(500, 500))  # 600 away, beyond assist_radius (350)
	_run(sim, 40)
	check(sim._by_id["division-2"].order.is_empty(), "demasiado lejos para reaccionar")
	return done()


func test_client_sees_automatic_orders() -> bool:
	var order := Order.from_protocol({"type": "attack", "target_division_id": "division-3", "auto": true})
	check(order.automatic, "la orden automática se reconoce en el cliente")
	return done()
