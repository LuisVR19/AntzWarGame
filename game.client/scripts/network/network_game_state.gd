class_name NetworkGameState
extends GameStateSource
## Game source backed by the authoritative Go server.
## Leave game_id empty to create a new match, or set it to join one.
## With vs_ai the server creates a match against its bot (create_ai_game).

var server_url := ""
var player_name := ""
var game_id_to_join := ""
var vs_ai := false
var _net: NetworkManager
var _was_connected := false
var _failed := false


func _init(url := "ws://127.0.0.1:8080/ws", p_name := "Jugador", join_game_id := "", p_vs_ai := false) -> void:
	server_url = url
	player_name = p_name
	game_id_to_join = join_game_id
	vs_ai = p_vs_ai


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
	if vs_ai:
		return "Contra la IA · servidor %s" % server_url
	return "Servidor %s" % server_url


func loading_text() -> String:
	return "Creando partida contra la IA..." if vs_ai else "Conectando..."


func _send(msg: Dictionary) -> void:
	_net.send_message(msg)


func _on_connected() -> void:
	_was_connected = true
	if not session_token.is_empty():
		_net.send_message(Protocol.join_game(state.game_id, player_name, session_token))
	elif vs_ai:
		_net.send_message(Protocol.create_ai_game(player_name))
	elif game_id_to_join.is_empty():
		_net.send_message(Protocol.create_game(player_name))
	else:
		_net.send_message(Protocol.join_game(game_id_to_join, player_name))


func _on_disconnected(code: int, reason: String) -> void:
	if _failed:
		return  # the cause was already reported
	if not _was_connected:
		connection_lost.emit("No se pudo conectar con el servidor %s. ¿Está en ejecución?" % server_url)
		return
	var text := "Conexión cerrada (código %d)" % code
	if not reason.is_empty():
		text += ": " + reason
	connection_lost.emit(text)


## An error before game_created/game_joined means the game could not be
## created or joined: report it as a session failure (not as a rejected
## order) and close the connection so the player can go back to the menu.
func _handle_message(msg: Dictionary) -> void:
	if str(msg.get("type", "")) == Protocol.ERROR and local_player_id.is_empty() and not _failed:
		_failed = true
		connection_lost.emit(session_error_text(str(msg.get("code", "")), str(msg.get("message", ""))))
		if _net != null:
			_net.disconnect_from_server()
		return
	super._handle_message(msg)


static func session_error_text(code: String, message: String) -> String:
	match code:
		"create_failed":
			return "El servidor no pudo crear la partida: %s" % message
		"game_not_found":
			return "La partida no existe."
		"game_full":
			return "La partida ya está completa."
		"timeout":
			return "El servidor no respondió a tiempo."
	return "El servidor rechazó la solicitud (%s): %s" % [code, message]
