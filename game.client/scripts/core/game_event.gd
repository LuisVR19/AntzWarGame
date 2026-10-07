class_name GameEvent
extends RefCounted
## A notable thing that happened (order accepted, battle started, ...).
## `type` is the protocol message type; `data` is the raw message.

var type := ""
var tick := 0
var data: Dictionary = {}


static func from_message(msg: Dictionary) -> GameEvent:
	var ev := GameEvent.new()
	ev.type = str(msg.get("type", ""))
	ev.tick = int(msg.get("tick", 0))
	ev.data = msg
	return ev
