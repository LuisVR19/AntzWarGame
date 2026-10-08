class_name CommandLayer
extends Node2D
## Chain of command on the map (Go server): a star for each general and a
## diamond for each commander over their host divisions, communication and
## influence radii (selected unit, or all own units with [C]), lines to the
## subordinates of the selected unit, out-of-range / no-command marks and
## pending-order envelopes (with ETA) on own divisions, and the messengers
## travelling to their recipients. Pure presentation: every value comes from
## the server state; nothing here decides when an order is delivered.

## Marker position relative to the host division's ground point (screen px).
const MARKER_OFFSET := Vector2(0, -52)
const MARKER_SIZE := 9.0
const PICK_RADIUS := 14.0
const MARK_OFFSET := Vector2(20, -34)
const FONT_SIZE := 12

## Shows the comm radius of every own active command unit.
var show_radii := false
## Command unit highlighted by the selection ("" = none).
var selected_command_id := ""
var _state: BattleState
var _local_player_id := ""
var _projection: IsoProjection
var _divisions: DivisionLayer


func setup(projection: IsoProjection, division_layer: DivisionLayer) -> void:
	_projection = projection
	_divisions = division_layer
	queue_redraw()


func sync(state: BattleState, local_player_id: String) -> void:
	_state = state
	_local_player_id = local_player_id


func _process(_delta: float) -> void:
	if _state != null and _state.has_chain_of_command():
		queue_redraw()  # follows the interpolated division views


## ID of the command marker under `screen_point`, or "".
func pick(screen_point: Vector2) -> String:
	if _state == null or _projection == null:
		return ""
	var best := ""
	var best_distance := PICK_RADIUS
	for c in _state.all_commands():
		if not c.is_alive():
			continue
		var distance := marker_position(c).distance_to(screen_point)
		if distance <= best_distance:
			best = c.id
			best_distance = distance
	return best


## Screen position of a command unit's marker.
func marker_position(c: CommandData) -> Vector2:
	return _ground_position(c.host_division_id, c.position) + MARKER_OFFSET


func _ground_position(division_id: String, fallback_world: Vector2) -> Vector2:
	if _divisions != null:
		var view := _divisions.view(division_id)
		if view != null:
			return view.position
	return _projection.world_to_screen(fallback_world)


func _draw() -> void:
	if _state == null or _projection == null or not _state.has_chain_of_command():
		return
	for c in _state.all_commands():
		if c.is_alive() and (c.id == selected_command_id or (show_radii and c.is_active() and _is_own(c))):
			_draw_radii(c, c.id == selected_command_id)
	var selected := _state.get_command(selected_command_id)
	if selected != null and selected.is_alive() and _is_own(selected):
		_draw_links(selected)
	for d in _state.all_divisions():
		if d.is_alive() and d.player_id == _local_player_id:
			_draw_division_marks(d)
	for m in _state.messengers:
		_draw_messenger(m)
	for c in _state.all_commands():
		if c.is_alive():
			_draw_marker(c)


func _is_own(c: CommandData) -> bool:
	return c.player_id == _local_player_id


func _side_color(player_id: String) -> Color:
	return Palette.side_color(_state.side_of(player_id))


func _draw_radii(c: CommandData, selected: bool) -> void:
	var center := _ground_position(c.host_division_id, c.position)
	var color := _side_color(c.player_id).lightened(0.3)
	if selected and c.influence_radius > 0.0:
		var radii := _projection.ground_radii(c.influence_radius)
		PlaceholderPainter.ellipse(self, center, radii, Color(color, 0.08), 48)
		PlaceholderPainter.ellipse_outline(self, center, radii, Color(color, 0.35), 1.0)
	if c.comm_radius > 0.0:
		PlaceholderPainter.ellipse_outline(self, center, _projection.ground_radii(c.comm_radius), Color(color, 0.8), 2.0)


