class_name UiStyle
extends RefCounted
## Small factory helpers so every UI component looks consistent without a
## Theme resource (which can be added later in the editor).


static func panel_style(bg := Palette.PANEL_BG, margin := 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(margin)
	return sb


static func apply_panel(panel: Control, bg := Palette.PANEL_BG, margin := 10.0) -> void:
	panel.add_theme_stylebox_override("panel", panel_style(bg, margin))


static func label(text := "", size := 14, color := Palette.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, min_width := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 32)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func format_time(seconds: float) -> String:
	var total := maxi(int(seconds), 0)
	return "%02d:%02d" % [total / 60, total % 60]
