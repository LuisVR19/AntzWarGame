extends "res://tests/framework/test_case.gd"
## MovementSystem and CombatResolver (local simulation building blocks).

var map: MapData
var movement := MovementSystem.new()


func before_each() -> void:
	map = MapData.from_definitions()


func _combatant(overrides := {}) -> Dictionary:
	var c := {
		"unit_count": 3000, "attack": 10.0, "defense": 10.0, "morale": 100.0,
		"experience": 0.0, "fatigue": 0.0, "terrain_attack": 1.0, "terrain_defense": 1.0,
		"stance": CombatResolver.STANCE_HOLDING,
	}
	c.merge(overrides, true)
	return c


func test_move_on_plain_uses_speed() -> bool:
	var res := movement.step(map, Vector2(500, 1100), Vector2(700, 1100), 30.0, 1.0)
	check_near(res["moved"], 30.0, 0.001, "30 u/s en llanura")
	check(not res["arrived"] and not res["blocked"], "sigue en camino")
	return done()


func test_forest_slows_movement() -> bool:
	var res := movement.step(map, Vector2(450, 200), Vector2(620, 200), 30.0, 1.0)
	check_near(res["moved"], 21.0, 0.001, "bosque x0.7")
	return done()


func test_arrives_without_overshoot() -> bool:
	var res := movement.step(map, Vector2(500, 1100), Vector2(510, 1100), 30.0, 1.0)
	check(res["arrived"], "llega")
	check_eq(res["position"], Vector2(510, 1100), "sin pasarse")
	return done()


func test_water_blocks_movement() -> bool:
	var res := movement.step(map, Vector2(900, 600), Vector2(1100, 600), 1000.0, 1.0)
	check(res["blocked"], "el río bloquea")
	check(map.is_passable(res["position"]), "se detiene en tierra")
	check(res["position"].x < 950.0, "antes del agua")
	return done()


func test_equal_forces_equal_losses() -> bool:
	var combat := CombatResolver.new(Definitions.rules()["combat"])
	var r := combat.resolve(_combatant(), _combatant())
	check_eq(r["a"]["losses"], 60, "3000 * 0.02 * 1")
	check_eq(r["b"]["losses"], 60, "simétrico")
	check(r["a"]["morale_delta"] < 0.0, "la moral baja")
	check(r["a"]["fatigue_delta"] > 0.0, "la fatiga sube")
	check_eq(combat.resolve(_combatant(), _combatant()), r, "determinístico")
	return done()


func test_terrain_and_stance_modifiers() -> bool:
	var combat := CombatResolver.new(Definitions.rules()["combat"])
	var on_hill := _combatant({"terrain_defense": 1.3})
	var r := combat.resolve(_combatant(), on_hill)
	check(r["b"]["losses"] < r["a"]["losses"], "la colina protege al defensor")
	var defending := _combatant({"stance": CombatResolver.STANCE_DEFENDING})
	check(combat.defense_power(defending) > combat.defense_power(_combatant()), "DEFEND aumenta defensa")
	var retreating := _combatant({"stance": CombatResolver.STANCE_RETREATING})
	check(combat.attack_power(retreating) < combat.attack_power(_combatant()), "en retirada ataca peor")
	var low_morale := _combatant({"morale": 20.0})
	check(combat.attack_power(low_morale) < combat.attack_power(_combatant()), "moral baja = menos ataque")
	return done()


func test_losses_are_clamped() -> bool:
	var combat := CombatResolver.new(Definitions.rules()["combat"])
	var r := combat.resolve(_combatant({"attack": 1000.0}), _combatant({"unit_count": 50}))
	check_eq(r["b"]["losses"], 50, "no más bajas que unidades")
	r = combat.resolve(_combatant({"attack": 1000.0}), _combatant())
	check_eq(r["b"]["losses"], 240, "ratio limitado a 4")
	return done()
