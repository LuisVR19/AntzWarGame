class_name InputActions
extends RefCounted
## Registers the input actions at runtime so project.godot does not need a
## hand-written [input] section. They can be rebound later in the editor.

const CAM_LEFT := "cam_left"
const CAM_RIGHT := "cam_right"
const CAM_UP := "cam_up"
const CAM_DOWN := "cam_down"
const CANCEL := "cancel"
const TOGGLE_DEBUG := "toggle_debug"
const SWITCH_PLAYER := "switch_player"
const ORDER_MOVE := "order_move"
const ORDER_ATTACK := "order_attack"
const ORDER_DEFEND := "order_defend"
const ORDER_RETREAT := "order_retreat"
const ORDER_HOLD := "order_hold"
const ORDER_SPLIT := "order_split"
const ORDER_MERGE := "order_merge"
const CYCLE_FORMATION := "cycle_formation"
const SELECT_ALL := "select_all"

## Hotkey action -> Order type.
const ORDER_HOTKEYS := {
	ORDER_MOVE: "MOVE",
	ORDER_ATTACK: "ATTACK",
	ORDER_DEFEND: "DEFEND",
	ORDER_RETREAT: "RETREAT",
	ORDER_HOLD: "HOLD",
	ORDER_SPLIT: "SPLIT",
	ORDER_MERGE: "MERGE",
}


static func ensure() -> void:
	_add(CAM_LEFT, [KEY_A, KEY_LEFT])
	_add(CAM_RIGHT, [KEY_D, KEY_RIGHT])
	_add(CAM_UP, [KEY_W, KEY_UP])
	_add(CAM_DOWN, [KEY_S, KEY_DOWN])
	_add(CANCEL, [KEY_ESCAPE])
	_add(TOGGLE_DEBUG, [KEY_F3])
	_add(SWITCH_PLAYER, [KEY_TAB])
	_add(ORDER_MOVE, [KEY_1])
	_add(ORDER_ATTACK, [KEY_2])
	_add(ORDER_DEFEND, [KEY_3])
	_add(ORDER_RETREAT, [KEY_4])
	_add(ORDER_HOLD, [KEY_5])
	_add(ORDER_SPLIT, [KEY_6])
	_add(ORDER_MERGE, [KEY_7])
	_add(CYCLE_FORMATION, [KEY_F])
	if not InputMap.has_action(SELECT_ALL):  # Ctrl+A
		InputMap.add_action(SELECT_ALL)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_A
		ev.ctrl_pressed = true
		InputMap.action_add_event(SELECT_ALL, ev)


static func _add(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
