extends Node
## Application entry: shows the menu and swaps in the battle scene with the
## chosen game source (local simulation or Go server).

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")

var _battle: BattleController

@onready var menu: MainMenu = $MainMenu


func _ready() -> void:
	menu.local_requested.connect(_start_local)
	menu.online_requested.connect(_start_online)


func _start_local(map_id: String, army_id: String) -> void:
	var source := LocalGameState.new()
	source.map_id = map_id
	source.army_id = army_id
	_start(source)


func _start_online(url: String, player_name: String, game_id: String) -> void:
	_start(NetworkGameState.new(url, player_name, game_id))


func _start(source: GameStateSource) -> void:
	menu.hide()
	_battle = BATTLE_SCENE.instantiate() as BattleController
	add_child(_battle)
	_battle.exit_requested.connect(_on_exit_requested)
	_battle.start(source)


func _on_exit_requested() -> void:
	_battle.queue_free()
	_battle = null
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	menu.show()
