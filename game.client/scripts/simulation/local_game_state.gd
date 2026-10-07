class_name LocalGameState
extends GameStateSource
## Game source that runs LocalGameSimulation in-process (no server needed).
## Messages go through the same _handle_message() as the network source.
## Hot-seat: the controlled player can be switched to test both armies.

const MAX_STEPS_PER_FRAME := 5

var _sim: LocalGameSimulation
var _accumulator := 0.0
var _tick_interval := 0.1


func start() -> void:
	var rules := Definitions.rules()
	_sim = LocalGameSimulation.new(rules, MapData.from_definitions(), Definitions.army())
	_tick_interval = 1.0 / float(_sim.tick_rate)
	_deliver(_sim.joined_message(LocalGameSimulation.PLAYER_1))
	_deliver(_sim.start())


func stop() -> void:
	_sim = null


func source_name() -> String:
	return "Simulación local"


func can_switch_player() -> bool:
	return true


func switch_controlled_player() -> void:
	if local_player_id == LocalGameSimulation.PLAYER_1:
		local_player_id = LocalGameSimulation.PLAYER_2
	else:
		local_player_id = LocalGameSimulation.PLAYER_1
	session_started.emit(state.game_id, local_player_id)
	state_updated.emit(state)


func _send(msg: Dictionary) -> void:
	if _sim != null:
		_deliver(_sim.handle(local_player_id, msg))


func _process(delta: float) -> void:
	if _sim == null:
		return
	_accumulator += delta
	var steps := 0
	while _accumulator >= _tick_interval and steps < MAX_STEPS_PER_FRAME:
		_accumulator -= _tick_interval
		_deliver(_sim.step())
		steps += 1
	if steps == MAX_STEPS_PER_FRAME:
		_accumulator = 0.0  # avoid a spiral of death after a long frame


func _deliver(messages: Variant) -> void:
	if messages is Dictionary:
		_handle_message(messages)
	elif messages is Array:
		for msg in messages:
			_handle_message(msg)
