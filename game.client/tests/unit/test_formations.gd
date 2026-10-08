extends "res://tests/framework/test_case.gd"
## Formations: data, blow geometry, combat effects and the size of divisions.

var combat := CombatResolver.new(Definitions.rules()["combat"])


## A combatant with equal base stats, in `formation`, hit on `side` by an
## enemy in `enemy` formation.
func _fighter(units: int, formation: String, enemy: String, side := Formations.FRONT) -> Dictionary:
	return {
		"unit_count": units, "attack": 10.0, "defense": 10.0, "morale": 100.0,
		"experience": 0.0, "fatigue": 0.0, "terrain_attack": 1.0, "terrain_defense": 1.0,
		"stance": CombatResolver.STANCE_HOLDING,
		"formation_attack": Formations.attack_multiplier(formation, enemy),
		"formation_defense": Formations.defense_multiplier(formation, side),
		"frontage": int(Formations.stat(formation, "frontage", float(units))),
	}


func test_definitions_are_complete() -> bool:
	check_eq(Formations.ids().size(), 5, "cinco formaciones")
	for id in Formations.ids():
		for key in ["name", "attack", "defense_front", "defense_flank", "defense_rear", "speed", "frontage", "turn_rate"]:
			check(Formations.get_def(id).has(key), "%s define %s" % [id, key])
	check_eq(Formations.next(Formations.COLUMN), Formations.LINE, "el ciclo vuelve al principio")
	return done()


func test_exposure_sectors() -> bool:
	check_eq(Formations.exposure(0.0, Vector2(1, 0)), Formations.FRONT, "de frente")
	check_eq(Formations.exposure(0.0, Vector2(1, 1)), Formations.FRONT, "45 grados sigue siendo frente")
	check_eq(Formations.exposure(0.0, Vector2(0, 1)), Formations.FLANK, "de costado")
	check_eq(Formations.exposure(0.0, Vector2(-1, 1)), Formations.REAR, "135 grados = retaguardia")
	check_eq(Formations.exposure(PI, Vector2(1, 0)), Formations.REAR, "mirando al oeste, golpe desde el este")
	return done()


func test_shield_wall_strong_front_weak_flanks() -> bool:
	var attacker := _fighter(2000, Formations.LINE, Formations.SHIELD_WALL)
	var front := combat.resolve(attacker, _fighter(2000, Formations.SHIELD_WALL, Formations.LINE, Formations.FRONT))
	var flank := combat.resolve(attacker, _fighter(2000, Formations.SHIELD_WALL, Formations.LINE, Formations.FLANK))
	var line := combat.resolve(attacker, _fighter(2000, Formations.LINE, Formations.LINE, Formations.FRONT))
	check(front["b"]["losses"] < line["b"]["losses"] * 0.7, "de frente el muro sufre mucho menos que una línea")
	check(flank["b"]["losses"] > front["b"]["losses"] * 2, "por el flanco sufre más del doble")
	return done()


func test_wedge_breaks_shield_wall() -> bool:
	var wedge := _fighter(1000, Formations.WEDGE, Formations.SHIELD_WALL)
	var line := _fighter(1000, Formations.LINE, Formations.SHIELD_WALL)
	var wall := _fighter(2000, Formations.SHIELD_WALL, Formations.WEDGE)
	check(combat.resolve(wedge, wall)["b"]["losses"] > combat.resolve(line, wall)["b"]["losses"], "la cuña rompe el muro mejor que la línea")
	var square := _fighter(2000, Formations.SQUARE, Formations.LINE, Formations.REAR)
	var line_rear := _fighter(2000, Formations.LINE, Formations.LINE, Formations.REAR)
	check(combat.defense_power(square) > combat.defense_power(line_rear), "el erizo no tiene retaguardia débil")
	return done()


func test_frontage_limits_big_divisions() -> bool:
	var huge := _fighter(6000, Formations.LINE, Formations.LINE)
	var small := _fighter(2000, Formations.LINE, Formations.LINE)
	var r := combat.resolve(huge, small)
	check_eq(CombatResolver.fighting_units(huge), 2000, "solo lucha el frente de la línea")
	check_eq(r["b"]["losses"], 40, "6000 soldados golpean como 2000: 2000 * 0.02")
	check(r["a"]["morale_delta"] > r["b"]["morale_delta"], "la reserva sí protege la moral de la grande")
	return done()


func test_small_flanker_beats_big_wall_exchange() -> bool:
	# 1500 in a wedge hitting the flank of 3000 in a shield wall.
	var wedge := _fighter(1500, Formations.WEDGE, Formations.SHIELD_WALL, Formations.FRONT)
	var wall := _fighter(3000, Formations.SHIELD_WALL, Formations.WEDGE, Formations.FLANK)
	var r := combat.resolve(wedge, wall)
	check(r["b"]["losses"] > r["a"]["losses"], "la pequeña bien colocada causa más bajas de las que recibe")
	return done()


func test_division_size_grows_with_soldiers() -> bool:
	var c := VisualConfig.new()
	var r1 := DivisionView.size_radius(c, 1000)
	var r2 := DivisionView.size_radius(c, 2000)
	var r4 := DivisionView.size_radius(c, 4000)
	check(r1 < r2 and r2 < r4, "más soldados = más grande")
	check_near(r2, c.unit_radius, 0.01, "tamaño de referencia")
	check_near(r4 / r2, pow(2.0, c.unit_size_exponent), 0.01, "doble de soldados = radio x 2^exponente")
	check_eq(DivisionView.size_radius(c, 1), c.unit_radius_min, "tamaño mínimo")
	check_eq(DivisionView.size_radius(c, 1000000), c.unit_radius_max, "tamaño máximo")
	return done()
