class_name NetworkManager
extends Node
## Owns the WebSocket: connect, disconnect, send and receive JSON messages.
## Knows nothing about the game; scenes never touch the socket directly.

signal connected
signal disconnected(code: int, reason: String)
signal message_received(message: Dictionary)

var _socket := WebSocketPeer.new()
var _last_state := WebSocketPeer.STATE_CLOSED
var _request_seq := 0


func connect_to(url: String) -> Error:
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(url)
	if err != OK:
		push_warning("NetworkManager: cannot connect to %s (error %d)" % [url, err])
		return err
	_last_state = WebSocketPeer.STATE_CONNECTING
	return OK


func disconnect_from_server(code := 1000, reason := "") -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close(code, reason)


func is_open() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


## Serializes and sends a message. Adds a request_id if missing and
## returns it so callers can correlate errors.
func send_message(message: Dictionary) -> String:
	if not is_open():
		push_warning("NetworkManager: not connected, message dropped: %s" % message.get("type", "?"))
		return ""
	if not message.has("request_id"):
		_request_seq += 1
		message["request_id"] = "req-%d" % _request_seq
	_socket.send_text(JSON.stringify(message))
	return str(message["request_id"])


func _process(_delta: float) -> void:
	if _last_state == WebSocketPeer.STATE_CLOSED:
		return
	_socket.poll()
	var current := _socket.get_ready_state()
	if current != _last_state:
		if current == WebSocketPeer.STATE_OPEN:
			connected.emit()
		elif current == WebSocketPeer.STATE_CLOSED:
			_last_state = current
			disconnected.emit(_socket.get_close_code(), _socket.get_close_reason())
			return
		_last_state = current
	while current == WebSocketPeer.STATE_OPEN and _socket.get_available_packet_count() > 0:
		var text := _socket.get_packet().get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			message_received.emit(parsed)
		else:
			push_warning("NetworkManager: ignoring non-object message: %s" % text)
