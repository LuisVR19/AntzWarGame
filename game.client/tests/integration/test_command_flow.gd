extends "res://tests/framework/test_case.gd"
## Chain of command in the real battle scene, fed with server-shaped
## messages through a fake socket: markers, selecting a commander, its
## panel, pending orders on a division, reassignment and the radii toggle.

const UNIT_TEST := preload("res://tests/unit/test_command_chain.gd")

var main: Node


## Fake socket: records what the client sends.
class FakeNet extends NetworkManager:
	var sent: Array[Dictionary] = []

	func send_message(message: Dictionary) -> String:
		sent.append(message)
		return "req-%d" % sent.size()

	func disconnect_from_server(_code := 1000, _reason := "") -> void:
		pass


## Network source that "connects" instantly to the fake socket.
class FakeSource extends NetworkGameState:
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


func test_command_flow() -> bool:
	await wait_frames(2)
	var source := FakeSource.new()
	main._start(source)
	await wait_frames(2)
	var battle = main._battle
	var net := source._net as FakeNet
	source._handle_message({"type": "game_created", "game_id": "game-1", "player_id": "player-1", "session_token": "tok",
		"side": 0, "tick_rate": 10, "map": MapData.from_definitions().to_protocol(),
		"state": {"type": "game_state", "status": "waiting", "tick": 0, "divisions": [], "battles": []}})
	source._handle_message({"type": "lobby_updated", "status": "waiting", "players": [
		{"id": "player-1", "name": "Ana", "side": 0, "ready": true, "connected": true},
		{"id": "player-2", "name": "IA", "side": 1, "ready": true, "connected": true, "bot": true},
	]})
	source._handle_message({"type": "game_started", "tick": 40, "state": UNIT_TEST.SNAPSHOT})
	await wait_frames(3)

	var layer: CommandLayer = battle.command_layer
	check(layer != null and layer.get_parent() == battle, "capa de mando en la escena de batalla")
	check(battle.hud.division_panel._buttons["ASSIGN"].visible, "botón de reasignar mando con el servidor Go")

	# Click on the commander's marker: it is selected and its panel shown.
	var commander := source.state.get_command("commander-1")
	battle._on_primary_clicked(layer.marker_position(commander))
	await wait_frames(1)
	check_eq(battle.selection.primary(), "commander-1", "clic sobre el marcador selecciona al comandante")
	check_eq(layer.selected_command_id, "commander-1", "el comandante se resalta (radios y enlaces)")
	check(battle.hud.division_panel._info.visible, "panel de mando")
	check_eq(battle.hud.division_panel._title.text, "Infantry Command", "nombre del comandante")
	var panel_text := _info_text(battle.hud.division_panel._info)
	for expected in ["Comandante", "Activo", "350", "Divisiones subordinadas", "1 en rango · 1 fuera"]:
		check(panel_text.contains(expected), "el panel muestra «%s»: %s" % [expected, panel_text])

	# An out-of-range division with an order in transit.
	battle.selection.select("division-2")
	await wait_frames(1)
	var values: Dictionary = battle.hud.division_panel._values
	check(values["command"].visible, "filas de mando visibles para una división propia")
	check(values["command"].text.contains("Infantry Command"), "comandante asignado: %s" % values["command"].text)
	check(values["link"].text.contains("mensajero"), "enlace fuera de rango: %s" % values["link"].text)
	check(values["pending"].text.contains("Defender") and values["pending"].text.contains("5 s"),
		"orden pendiente con ETA: %s" % values["pending"].text)

	# Reassign it: button, then click on a commander marker.
	battle._on_order_requested(battle.ASSIGN_COMMANDER)
	check_eq(battle._command_mode, battle.ASSIGN_COMMANDER, "modo reasignar esperando un comandante")
	battle._on_primary_clicked(layer.marker_position(commander))
	check_eq(net.sent[-1], {"type": "assign_commander", "division_id": "division-2", "commander_id": "commander-1"},
		"solicitud de reasignación al servidor")
	check_eq(battle._command_mode, "", "el modo termina tras el clic")
	# The enemy general cannot take command of own divisions.
	battle.selection.select("division-2")
	battle._on_order_requested(battle.ASSIGN_COMMANDER)
	var sent_before: int = net.sent.size()
	battle._on_primary_clicked(layer.marker_position(source.state.get_command("general-5")))
	check_eq(net.sent.size(), sent_before, "no se puede asignar a un mando enemigo")

	# Enemy division: no command rows.
	battle.selection.select("division-4")
	await wait_frames(1)
	check(not values["command"].visible, "sin datos de mando de divisiones enemigas")

	battle._toggle_command_radii()
	check(layer.show_radii, "[C] muestra los radios de comunicación")
	await wait_frames(2)  # draws markers, radii, messenger and pending marks

	# The server says the commander fell: the client shows it.
	source._handle_message({"type": "command_updated", "tick": 50, "command_id": "commander-1", "player_id": "player-1",
		"role": "commander", "status": "eliminated", "reason": "host_destroyed"})
	check_eq(layer.pick(layer.marker_position(commander)), "", "un mando eliminado deja de dibujarse")
	battle._exit()
	return done()


func _info_text(grid: GridContainer) -> String:
	var parts := PackedStringArray()
	for child in grid.get_children():
		if child is Label:
			parts.append((child as Label).text)
	return " | ".join(parts)
