class_name SelectionManager
extends Node
## Keeps the selected IDs: several divisions (box selection, Shift+click,
## Ctrl+A) or one building/resource. The first one is the "primary": its
## details are shown in the panel.

signal selection_changed(ids: Array)

var _ids: Array[String] = []


func select(id: String) -> void:
	select_many([id])


## Replaces the selection; the first id becomes the primary one.
func select_many(new_ids: Array) -> void:
	var unique: Array[String] = []
	for id in new_ids:
		if not unique.has(str(id)):
			unique.append(str(id))
	if unique == _ids:
		return
	_ids = unique
	selection_changed.emit(ids())


## Adds the id, or removes it if it was already selected.
func toggle(id: String) -> void:
	var next: Array = _ids.duplicate()
	if next.has(id):
		next.erase(id)
	else:
		next.append(id)
	if next.is_empty():
		clear()
	else:
		select_many(next)


func clear() -> void:
	if _ids.is_empty():
		return
	_ids.clear()
	selection_changed.emit(ids())


func primary() -> String:
	return _ids[0] if not _ids.is_empty() else ""


func ids() -> Array[String]:
	return _ids.duplicate()


func count() -> int:
	return _ids.size()


func is_selected(id: String) -> bool:
	return _ids.has(id)