func _draw_links(c: CommandData) -> void:
	var from := _ground_position(c.host_division_id, c.position)
	for d in _state.subordinates(c.id):
		if d.id == c.host_division_id:
			continue
		var to := _ground_position(d.id, d.position)
		draw_dashed_line(from, to, _link_color(d.command_link), 2.0, 8.0)


static func _link_color(link: String) -> Color:
	if link == CommandData.LINK_IN_RANGE:
		return Palette.LINK_OK
	if link == CommandData.LINK_OUT_OF_RANGE:
		return Palette.LINK_FAR
	return Palette.LINK_NONE


## Out of range: orange ring with a gap. No command: grey cross.
## Pending order: envelope with the estimated seconds to delivery.
func _draw_division_marks(d: DivisionData) -> void:
	var base := _ground_position(d.id, d.position)
	var mark := base + MARK_OFFSET
	if d.command_link == CommandData.LINK_OUT_OF_RANGE:
		draw_arc(mark, 6.0, 0.6, TAU - 0.6, 16, Palette.LINK_FAR, 2.0)
	elif d.command_link == CommandData.LINK_NO_COMMAND:
		draw_line(mark + Vector2(-5, -5), mark + Vector2(5, 5), Palette.LINK_NONE, 2.0)
		draw_line(mark + Vector2(-5, 5), mark + Vector2(5, -5), Palette.LINK_NONE, 2.0)
	if d.pending_order != null:
		var env := base + Vector2(-MARK_OFFSET.x - 14, MARK_OFFSET.y - 5)
		_draw_envelope(env, Palette.MESSENGER)
		var seconds := ceili(_state.ticks_to_seconds(d.pending_eta_ticks))
		_draw_text(env + Vector2(-2, -4), "%ds" % seconds, Palette.MESSENGER)


func _draw_messenger(m: Dictionary) -> void:
	var at := _projection.world_to_screen(m["position"])
	var recipient := _state.get_division(str(m["division_id"]))
	if recipient != null and recipient.is_alive():
		draw_dashed_line(at, _ground_position(recipient.id, recipient.position), Color(Palette.MESSENGER, 0.45), 1.5, 6.0)
	draw_circle(at, 5.0, Palette.TEXT_SHADOW)
	draw_circle(at, 4.0, Palette.MESSENGER)
	_draw_envelope(at + Vector2(-6, -16), Palette.MESSENGER)


func _draw_envelope(top_left: Vector2, color: Color) -> void:
	var size := Vector2(12, 8)
	draw_rect(Rect2(top_left, size), Palette.TEXT_SHADOW)
	draw_rect(Rect2(top_left, size), color, false, 1.5)
	var flap := PackedVector2Array([top_left, top_left + Vector2(size.x / 2, size.y * 0.6), top_left + Vector2(size.x, 0)])
	draw_polyline(flap, color, 1.5)


func _draw_marker(c: CommandData) -> void:
	var at := marker_position(c)
	var fill := Palette.GENERAL_MARK if c.is_general() else _side_color(c.player_id)
	if not c.is_active():
		fill = Palette.COMMAND_INACTIVE
	var points := _star(at, MARKER_SIZE + 2.0) if c.is_general() else _diamond(at, MARKER_SIZE)
	draw_colored_polygon(points, fill)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Palette.COMMAND_OUTLINE, 1.5)
	if c.is_general():
		# Ring in the side colour so both generals are told apart.
		draw_arc(at, MARKER_SIZE + 5.0, 0.0, TAU, 24, _side_color(c.player_id), 2.0)
	if c.id == selected_command_id:
		draw_arc(at, MARKER_SIZE + 9.0, 0.0, TAU, 24, Palette.SELECTION, 2.0)
	if c.status == CommandData.STATUS_INCAPACITATED:
		_draw_text(at + Vector2(MARKER_SIZE + 2, 4), "!", Palette.LINK_FAR)


static func _diamond(center: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0),
	])


static func _star(center: Vector2, r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var radius := r if i % 2 == 0 else r * 0.45
		var angle := -PI / 2.0 + i * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _draw_text(at: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Palette.TEXT_SHADOW)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
