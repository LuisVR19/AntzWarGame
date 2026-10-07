class_name BattleLayer
extends Node2D
## Draws a pulsing marker where each active battle takes place.

var _battles: Array = []
var _time := 0.0


func sync_battles(battles: Array) -> void:
	_battles = battles.duplicate()
	queue_redraw()


func _process(delta: float) -> void:
	if _battles.is_empty():
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	for battle in _battles:
		var center: Vector2 = battle["position"]
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		draw_circle(center, 50.0 + pulse * 6.0, Color(Palette.BATTLE, 0.12))
		draw_arc(center, 50.0 + pulse * 6.0, 0.0, TAU, 48, Color(Palette.BATTLE, 0.7), 2.0)
		# Crossed "swords".
		var s := 12.0
		draw_line(center + Vector2(-s, -s), center + Vector2(s, s), Palette.BATTLE, 3.0)
		draw_line(center + Vector2(s, -s), center + Vector2(-s, s), Palette.BATTLE, 3.0)
