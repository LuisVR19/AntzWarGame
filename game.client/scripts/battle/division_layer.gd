class_name DivisionLayer
extends Node2D
## Creates, updates and removes DivisionViews to mirror the BattleState.
## Also answers "which division is under this screen point?" for selection.
## Views are children of this node, which is Y-sorted inside World.

const DIVISION_SCENE := preload("res://scenes/units/division_view.tscn")

var debug_enabled := false
var _views: Dictionary = {}  # id -> DivisionView
var _selected: Array[String] = []
var _label_scale := 1.0
var _map: MapData
var _projection: IsoProjection
var _config: VisualConfig


func setup(projection: IsoProjection, config: VisualConfig) -> void:
	_projection = projection
	_config = config
	for view in _views.values():
		view.setup(projection, config)


func set_map(map: MapData) -> void:
	_map = map


func views() -> Array:
	return _views.values()


func selected_count() -> int:
	return _selected.size()


func view(id: String) -> DivisionView:
	return _views.get(id)


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


## ID of the alive division drawn under `screen_point`, or "".
func pick(screen_point: Vector2) -> String:
	var best := ""
	var best_score := INF
	for view in _views.values():
		var v := view as DivisionView
		var score := v.hit_test(screen_point)
		if score < best_score:
			best = v.division_id()
			best_score = score
	return best


func _apply(d: DivisionData, state: BattleState, local_player_id: String) -> void:
	var view: DivisionView = _views.get(d.id)
	if view == null:
		view = DIVISION_SCENE.instantiate() as DivisionView
		view.name = d.id
		add_child(view)
		_views[d.id] = view
		if _projection != null:
			view.setup(_projection, _config)
		view.set_label_scale(_label_scale)
	view.apply(d, state.side_of(d.player_id), d.player_id == local_player_id)
	view.set_selected(_selected.has(d.id))
	view.set_debug_lines(_debug_lines(d))


## Route to draw for each division (world units): the server path if any,
## otherwise the order target (position or target division).
func _update_routes(state: BattleState) -> void:
	for id in _views.keys():
		var view: DivisionView = _views[id]
		var d := view.data
		var points := PackedVector2Array()
		if d != null and d.is_alive() and d.order != null:
			if d.order.type == Order.ATTACK or d.order.type == Order.MERGE:
				var target := state.get_division(d.order.target_division_id)
				if target != null and target.is_alive():
					points = d.path.duplicate()
					points.append(target.position)
			elif not d.path.is_empty():
				points = d.path
			elif d.order.has_target_position:
				points.append(d.order.target_position)
		view.route_world = points


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
	var cell := _map.cell_of(d.position) if _map != null else Vector2i.ZERO
	return PackedStringArray([
		"%s [%s]" % [d.id, d.player_id],
		"pos (%d, %d) celda (%d, %d)" % [roundi(d.position.x), roundi(d.position.y), cell.x, cell.y],
		"estado %s" % d.state,
		"orden %s" % order_text,
		"terreno %s" % terrain,
	])
