class_name DivisionData
extends RefCounted
## Client-side snapshot of a division, as received from the game source.
## Pure data: no rendering, no simulation.

var id := ""
var player_id := ""
var display_name := ""
var position := Vector2.ZERO
var unit_count := 0
var max_unit_count := 0
var attack := 0.0  # "fuerza"
var defense := 0.0
var speed := 0.0
var morale := 0.0  # 0..100
var experience := 0.0  # 0..100
var fatigue := 0.0  # 0..100
var state := GameTypes.STATE_IDLE
var order: Order = null
var path: PackedVector2Array = PackedVector2Array()
var routed := false
var in_battle := false
var terrain := ""
var formation := Formations.DEFAULT
var facing := 0.0  # radians, world space
var reforming := false
var unit_type := UnitTypes.DEFAULT
var radius := 0.0  # ground radius in world units (0 = unknown, e.g. Go server)


static func from_protocol(raw: Dictionary) -> DivisionData:
	var d := DivisionData.new()
	d.id = str(raw.get("id", ""))
	d.player_id = str(raw.get("player_id", ""))
	d.display_name = str(raw.get("name", d.id))
	d.position = Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)))
	d.unit_count = int(raw.get("unit_count", 0))
	d.max_unit_count = maxi(int(raw.get("max_unit_count", d.unit_count)), 1)
	d.attack = float(raw.get("attack", 0.0))
	d.defense = float(raw.get("defense", 0.0))
	d.speed = float(raw.get("speed", 0.0))
	d.morale = float(raw.get("morale", 0.0))
	d.experience = float(raw.get("experience", 0.0))
	d.fatigue = float(raw.get("fatigue", 0.0))
	d.state = GameTypes.from_wire(str(raw.get("state", "idle")))
	d.routed = bool(raw.get("routed", false))
	d.in_battle = bool(raw.get("in_battle", false))
	d.terrain = GameTypes.from_wire(str(raw.get("terrain", "")))
	d.formation = GameTypes.from_wire(str(raw.get("formation", GameTypes.to_wire(Formations.DEFAULT))))
	d.facing = float(raw.get("facing", 0.0))
	d.reforming = bool(raw.get("reforming", false))
	d.radius = float(raw.get("radius", 0.0))
	d.unit_type = GameTypes.from_wire(str(raw.get("unit_type", GameTypes.to_wire(UnitTypes.DEFAULT))))
	var order_raw: Variant = raw.get("order")
	if order_raw is Dictionary:
		d.order = Order.from_protocol(order_raw)
		d.order.division_id = d.id
	var path_raw: Variant = raw.get("path")
	if path_raw is Array:
		for p in path_raw:
			d.path.append(Protocol.vec_from(p))
	return d


func is_alive() -> bool:
	return state != GameTypes.STATE_DESTROYED


## Remaining strength in 0..1.
func strength_ratio() -> float:
	return clampf(float(unit_count) / float(max_unit_count), 0.0, 1.0)


func order_type() -> String:
	return order.type if order != null else ""
