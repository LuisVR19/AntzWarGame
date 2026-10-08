class_name ResourceNodeData
extends RefCounted
## A resource deposit (gold, wood, stone, food) on one grid cell. Pure data;
## its view lives in scripts/units/resource_view.gd.

const GOLD := "GOLD"
const WOOD := "WOOD"
const STONE := "STONE"
const FOOD := "FOOD"

var id := ""
var type := ""
var display_name := ""
var cell := Vector2i.ZERO
var amount := 0
var max_amount := 0
var asset := ""


static func create(p_id: String, p_type: String, def: Dictionary, p_cell: Vector2i, p_amount: int) -> ResourceNodeData:
	var r := ResourceNodeData.new()
	r.id = p_id
	r.type = p_type
	r.display_name = str(def.get("name", p_type))
	r.cell = p_cell
	r.amount = p_amount
	r.max_amount = p_amount
	r.asset = str(def.get("asset", ""))
	return r


func center_grid() -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


func amount_ratio() -> float:
	return float(amount) / float(max_amount) if max_amount > 0 else 0.0
