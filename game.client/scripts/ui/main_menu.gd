class_name MainMenu
extends Control
## Entry screen: play locally (mock simulation) or connect to the Go server.

signal local_requested(map_id: String, army_id: String)
signal online_requested(url: String, player_name: String, game_id: String)

const DEFAULT_URL := "ws://127.0.0.1:8080/ws"

var _name: LineEdit
var _url: LineEdit
var _game_id: LineEdit
var _map_select: OptionButton
var _army_select: OptionButton
var _local_info: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	UiStyle.apply_panel(panel, Palette.PANEL_BG, 24.0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := UiStyle.label("AntzGame", 40, Palette.BAR_MORALE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := UiStyle.label("Estrategia 1v1 de ejércitos de hormigas · MVP", 14, Palette.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	box.add_child(HSeparator.new())

	box.add_child(UiStyle.label("Nombre", 13, Palette.TEXT_DIM))
	_name = _line_edit("Jugador")
	box.add_child(_name)

	box.add_child(UiStyle.label("Mapa", 13, Palette.TEXT_DIM))
	_map_select = _catalog_select(Definitions.maps())
	box.add_child(_map_select)
	box.add_child(UiStyle.label("Tamaño del ejército", 13, Palette.TEXT_DIM))
	_army_select = _catalog_select(Definitions.armies())
	box.add_child(_army_select)
	_local_info = UiStyle.label("", 12, Palette.TEXT_DIM)
	_local_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_local_info.custom_minimum_size = Vector2(420, 0)
	box.add_child(_local_info)
	_map_select.item_selected.connect(func(_i: int) -> void: _update_local_info())
	_army_select.item_selected.connect(func(_i: int) -> void: _update_local_info())
	_update_local_info()

	var local := UiStyle.button("Partida local (sin servidor)")
	local.pressed.connect(func() -> void: local_requested.emit(_selected(_map_select), _selected(_army_select)))
	box.add_child(local)
	box.add_child(UiStyle.label("Un solo jugador controla ambos ejércitos (Tab para cambiar).", 12, Palette.TEXT_DIM))

	box.add_child(HSeparator.new())
	box.add_child(UiStyle.label("Servidor Go (WebSocket)", 13, Palette.TEXT_DIM))
	_url = _line_edit(DEFAULT_URL)
	box.add_child(_url)
	_game_id = _line_edit("")
	_game_id.placeholder_text = "ID de partida (vacío = crear una nueva)"
	box.add_child(_game_id)
	var online := UiStyle.button("Conectar")
	online.pressed.connect(_on_online_pressed)
	box.add_child(online)


## OptionButton with one item per catalog entry; the id is the item metadata.
func _catalog_select(catalog: Dictionary) -> OptionButton:
	var select := OptionButton.new()
	select.custom_minimum_size = Vector2(0, 32)
	for id in catalog.keys():
		select.add_item(str(catalog[id].get("name", id)))
		select.set_item_metadata(select.item_count - 1, id)
	return select


func _selected(select: OptionButton) -> String:
	return str(select.get_item_metadata(select.selected)) if select.selected >= 0 else ""


func _update_local_info() -> void:
	var map: Dictionary = Definitions.maps().get(_selected(_map_select), {})
	var army: Dictionary = Definitions.armies().get(_selected(_army_select), {})
	_local_info.text = "%s\nEjército: %s" % [str(map.get("description", "")), str(army.get("description", ""))]


func _line_edit(text: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(0, 32)
	return e


func _on_online_pressed() -> void:
	var player_name := _name.text.strip_edges()
	if player_name.is_empty():
		player_name = "Jugador"
	online_requested.emit(_url.text.strip_edges(), player_name, _game_id.text.strip_edges())
