class_name DivisionLayer
extends Node2D
## Creates, updates and removes DivisionViews to mirror the BattleState.
## Also answers "which division is under this point?" for selection.

const DIVISION_SCENE := preload("res://scenes/units/division_view.tscn")

var debug_enabled := false
var _views: Dictionary = {}  # id -> DivisionView
var _selected: Array[String] = []
var _label_scale := 1.0
var _map: MapData


func set_map(map: MapData) -> void:
	_map = map


func sync_state(state: BattleState, local_player_id: String) -> void:
	for d in state.all_divisions():
		_apply(d, state, local_player_id)
	for id in _views.keys():
		if state.get_division(id) == null:
			_views[id].queue_free()
			_views.erase(id)
	_update_routes(state)


func update_division(d: DivisionData, state: BattleState, local_player_id: String) -> void:
	_apply(d, state, local_player_id)
	_update_routes(state)


func set_selection(ids: Array) -> void:
	_selected.assign(ids)
	for id in _views.keys():
		_views[id].set_selected(_selected.has(id))


func set_label_scale(value: float) -> void:
	_label_scale = value
	for view in _views.values():
		view.set_label_scale(value)


func set_debug(enabled: bool, state: BattleState) -> void:
	debug_enabled = enabled
	for d in state.all_divisions():
		var view: DivisionView = _views.get(d.id)
		if view != null:
			view.set_debug_lines(_debug_lines(d))


## Returns the ID of the alive division closest to `world_pos` within its
## pick radius, or "" if none.
func pick(world_pos: Vector2) -> String:
	var best := ""
	var best_dist := INF
	for view in _views.values():
		var v := view as DivisionView
		if v.data == null or not v.data.is_alive():
			continue
		var dist := v.position.distance_to(world_pos)
		if dist <= DivisionView.PICK_RADIUS and dist < best_dist:
			best = v.division_id()
			best_dist = dist
	return best


func _apply(d: DivisionData, state: BattleState, local_player_id: String) -> void:
	var view: DivisionView = _views.get(d.id)
	if view == null:
		view = DIVISION_SCENE.instantiate() as DivisionView
		view.name = d.id
		add_child(view)
		_views[d.id] = view
		view.set_label_scale(_label_scale)
	view.apply(d, state.side_of(d.player_id), d.player_id == local_player_id)
	view.set_selected(_selected.has(d.id))
	view.set_debug_lines(_debug_lines(d))


## Route to draw for each division: the server path if any, otherwise the
## order target (position or target division).
func _update_routes(state: BattleState) -> void:
	for id in _views.keys():
		var view: DivisionView = _views[id]
		var d := view.data
		var points := PackedVector2Array()
		if d != null and d.is_alive() and d.order != null:
			if d.order.type == Order.ATTACK:
				var target := state.get_division(d.order.target_division_id)
				if target != null and target.is_alive():
					points.append(target.position)
			elif not d.path.is_empty():
				points = d.path
			elif d.order.has_target_position:
				points.append(d.order.target_position)
		view.set_order_points(points)


func _debug_lines(d: DivisionData) -> PackedStringArray:
	if not debug_enabled:
		return PackedStringArray()
	var terrain := d.terrain
	if terrain.is_empty() and _map != null:
		terrain = _map.terrain_at(d.position)
	var order_text := "-"
	if d.order != null:
		order_text = d.order.type
		if d.order.type == Order.ATTACK:
			order_text += " -> " + d.order.target_division_id
		elif d.order.has_target_position:
			order_text += " (%d, %d)" % [roundi(d.order.target_position.x), roundi(d.order.target_position.y)]
	return PackedStringArray([
		"%s [%s]" % [d.id, d.player_id],
		"pos (%d, %d)" % [roundi(d.position.x), roundi(d.position.y)],
		"estado %s" % d.state,
		"orden %s" % order_text,
		"terreno %s" % terrain,
	])
