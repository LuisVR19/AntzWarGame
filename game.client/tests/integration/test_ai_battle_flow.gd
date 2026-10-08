extends "res://tests/framework/test_case.gd"
## "Jugar contra IA" through the real scenes: the battle starts with the
## server's messages (fed by a fake socket with the exact shape the Go server
## sends), the player gives orders, the result is shown and the menu comes
## back. Also checks that an unreachable server does not block the client.

var main: Node


## Fake socket: records what the client sends.
class FakeNet extends NetworkManager:
	var sent: Array[Dictionary] = []

	func send_message(message: Dictionary) -> String:
		sent.append(message)
		return "req-%d" % sent.size()

	func disconnect_from_server(_code := 1000, _reason := "") -> void:
		pass


## AI source that "connects" instantly to the fake socket.
class FakeAiSource extends NetworkGameState:
	func _init() -> void:
		super("ws://fake/ws", "Ana", "", true)

	func start() -> void:
		_net = FakeNet.new()
		add_child(_net)
		_on_connected()


func before_each() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	tree.root.add_child(main)


func after_each() -> void:
	if is_instance_valid(main):
		main.queue_free()


func _division(id: String, owner: String, x: float, y: float) -> Dictionary:
	return {"id": id, "player_id": owner, "name": id, "x": x, "y": y, "unit_count": 3000, "max_unit_count": 3000,
		"attack": 10, "defense": 12, "speed": 30, "morale": 80, "experience": 10, "fatigue": 0,
		"state": "idle", "routed": false, "in_battle": false, "terrain": "plain"}


func test_ai_battle_flow() -> bool:
	await wait_frames(2)
	var source := FakeAiSource.new()
	main._start(source)
	await wait_frames(2)
	var battle = main._battle
	var net := source._net as FakeNet
	check_eq(net.sent[0]["type"], Protocol.CREATE_AI_GAME, "se solicita la partida contra la IA")
	check_eq(battle.hud.top_bar._status.text, "Creando partida contra la IA...", "indicador de carga")

	var players := [
		{"id": "bot-1", "name": "IA", "side": 1, "ready": true, "connected": true, "bot": true},
		{"id": "player-2", "name": "Ana", "side": 0, "ready": false, "connected": true},
	]
	source._handle_message({"type": "game_created", "request_id": "req-1", "game_id": "game-ai", "player_id": "player-2",
		"session_token": "tok", "side": 0, "reconnected": false, "tick_rate": 10,
		"map": MapData.from_definitions().to_protocol(),
		"state": {"type": "game_state", "game_id": "game-ai", "status": "waiting", "tick": 0, "divisions": [], "battles": []}})
	source._handle_message({"type": "lobby_updated", "game_id": "game-ai", "status": "waiting", "players": players})
	await wait_frames(1)
	check(battle.hud.top_bar._ready_button.visible, "botón ¡Listo! visible")
	battle.hud.top_bar._on_ready_pressed()
	check_eq(net.sent[-1]["type"], Protocol.READY, "el jugador envía ready")

	var divisions := [_division("division-1", "bot-1", 1800, 450), _division("division-2", "player-2", 200, 450)]
	source._handle_message({"type": "game_started", "game_id": "game-ai", "tick": 0,
		"state": {"type": "game_state", "game_id": "game-ai", "status": "running", "tick": 0, "divisions": divisions, "battles": []}})
	await wait_frames(2)
	check_eq(battle.division_layer._views.size(), 2, "se dibujan las divisiones de ambos ejércitos")
	check(not battle.hud.top_bar._ready_button.visible, "el botón ¡Listo! se oculta")

	# The player controls its own divisions as usual.
	battle.selection.select("division-2")
	battle._on_order_requested(Order.HOLD)
	check_eq(net.sent[-1], {"type": "hold_division", "division_id": "division-2"}, "orden del jugador enviada al servidor")
	# The bot's divisions are enemies: they cannot be commanded.
	battle.selection.select("division-1")
	check(battle._commandable_selection().is_empty(), "las divisiones de la IA no son controlables")

	# The AI moves: the client only renders the authoritative state.
	var moved := divisions.duplicate(true)
	moved[0]["x"] = 1500.0
	moved[0]["state"] = "attacking"
	source._handle_message({"type": "game_state", "game_id": "game-ai", "status": "running", "tick": 30,
		"divisions": moved, "battles": []})
	check_eq(battle.source.state.get_division("division-1").position, Vector2(1500, 450), "estado recibido del servidor")

	source._handle_message({"type": "game_finished", "tick": 900, "winner_player_id": "bot-1",
		"reason": "annihilation", "result": "defeat"})
	await wait_frames(1)
	check(battle.hud.game_over.visible, "panel de resultado")
	check_eq(battle.hud.game_over._title.text, "Derrota", "derrota contra la IA")

	battle.hud.game_over.back_pressed.emit()
	await wait_frames(2)
	check(main.menu.visible, "volver al menú")
	check(main._battle == null, "la batalla se libera")
	return done()


func test_unreachable_server_does_not_block_the_client() -> bool:
	await wait_frames(2)
	main.menu._url.text = "ws://127.0.0.1:1/ws"  # nothing listens there
	main.menu._on_ai_pressed()
	await wait_frames(2)
	var battle = main._battle
	check(battle != null, "se entra en la escena de batalla")
	if battle == null:
		return done()
	var failed := func() -> bool: return battle.hud.game_over.visible
	check(await wait_until(failed, 15.0), "se informa del error de conexión")
	var subtitle: String = battle.hud.game_over._subtitle.text
	check(subtitle.contains("No se pudo conectar"), "mensaje comprensible: %s" % subtitle)
	battle.hud.game_over.back_pressed.emit()
	await wait_frames(2)
	check(main.menu.visible, "se puede volver al menú")
	main.menu._on_ai_pressed()
	await wait_frames(1)
	check(main._battle != null, "y volver a intentarlo")
	main._battle._exit()
	return done()
