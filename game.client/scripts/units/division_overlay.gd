class_name DivisionOverlay
extends Node2D
## Floating info above a division: name, approximate size, strength bar and
## morale bar; plus debug lines below it when debug mode is on.
## Its scale is set inversely to the camera zoom so text stays readable.

const WIDTH := 110.0
const BAR_HEIGHT := 4.0
const TOP := -(DivisionShape.RADIUS + 40.0)

var _title := ""
var _units := ""
var _strength := 1.0
var _morale := 1.0
var _alive := true
var _color := Color.WHITE
var _debug_lines: PackedStringArray = PackedStringArray()


func configure(data: DivisionData, side_color: Color) -> void:
	_title = data.display_name
	_units = format_units(data.unit_count)
	_strength = data.strength_ratio()
	_morale = clampf(data.morale / 100.0, 0.0, 1.0)
	_alive = data.is_alive()
	_color = side_color
	queue_redraw()


func set_debug_lines(lines: PackedStringArray) -> void:
	_debug_lines = lines
	queue_redraw()


## "~3k", "~2.4k", "~850"
static func format_units(count: int) -> String:
	if count >= 1000:
		return "~%.1fk" % (count / 1000.0)
	return "~%d" % count


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var left := -WIDTH * 0.5
	var title_color := _color.lightened(0.4) if _alive else Palette.DESTROYED
	_text(font, Vector2(left, TOP), _title, 13, title_color)
	if _alive:
		_text(font, Vector2(left, TOP + 13), _units, 11, Palette.TEXT_DIM)
		var strength_color := Palette.BAR_STRENGTH.lerp(Palette.BAR_STRENGTH_LOW, 1.0 - _strength)
		_bar(Vector2(left + 15, TOP + 17), _strength, strength_color)
		_bar(Vector2(left + 15, TOP + 17 + BAR_HEIGHT + 2), _morale, Palette.BAR_MORALE)
	var y := DivisionShape.RADIUS + 26.0
	for line in _debug_lines:
		_text(font, Vector2(left - 20, y), line, 10, Palette.TEXT)
		y += 11.0


func _text(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	var width := WIDTH + (40.0 if size <= 10 else 0.0)
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, width, size, Palette.TEXT_SHADOW)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


func _bar(pos: Vector2, ratio: float, color: Color) -> void:
	var w := WIDTH - 30.0
	draw_rect(Rect2(pos, Vector2(w, BAR_HEIGHT)), Palette.BAR_BACK)
	draw_rect(Rect2(pos, Vector2(w * clampf(ratio, 0.0, 1.0), BAR_HEIGHT)), color)
