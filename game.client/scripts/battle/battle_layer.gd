class_name BattleLayer
extends Node2D
## Effects layer: a pulsing marker where each active battle takes place and
## the acid shots of archers. Drawn above the World objects.

const MARKER_RADIUS := 50.0  # world units
const VOLLEY_SECONDS := 0.6
const VOLLEY_ARC := 40.0  # screen pixels

var _battles: Array = []
var _time := 0.0
var _projection: IsoProjection
var _volleys: Array = []  # [{from, to, age}] in screen space


func setup(projection: IsoProjection) -> void:
	_projection = projection
	queue_redraw()


func sync_battles(battles: Array) -> void:
	_battles = battles.duplicate()
	queue_redraw()


## Shows an acid shot flying from `from` to `to` (world units).
func add_volley(from: Vector2, to: Vector2) -> void:
	if _projection != null:
		_volleys.append({"from": _projection.world_to_screen(from), "to": _projection.world_to_screen(to), "age": 0.0})


func _process(delta: float) -> void:
	if _battles.is_empty() and _volleys.is_empty():
		return
	_time += delta
	for v in _volleys:
		v["age"] += delta
	_volleys = _volleys.filter(func(v: Dictionary) -> bool: return v["age"] < VOLLEY_SECONDS)
	queue_redraw()


func _draw() -> void:
	if _projection == null:
		return
	for v in _volleys:
		var t: float = v["age"] / VOLLEY_SECONDS
		for k in 5:
			var progress := clampf(t * 1.25 - k * 0.06, 0.0, 1.0)
			var p: Vector2 = (v["from"] as Vector2).lerp(v["to"], progress) + Vector2(0, -sin(progress * PI) * VOLLEY_ARC)
			draw_circle(p, 2.6 - k * 0.3, Palette.ACID)
	var pulse := 1.0 + 0.12 * sin(_time * 6.0)
	var radii := _projection.ground_radii(MARKER_RADIUS) * pulse
	for battle in _battles:
		var center := _projection.world_to_screen(battle["position"])
		PlaceholderPainter.ellipse(self, center, radii, Color(Palette.BATTLE, 0.12))
		PlaceholderPainter.ellipse_outline(self, center, radii, Color(Palette.BATTLE, 0.7), 2.0)
		# Crossed "swords" above the fight.
		var top := center - Vector2(0, 30)
		var s := 10.0
		draw_line(top + Vector2(-s, -s), top + Vector2(s, s), Palette.BATTLE, 3.0)
		draw_line(top + Vector2(s, -s), top + Vector2(-s, s), Palette.BATTLE, 3.0)
