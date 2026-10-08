class_name MapObjectLayer
extends Node2D
## Views of static map objects (buildings or resources). `view_scene` must
## implement setup(data, projection, config), entity_id(), set_selected(),
## set_label_scale() and hit_test(screen_point).

@export var view_scene: PackedScene

var _views: Dictionary = {}  # id -> view


func setup(items: Array, projection: IsoProjection, config: VisualConfig) -> void:
	for view in _views.values():
		remove_child(view)
		view.free()
	_views.clear()
	for item in items:
		var view = view_scene.instantiate()
		add_child(view)
		view.setup(item, projection, config)
		_views[view.entity_id()] = view


func view(id: String) -> Node2D:
	return _views.get(id)


func count() -> int:
	return _views.size()


func set_selection(ids: Array) -> void:
	for id in _views.keys():
		_views[id].set_selected(ids.has(id))


func set_label_scale(value: float) -> void:
	for view in _views.values():
		view.set_label_scale(value)


## ID of the object under a screen point, or "".
func pick(screen_point: Vector2) -> String:
	var best := ""
	var best_score := INF
	for id in _views.keys():
		var score: float = _views[id].hit_test(screen_point)
		if score < best_score:
			best = id
			best_score = score
	return best
