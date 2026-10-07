class_name Palette
extends RefCounted
## Every color/size used by the placeholder visuals. Replacing shapes with
## real assets later should only touch this file and the *_painter / *_shape
## scripts, never the game logic.

const SIDE_COLORS := [Color(0.27, 0.56, 1.0), Color(0.95, 0.32, 0.26)]
const SIDE_NAMES := ["azul", "rojo"]

const TERRAIN := {
	"PLAIN": Color(0.43, 0.6, 0.31),
	"FOREST": Color(0.24, 0.45, 0.22),
	"HILL": Color(0.55, 0.5, 0.33),
	"WATER": Color(0.2, 0.42, 0.75),
}
const TREE := Color(0.13, 0.32, 0.14)
const TREE_LIGHT := Color(0.2, 0.42, 0.19)
const HILL_DARK := Color(0.45, 0.4, 0.26)
const HILL_LIGHT := Color(0.64, 0.59, 0.41)
const WATER_WAVE := Color(0.45, 0.65, 0.95, 0.6)
const GRID := Color(0, 0, 0, 0.06)
const MAP_BORDER := Color(0.05, 0.05, 0.05)
const NEST := Color(0.42, 0.29, 0.17)
const NEST_HOLE := Color(0.12, 0.08, 0.05)

const SELECTION := Color(1.0, 0.9, 0.3)
const MOVE_RADIUS := Color(1.0, 1.0, 1.0, 0.25)
const ORDER_MOVE_LINE := Color(1.0, 1.0, 1.0, 0.75)
const ORDER_ATTACK_LINE := Color(1.0, 0.35, 0.25, 0.9)
const ORDER_RETREAT_LINE := Color(1.0, 0.8, 0.3, 0.8)
const BATTLE := Color(1.0, 0.55, 0.1)
const DESTROYED := Color(0.35, 0.35, 0.35, 0.7)
const BAR_BACK := Color(0, 0, 0, 0.6)
const BAR_STRENGTH := Color(0.35, 0.85, 0.35)
const BAR_STRENGTH_LOW := Color(0.9, 0.25, 0.2)
const BAR_MORALE := Color(0.95, 0.8, 0.25)
const TEXT := Color(1, 1, 1)
const TEXT_DIM := Color(0.8, 0.8, 0.8)
const TEXT_SHADOW := Color(0, 0, 0, 0.75)

const LOG_INFO := Color(0.85, 0.85, 0.85)
const LOG_COMBAT := Color(1.0, 0.65, 0.3)
const LOG_ERROR := Color(1.0, 0.4, 0.4)
const LOG_GOOD := Color(0.5, 0.95, 0.5)

const PANEL_BG := Color(0.08, 0.09, 0.1, 0.88)


static func side_color(side: int) -> Color:
	return SIDE_COLORS[clampi(side, 0, SIDE_COLORS.size() - 1)]


static func side_name(side: int) -> String:
	return SIDE_NAMES[clampi(side, 0, SIDE_NAMES.size() - 1)]


static func terrain_color(type: String) -> Color:
	return TERRAIN.get(type, TERRAIN["PLAIN"])
