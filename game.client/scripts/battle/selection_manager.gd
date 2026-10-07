class_name SelectionManager
extends Node
## Keeps the selected division IDs. Single selection for the MVP; the API is
## list-based so multiple selection can be added without changing callers.

signal selection_changed(ids: Array)

var _ids: Array[String] = []


func select(id: String) -> void:
	if _ids.size() == 1 and _ids[0] == id:
		return
	_ids = [id]
	selection_changed.emit(ids())


func clear() -> void:
	if _ids.is_empty():
		return
	_ids.clear()
	selection_changed.emit(ids())


func primary() -> String:
	return _ids[0] if not _ids.is_empty() else ""


func ids() -> Array[String]:
	return _ids.duplicate()


func is_selected(id: String) -> bool:
	return _ids.has(id)
