class_name CombatResolver
extends RefCounted
## Simple deterministic combat used by the local simulation. Same model as
## the Go server's SimpleEngine:
##   attack_power  = attack  * morale_mod * terrain_attack  * exp_mod * fatigue_mod * stance
##   defense_power = defense * morale_mod * terrain_defense * exp_mod * fatigue_mod * stance
##   losses(B) = fighting(A) * base_rate * clamp(attack_power(A) / defense_power(B))
## Local-only extras (formations): attack/defense are also multiplied by
## formation_attack / formation_defense, and only `frontage` soldiers fight at
## once (fighting = min(units, frontage)); the rest is a reserve that only
## softens morale losses. Without those keys it behaves like the server.

const STANCE_ATTACKING := "ATTACKING"
const STANCE_DEFENDING := "DEFENDING"  # explicit DEFEND order
const STANCE_HOLDING := "HOLDING"
const STANCE_RETREATING := "RETREATING"

var base_rate := 0.02
var min_ratio := 0.25
var max_ratio := 4.0
var morale_loss_base := 0.5
var morale_loss_per_pct := 1.5
var fatigue_per_round := 1.5
var experience_per_round := 0.4
var defend_bonus := 1.25
var attacking_bonus := 1.1
var retreat_attack := 0.5
var retreat_defense := 0.7
var volley_factor := 0.6


func _init(params: Dictionary = {}) -> void:
	base_rate = float(params.get("base_casualty_rate", base_rate))
	min_ratio = float(params.get("min_ratio", min_ratio))
	max_ratio = float(params.get("max_ratio", max_ratio))
	morale_loss_base = float(params.get("morale_loss_base", morale_loss_base))
	morale_loss_per_pct = float(params.get("morale_loss_per_loss_pct", morale_loss_per_pct))
	fatigue_per_round = float(params.get("fatigue_per_round", fatigue_per_round))
	experience_per_round = float(params.get("experience_per_round", experience_per_round))
	defend_bonus = float(params.get("defend_defense_bonus", defend_bonus))
	attacking_bonus = float(params.get("attacking_attack_bonus", attacking_bonus))
	retreat_attack = float(params.get("retreating_attack_factor", retreat_attack))
	retreat_defense = float(params.get("retreating_defense_factor", retreat_defense))
	volley_factor = float(params.get("volley_casualty_factor", volley_factor))


static func morale_modifier(morale: float) -> float:
	return 0.5 + 0.5 * clampf(morale, 0.0, 100.0) / 100.0


static func experience_modifier(experience: float) -> float:
	return 1.0 + 0.5 * clampf(experience, 0.0, 100.0) / 100.0


static func fatigue_modifier(fatigue: float) -> float:
	return 1.0 - 0.3 * clampf(fatigue, 0.0, 100.0) / 100.0


## `c` = {unit_count, attack, defense, morale, experience, fatigue,
##        terrain_attack, terrain_defense, stance}
func attack_power(c: Dictionary) -> float:
	var v: float = c.attack * morale_modifier(c.morale) * c.terrain_attack \
		* experience_modifier(c.experience) * fatigue_modifier(c.fatigue)
	v *= float(c.get("formation_attack", 1.0))
	if c.stance == STANCE_ATTACKING:
		v *= attacking_bonus
	elif c.stance == STANCE_RETREATING:
		v *= retreat_attack
	return v


func defense_power(c: Dictionary) -> float:
	var v: float = c.defense * morale_modifier(c.morale) * c.terrain_defense \
		* experience_modifier(c.experience) * fatigue_modifier(c.fatigue)
	v *= float(c.get("formation_defense", 1.0))
	if c.stance == STANCE_DEFENDING:
		v *= defend_bonus
	elif c.stance == STANCE_RETREATING:
		v *= retreat_defense
	return v


## Resolves one simultaneous round. Returns {"a": side, "b": side} where
## side = {losses, morale_delta, fatigue_delta, experience_delta, attack, defense}.
func resolve(a: Dictionary, b: Dictionary) -> Dictionary:
	var atk_a := attack_power(a)
	var def_a := defense_power(a)
	var atk_b := attack_power(b)
	var def_b := defense_power(b)
	var loss_b := _casualties(fighting_units(a), atk_a, def_b, int(b.unit_count))
	var loss_a := _casualties(fighting_units(b), atk_b, def_a, int(a.unit_count))
	return {
		"a": _side(int(a.unit_count), loss_a, atk_a, def_a),
		"b": _side(int(b.unit_count), loss_b, atk_b, def_b),
	}


## A ranged volley (archers): only the target suffers, with casualties scaled
## by volley_casualty_factor. Returns the target's side
## {losses, morale_delta, fatigue_delta, experience_delta, attack, defense}.
func resolve_volley(shooter: Dictionary, target: Dictionary) -> Dictionary:
	var atk := attack_power(shooter)
	var def := defense_power(target)
	var losses := _casualties(fighting_units(shooter), atk * volley_factor, def, int(target.unit_count))
	var side := _side(int(target.unit_count), losses, atk, def)
	side["fatigue_delta"] = 0.0
	side["experience_delta"] = 0.0
	return side


## Soldiers that can strike at once: the formation's frontage caps them.
static func fighting_units(c: Dictionary) -> int:
	var units := int(c.unit_count)
	return mini(units, int(c.get("frontage", units)))


func _casualties(attacker_units: int, atk: float, def: float, defender_units: int) -> int:
	if attacker_units <= 0 or defender_units <= 0 or atk <= 0.0:
		return 0
	var ratio := max_ratio
	if def > 0.0:
		ratio = clampf(atk / def, min_ratio, max_ratio)
	var losses := roundi(attacker_units * base_rate * ratio)
	return clampi(losses, 1, defender_units)


func _side(units: int, losses: int, atk: float, def: float) -> Dictionary:
	var loss_pct := 100.0 * losses / maxf(units, 1.0)
	return {
		"losses": losses,
		"morale_delta": -(morale_loss_base + morale_loss_per_pct * loss_pct),
		"fatigue_delta": fatigue_per_round,
		"experience_delta": experience_per_round,
		"attack": atk,
		"defense": def,
	}
