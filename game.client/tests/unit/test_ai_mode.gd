extends "res://tests/framework/test_case.gd"
## "Jugar contra IA": protocol message, NetworkGameState in AI mode and the
## main menu button. No server needed: the socket is replaced by a fake.


## Records the messages instead of sending them over a WebSocket.
class FakeNet extends NetworkManager:
	var sent: Array[Dictionary] = []
	var closed := false

	func send_message(message: Dictionary) -> String:
		sent.append(message)
		return "req-%d" % sent.size()

	func disconnect_from_server(_code := 1000, _reason := "") -> void:
		closed = true


func _ai_source() -> Array:
	var src := NetworkGameState.new("ws://127.0.0.1:8080/ws", "Ana", "", true)
	var net := FakeNet.new()
	src._net = net
	return [src, net]


func test_create_ai_game_message() -> bool:
	check_eq(Protocol.create_ai_game("Ana"), {"type": "create_ai_game", "player_name": "Ana"}, "create_ai_game")
	return done()


func test_ai_source_requests_an_ai_game_on_connect() -> bool:
	var pair := _ai_source()
	var src: NetworkGameState = pair[0]
	var net: FakeNet = pair[1]
	src._on_connected()
	check_eq(net.sent.size(), 1, "una sola solicitud")
	check_eq(net.sent[0]["type"], Protocol.CREATE_AI_GAME, "pide una partida contra la IA")
	check_eq(net.sent[0]["player_name"], "Ana", "con el nombre del jugador")
	check(src.needs_ready(), "el jugador pulsa ¡Listo! como en una partida normal")
	check(src.source_name().contains("IA"), "la fuente indica el modo IA")
	check(src.loading_text().contains("IA"), "texto de carga específico")
	var normal := NetworkGameState.new("ws://x", "Ana", "")
	var normal_net := FakeNet.new()
	normal._net = normal_net
	normal._on_connected()
	check_eq(normal_net.sent[0]["type"], Protocol.CREATE_GAME, "el modo multijugador sigue enviando create_game")
	src.free()
	normal.free()
	normal_net.free()
	net.free()
	return done()


func test_errors_before_the_session_are_reported_as_connection_failures() -> bool:
	var pair := _ai_source()
	var src: NetworkGameState = pair[0]
	var net: FakeNet = pair[1]
	var lost := []
	var rejected := []
	src.connection_lost.connect(func(reason: String) -> void: lost.append(reason))
	src.order_rejected.connect(func(code: String, _m: String) -> void: rejected.append(code))
	src._handle_message({"type": "error", "code": "create_failed", "message": "server is at maximum game capacity"})
	check_eq(lost.size(), 1, "error de creación -> connection_lost")
	check(lost[0].contains("no pudo crear la partida"), "mensaje comprensible")
	check(rejected.is_empty(), "no se trata como orden rechazada")
	check(net.closed, "se cierra la conexión")
	src._on_disconnected(1000, "")
	check_eq(lost.size(), 1, "el cierre posterior no repite el aviso")
	src.free()
	net.free()

	pair = _ai_source()
	src = pair[0]
	net = pair[1]
	lost.clear()
	src.connection_lost.connect(func(reason: String) -> void: lost.append(reason))
	src.order_rejected.connect(func(code: String, _m: String) -> void: rejected.append(code))
	src._on_disconnected(1006, "")
	check(lost[0].contains("No se pudo conectar"), "servidor no disponible: mensaje comprensible")
	src._on_connected()
	src._handle_message({"type": "game_created", "game_id": "game-1", "player_id": "player-2",
		"session_token": "tok", "side": 0, "tick_rate": 10,
		"state": {"tick": 0, "status": "waiting", "divisions": [], "battles": []}})
	src._handle_message({"type": "error", "code": "not_owner", "message": "x"})
	check_eq(rejected, ["not_owner"], "con la sesión iniciada los errores son órdenes rechazadas")
	src.free()
	net.free()
	return done()


func test_lobby_marks_the_bot() -> bool:
	var state := BattleState.new()
	state.set_players([
		{"id": "bot-1", "name": "IA", "side": 1, "ready": true, "connected": true, "bot": true},
		{"id": "player-2", "name": "Ana", "side": 0, "ready": false, "connected": true},
	])
	check(state.get_player("bot-1")["bot"], "el bot se marca en el lobby")
	check(not state.get_player("player-2")["bot"], "el humano no es bot")
	check_eq(state.player_name("bot-1"), "IA", "nombre del bot")
	check_eq(state.side_of("bot-1"), 1, "lado del bot")
	return done()


func test_menu_button_emits_once_until_shown_again() -> bool:
	var menu := MainMenu.new()
	tree.root.add_child(menu)
	var requests := []
	menu.ai_requested.connect(func(url: String, player_name: String) -> void: requests.append([url, player_name]))
	menu._on_ai_pressed()
	menu._on_ai_pressed()
	menu._on_online_pressed()
	check_eq(requests.size(), 1, "una sola solicitud aunque se pulse varias veces")
	check_eq(requests[0], [MainMenu.DEFAULT_URL, "Jugador"], "URL y nombre por defecto")
	menu.hide()
	menu.show()
	menu._on_ai_pressed()
	check_eq(requests.size(), 2, "al volver al menú se puede iniciar otra partida")
	menu.queue_free()
	return done()
