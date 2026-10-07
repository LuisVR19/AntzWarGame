class_name EventLog
extends PanelContainer
## Bottom-left log of game events ("Combate iniciado", ...).

const MAX_ENTRIES := 80

var _text: RichTextLabel
var _entries: PackedStringArray = PackedStringArray()


func _ready() -> void:
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 10.0
	offset_right = 560.0
	offset_top = -190.0
	offset_bottom = -10.0
	UiStyle.apply_panel(self, Palette.PANEL_BG, 8.0)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.add_theme_font_size_override("normal_font_size", 13)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_text)


func add_entry(text: String, color := Palette.LOG_INFO, time_label := "") -> void:
	var prefix := "[color=#888888]%s[/color]  " % time_label if not time_label.is_empty() else ""
	_entries.append("%s[color=#%s]%s[/color]" % [prefix, color.to_html(false), _escape(text)])
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)
		_text.text = "\n".join(_entries)
	else:
		if _entries.size() > 1:
			_text.append_text("\n")
		_text.append_text(_entries[_entries.size() - 1])


func clear() -> void:
	_entries.clear()
	_text.clear()


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
