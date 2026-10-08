class_name GameStateSource
extends Node
## Abstraction the battle scene talks to. Implementations:
##   - LocalGameState:   in-process mock server (LocalGameSimulation)
##   - NetworkGameState: Go server over WebSocket (NetworkManager)
## Both feed the SAME protocol messages into _handle_message(), so the UI
## behaves identically and one can replace the other without UI changes.

signal session_started(game_id: String, player_id: String)
signal map_received(map: MapData)
signal lobby_changed(players: Array, status: String)
signal state_updated(state: BattleState)
signal division_changed(division: DivisionData, reason: String)
signal game_event(event: GameEvent)
signal order_rejected(code: String, message: String)
signal game_finished(result: String, reason: String, winner_id: String)
signal connection_lost(reason: String)

var state := BattleState.new()
var local_player_id := ""
var session_token := ""
var map_data: MapData = null


## Starts the session (connect, create the local match, ...). Virtual.
func start() -> void:
	pass


## Stops the session and releases resources. Virtual.
func stop() -> void:
	pass


func submit_order(order: Order) -> void:
	_send(order.to_message())


func set_ready(is_ready: bool) -> void:
	_send(Protocol.ready_message(is_ready))


## True when players must press "ready" before the match starts.
func needs_ready() -> bool:
	return false


## Local hot-seat: lets one person control both armies for testing.
func can_switch_player() -> bool:
	return false


func switch_controlled_player() -> void:
	pass


## True if the source implements split/merge (the Go server does not yet).
func supports_split_merge() -> bool:
	return false


## True if the source implements formations (the Go server does not yet).
func supports_formations() -> bool:
	return false


func source_name() -> String:
	return "abstract"


## Status shown while the session is being set up (before the first state).
func loading_text() -> String:
	return "Conectando..."


## Sends a client -> server message. Virtual.
func _send(_msg: Dictionary) -> void:
	push_warning("GameStateSource._send not implemented")


## Applies one server -> client message to `state` and emits signals.
func _handle_message(msg: Dictionary) -> void:
	var type := str(msg.get("type", ""))
	if type == Protocol.GAME_CREATED or type == Protocol.GAME_JOINED:
		local_player_id = str(msg.get("player_id", ""))
		session_token = str(msg.get("session_token", ""))
		state.game_id = str(msg.get("game_id", ""))
		state.tick_rate = int(msg.get("tick_rate", state.tick_rate))
		var map_raw: Variant = msg.get("map")
		if map_raw is Dictionary:
			map_data = MapData.from_protocol(map_raw)
			map_received.emit(map_data)
		var state_raw: Variant = msg.get("state")
		if state_raw is Dictionary:
			state.apply_snapshot(state_raw)
		session_started.emit(state.game_id, local_player_id)
		state_updated.emit(state)
	elif type == Protocol.LOBBY_UPDATED:
		state.set_players(msg.get("players", []))
		state.status = GameTypes.from_wire(str(msg.get("status", "waiting")))
		lobby_changed.emit(state.players, state.status)
	elif type == Protocol.GAME_STARTED:
		var started_raw: Variant = msg.get("state")
		if started_raw is Dictionary:
			state.apply_snapshot(started_raw)
		game_event.emit(GameEvent.from_message(msg))
		state_updated.emit(state)
	elif type == Protocol.GAME_STATE:
		state.apply_snapshot(msg)
		state_updated.emit(state)
	elif type == Protocol.DIVISION_UPDATED:
		var div_raw: Variant = msg.get("division")
		if div_raw is Dictionary:
			var d := DivisionData.from_protocol(div_raw)
			state.upsert_division(d)
			division_changed.emit(d, str(msg.get("reason", "")))
		game_event.emit(GameEvent.from_message(msg))
	elif type == Protocol.DIVISION_SPLIT:
		for key in ["division", "new_division"]:
			var raw: Variant = msg.get(key)
			if raw is Dictionary:
				state.upsert_division(DivisionData.from_protocol(raw))
		game_event.emit(GameEvent.from_message(msg))
		state_updated.emit(state)
	elif type == Protocol.DIVISIONS_MERGED:
		state.remove_division(str(msg.get("merged_division_id", "")))
		var merged_raw: Variant = msg.get("division")
		if merged_raw is Dictionary:
			state.upsert_division(DivisionData.from_protocol(merged_raw))
		game_event.emit(GameEvent.from_message(msg))
		state_updated.emit(state)
	elif type in [Protocol.ORDER_ACCEPTED, Protocol.BATTLE_STARTED, Protocol.BATTLE_UPDATED,
			Protocol.BATTLE_ENDED, Protocol.DIVISION_DESTROYED, Protocol.VOLLEY]:
		game_event.emit(GameEvent.from_message(msg))
	elif type == Protocol.GAME_FINISHED:
		state.status = GameTypes.STATUS_FINISHED
		state.winner_id = str(msg.get("winner_player_id", ""))
		state.finish_reason = str(msg.get("reason", ""))
		var result := "draw"
		if not state.winner_id.is_empty():
			result = "victory" if state.winner_id == local_player_id else "defeat"
		game_event.emit(GameEvent.from_message(msg))
		game_finished.emit(result, state.finish_reason, state.winner_id)
	elif type == Protocol.ERROR:
		order_rejected.emit(str(msg.get("code", "error")), str(msg.get("message", "")))
	else:
		push_warning("GameStateSource: unhandled message type '%s'" % type)
