class_name BattleInput
extends Node2D
## Translates raw input over the battlefield into intents. It does not know
## the game rules; BattleController decides what each intent means.
## Uses _unhandled_input so clicks on UI panels never reach the map.
## Right button: dragging pans the camera (pan_requested); a short click
## without dragging is a contextual order (secondary_clicked).
## Left button: dragging draws a selection box (box_dragged / box_released);
## a short click selects (primary_clicked). Shift adds to the selection.

## Click positions are in screen (isometric canvas) space; BattleController
## converts them to world units with IsoProjection.
signal primary_clicked(screen_position: Vector2, additive: bool)
## Selection box in viewport pixels.
signal box_dragged(from: Vector2, to: Vector2)
signal box_released(from: Vector2, to: Vector2, additive: bool)
signal select_all_pressed
signal secondary_clicked(screen_position: Vector2)
signal pan_requested(screen_delta: Vector2)
signal cancel_pressed
signal order_hotkey_pressed(order_type: String)
signal debug_toggled
signal switch_player_pressed
signal formation_cycle_pressed

## Screen pixels the mouse must travel with the right button held to pan.
var drag_threshold := 6.0
var _right_down := false
var _right_press_position := Vector2.ZERO
var _panning := false
var _left_down := false
var _left_press_position := Vector2.ZERO
var _boxing := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_button(mb)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_on_left_button(mb)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _right_down:
		_on_right_drag(event as InputEventMouseMotion)
		return
	if event is InputEventMouseMotion and _left_down:
		_on_left_drag(event as InputEventMouseMotion)
		return
	if event.is_action_pressed(InputActions.SELECT_ALL):
		select_all_pressed.emit()
		return
	if event.is_action_pressed(InputActions.CANCEL):
		cancel_pressed.emit()
	elif event.is_action_pressed(InputActions.TOGGLE_DEBUG):
		debug_toggled.emit()
	elif event.is_action_pressed(InputActions.SWITCH_PLAYER):
		switch_player_pressed.emit()
	elif event.is_action_pressed(InputActions.CYCLE_FORMATION):
		formation_cycle_pressed.emit()
	else:
		for action in InputActions.ORDER_HOTKEYS.keys():
			if event.is_action_pressed(action):
				order_hotkey_pressed.emit(InputActions.ORDER_HOTKEYS[action])
				break


func _on_right_button(mb: InputEventMouseButton) -> void:
	if mb.pressed:
		_right_down = true
		_panning = false
		_right_press_position = mb.position
	elif _right_down:
		_right_down = false
		if not _panning:
			secondary_clicked.emit(get_global_mouse_position())
		_panning = false


func _on_right_drag(motion: InputEventMouseMotion) -> void:
	if (motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) == 0:
		_right_down = false  # the release happened somewhere we did not see
		_panning = false
		return
	if _panning:
		pan_requested.emit(motion.relative)
	elif motion.position.distance_to(_right_press_position) > drag_threshold:
		_panning = true
		pan_requested.emit(motion.position - _right_press_position)
	get_viewport().set_input_as_handled()


func _on_left_button(mb: InputEventMouseButton) -> void:
	if mb.pressed:
		_left_down = true
		_boxing = false
		_left_press_position = mb.position
	elif _left_down:
		_left_down = false
		if _boxing:
			_boxing = false
			box_released.emit(_left_press_position, mb.position, mb.shift_pressed)
		else:
			primary_clicked.emit(get_global_mouse_position(), mb.shift_pressed)


func _on_left_drag(motion: InputEventMouseMotion) -> void:
	if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		_left_down = false  # the release happened somewhere we did not see
		_boxing = false
		return
	if not _boxing and motion.position.distance_to(_left_press_position) > drag_threshold:
		_boxing = true
	if _boxing:
		box_dragged.emit(_left_press_position, motion.position)
		get_viewport().set_input_as_handled()
