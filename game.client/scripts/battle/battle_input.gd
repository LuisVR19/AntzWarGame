class_name BattleInput
extends Node2D
## Translates raw input over the battlefield into intents. It does not know
## the game rules; BattleController decides what each intent means.
## Uses _unhandled_input so clicks on UI panels never reach the map.

signal primary_clicked(world_position: Vector2)
signal secondary_clicked(world_position: Vector2)
signal cancel_pressed
signal order_hotkey_pressed(order_type: String)
signal debug_toggled
signal switch_player_pressed


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			primary_clicked.emit(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			secondary_clicked.emit(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.CANCEL):
		cancel_pressed.emit()
	elif event.is_action_pressed(InputActions.TOGGLE_DEBUG):
		debug_toggled.emit()
	elif event.is_action_pressed(InputActions.SWITCH_PLAYER):
		switch_player_pressed.emit()
	else:
		for action in InputActions.ORDER_HOTKEYS.keys():
			if event.is_action_pressed(action):
				order_hotkey_pressed.emit(InputActions.ORDER_HOTKEYS[action])
				break
