class_name Hud
extends CanvasLayer
## Container of the battle UI. Exposes its components; the BattleController
## wires them to the game source.

@onready var top_bar: TopBar = $TopBar
@onready var division_panel: DivisionPanel = $DivisionPanel
@onready var event_log: EventLog = $EventLog
@onready var debug_overlay: DebugOverlay = $DebugOverlay
@onready var game_over: GameOverPanel = $GameOverPanel
