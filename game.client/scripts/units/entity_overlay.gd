class_name EntityOverlay
extends Node2D
## Floating info above an entity: title, subtitle and up to a few bars
## (strength, morale, hit points, amount...). Debug lines go below it.
## Its scale is set inversely to the camera zoom so text stays readable.

const WIDTH := 110.0
const TEXT_WIDTH := 220.0  # wider than the bars so long names are not clipped
const BAR_HEIGHT := 4.0

## Y of the title relative to the entity's ground point.
var top := -60.0
var _title := ""
var _subtitle := ""
var _title_color := Color.WHITE
var _bars: Array = []  # [[ratio: float, color: Color], ...]
var _debug_lines: PackedStringArray = PackedStringArray()


func set_info(title: String, subtitle: String, title_color: Color, bars: Array) -> void:
	_title = title
	_subtitle = subtitle
	_title_color = title_color
	_bars = bars
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
	_text(font, top, _title, 13, _title_color)
	if not _subtitle.is_empty():
		_text(font, top + 13, _subtitle, 11, Palette.TEXT_DIM)
	var y := top + 17
	for bar in _bars:
		_bar(Vector2(-WIDTH * 0.5 + 15, y), float(bar[0]), bar[1])
		y += BAR_HEIGHT + 2
	y = 26.0
	for line in _debug_lines:
		_text(font, y, line, 10, Palette.TEXT)
		y += 11.0


func _text(font: Font, y: float, text: String, size: int, color: Color) -> void:
	var origin := Vector2(-TEXT_WIDTH * 0.5, y)
	draw_string(font, origin + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, size, Palette.TEXT_SHADOW)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, size, color)


func _bar(pos: Vector2, ratio: float, color: Color) -> void:
	var w := WIDTH - 30.0
	draw_rect(Rect2(pos, Vector2(w, BAR_HEIGHT)), Palette.BAR_BACK)
	draw_rect(Rect2(pos, Vector2(w * clampf(ratio, 0.0, 1.0), BAR_HEIGHT)), color)
