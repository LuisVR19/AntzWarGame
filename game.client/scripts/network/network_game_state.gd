class_name NetworkGameState
extends GameStateSource
## Game source backed by the authoritative Go server.
## Leave game_id empty to create a new match, or set it to join one.

var server_url := ""
var player_name := ""
var game_id_to_join := ""
var _net: NetworkManager


func _init(url := "ws://127.0.0.1:8080/ws", p_name := "Jugador", join_game_id := "") -> void:
	server_url = url
	player_name = p_name
	game_id_to_join = join_game_id


func start() -> void:
	_net = NetworkManager.new()
	_net.name = "NetworkManager"
	add_child(_net)
	_net.connected.connect(_on_connected)
	_net.disconnected.connect(_on_disconnected)
	_net.message_received.connect(_handle_message)
	if _net.connect_to(server_url) != OK:
		connection_lost.emit("No se pudo conectar a %s" % server_url)


func stop() -> void:
	if _net != null:
		_net.disconnect_from_server()


func needs_ready() -> bool:
	return true


func source_name() -> String:
	return "Servidor %s" % server_url


func _send(msg: Dictionary) -> void:
	_net.send_message(msg)


func _on_connected() -> void:
	if not session_token.is_empty():
		_net.send_message(Protocol.join_game(state.game_id, player_name, session_token))
	elif game_id_to_join.is_empty():
		_net.send_message(Protocol.create_game(player_name))
	else:
		_net.send_message(Protocol.join_game(game_id_to_join, player_name))


func _on_disconnected(code: int, reason: String) -> void:
	var text := "Conexión cerrada (código %d)" % code
	if not reason.is_empty():
		text += ": " + reason
	connection_lost.emit(text)
