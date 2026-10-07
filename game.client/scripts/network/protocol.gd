class_name Protocol
extends RefCounted
## JSON protocol shared with game.server (see game.server/README.md).
## Every message is a flat object with a "type" field.

# Client -> server
const CREATE_GAME := "create_game"
const JOIN_GAME := "join_game"
const READY := "ready"
const MOVE_DIVISION := "move_division"
const ATTACK_DIVISION := "attack_division"
const DEFEND_DIVISION := "defend_division"
const RETREAT_DIVISION := "retreat_division"
const HOLD_DIVISION := "hold_division"

# Server -> client
const GAME_CREATED := "game_created"
const GAME_JOINED := "game_joined"
const LOBBY_UPDATED := "lobby_updated"
const GAME_STARTED := "game_started"
const GAME_STATE := "game_state"
const ORDER_ACCEPTED := "order_accepted"
const DIVISION_UPDATED := "division_updated"
const BATTLE_STARTED := "battle_started"
const BATTLE_UPDATED := "battle_updated"
const BATTLE_ENDED := "battle_ended"
const DIVISION_DESTROYED := "division_destroyed"
const GAME_FINISHED := "game_finished"
const ERROR := "error"


static func create_game(player_name: String) -> Dictionary:
	return {"type": CREATE_GAME, "player_name": player_name}


static func join_game(game_id: String, player_name: String, session_token := "") -> Dictionary:
	var msg := {"type": JOIN_GAME, "game_id": game_id, "player_name": player_name}
	if not session_token.is_empty():
		msg["session_token"] = session_token
	return msg


static func ready_message(is_ready: bool) -> Dictionary:
	return {"type": READY, "ready": is_ready}


static func vec_from(raw: Variant) -> Vector2:
	if raw is Dictionary:
		return Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)))
	return Vector2.ZERO


static func vec_to(v: Vector2) -> Dictionary:
	return {"x": v.x, "y": v.y}
