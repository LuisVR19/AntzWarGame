class_name EntityVisual
extends Node2D
## Body of a map entity. Draws `texture` when an asset exists; otherwise
## calls `painter` (a PlaceholderPainter function). The node origin is the
## entity's ground point, which is also its depth-sorting point.

var texture: Texture2D
## On-screen width of the texture; its bottom-center goes on texture_anchor.
var texture_width := 64.0
var texture_anchor := Vector2.ZERO
var tint := Color.WHITE
var painter: Callable  # func(canvas: CanvasItem) -> void


func _draw() -> void:
	if texture != null:
		PlaceholderPainter.texture_on_ground(self, texture, texture_width, texture_anchor, tint)
	elif painter.is_valid():
		painter.call(self)
