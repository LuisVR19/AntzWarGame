// Package network exposes the game over WebSocket (real time) and HTTP
// (health/inspection). It translates JSON messages to application commands
// and application outputs to JSON; it contains no game rules.
package network

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

// Client -> server.
const (
	MsgCreateGame      = "create_game"
	MsgCreateAIGame    = "create_ai_game"
	MsgJoinGame        = "join_game"
	MsgReady           = "ready"
	MsgMoveDivision    = "move_division"
	MsgAttackDivision  = "attack_division"
	MsgDefendDivision  = "defend_division"
	MsgRetreatDivision = "retreat_division"
	MsgHoldDivision    = "hold_division"
	MsgAssignCommander = "assign_commander"
	MsgSetFormation    = "set_formation"
)

// Server -> client.
const (
	MsgGameCreated       = "game_created"
	MsgGameJoined        = "game_joined"
	MsgLobbyUpdated      = "lobby_updated"
	MsgGameStarted       = "game_started"
	MsgGameState         = "game_state"
	MsgOrderAccepted     = "order_accepted"
	MsgDivisionUpdated   = "division_updated"
	MsgBattleStarted     = "battle_started"
	MsgBattleUpdated     = "battle_updated"
	MsgBattleEnded       = "battle_ended"
	MsgDivisionDestroyed = "division_destroyed"
	MsgGameFinished      = "game_finished"
	MsgCommandUpdated    = "command_updated"
	MsgMessengerUpdated  = "messenger_updated"
	MsgVolley            = "volley"
	MsgError             = "error"
)

// Envelope is the common header of every inbound message. Messages are flat
// JSON objects: {"type": "...", "request_id": "...", ...fields}.
type Envelope struct {
	Type      string `json:"type"`
	RequestID string `json:"request_id,omitempty"`
}

// ---------------------------------------------------------------------------
// Client -> server payloads
// ---------------------------------------------------------------------------

type CreateGameRequest struct {
	Envelope
	PlayerName string `json:"player_name"`
}

// CreateAIGameRequest creates a game against a server-controlled bot. The
// reply is game_created, like create_game.
type CreateAIGameRequest struct {
	Envelope
	PlayerName string `json:"player_name"`
}

// JoinGameRequest joins a game. With session_token it reconnects instead.
type JoinGameRequest struct {
	Envelope
	GameID       string `json:"game_id"`
	PlayerName   string `json:"player_name"`
	SessionToken string `json:"session_token,omitempty"`
}

type ReadyRequest struct {
	Envelope
	Ready *bool `json:"ready,omitempty"` // defaults to true
}

type MoveDivisionRequest struct {
	Envelope
	DivisionID string   `json:"division_id"`
	X          *float64 `json:"x"`
	Y          *float64 `json:"y"`
}

type AttackDivisionRequest struct {
	Envelope
	DivisionID       string `json:"division_id"`
	TargetDivisionID string `json:"target_division_id"`
}

type DefendDivisionRequest struct {
	Envelope
	DivisionID string `json:"division_id"`
}

// RetreatDivisionRequest retreats to (x, y) or, if omitted, to the
// division's deployment point.
type RetreatDivisionRequest struct {
	Envelope
	DivisionID string   `json:"division_id"`
	X          *float64 `json:"x,omitempty"`
	Y          *float64 `json:"y,omitempty"`
}

// AssignCommanderRequest puts a division under another command unit
// (commander or general) of the same player.
type AssignCommanderRequest struct {
	Envelope
	DivisionID  string `json:"division_id"`
	CommanderID string `json:"commander_id"`
}

// SetFormationRequest changes a division's formation ("line",
// "shield_wall", "wedge", "square", "column"). It is not an order: it does
// not go through the chain of command. The division reorganizes for a while.
type SetFormationRequest struct {
	Envelope
	DivisionID string `json:"division_id"`
	Formation  string `json:"formation"`
}

type HoldDivisionRequest struct {
	Envelope
	DivisionID string `json:"division_id"`
}

// ---------------------------------------------------------------------------
// Shared DTOs
// ---------------------------------------------------------------------------

type PositionDTO struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type TerrainModifiersDTO struct {
	Movement   float64 `json:"movement_modifier"`
	Attack     float64 `json:"attack_modifier"`
	Defense    float64 `json:"defense_modifier"`
	Visibility float64 `json:"visibility_modifier"`
}

// MapDTO describes the battlefield. Rows contain one character per tile:
// P=plain, F=forest, H=hill, W=water. Row 0 is y=0.
type MapDTO struct {
	Width    float64                        `json:"width"`
	Height   float64                        `json:"height"`
	CellSize float64                        `json:"cell_size"`
	Cols     int                            `json:"cols"`
	Rows     int                            `json:"rows"`
	Tiles    []string                       `json:"tiles"`
	Legend   map[string]string              `json:"legend"`
	Terrain  map[string]TerrainModifiersDTO `json:"terrain"`
	Spawns   []PositionDTO                  `json:"spawns"`
}

type PlayerDTO struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Side      int    `json:"side"`
	Ready     bool   `json:"ready"`
	Connected bool   `json:"connected"`
	Bot       bool   `json:"bot,omitempty"`
}

type OrderDTO struct {
	ID               string       `json:"id"`
	Type             string       `json:"type"`
	TargetPosition   *PositionDTO `json:"target_position,omitempty"`
	TargetDivisionID string       `json:"target_division_id,omitempty"`
}

type DivisionDTO struct {
	ID           string        `json:"id"`
	PlayerID     string        `json:"player_id"`
	Name         string        `json:"name"`
	X            float64       `json:"x"`
	Y            float64       `json:"y"`
	UnitCount    int           `json:"unit_count"`
	MaxUnitCount int           `json:"max_unit_count"`
	Attack       float64       `json:"attack"`
	Defense      float64       `json:"defense"`
	Speed        float64       `json:"speed"`
	Morale       float64       `json:"morale"`
	Experience   float64       `json:"experience"`
	Fatigue      float64       `json:"fatigue"`
	State        string        `json:"state"`
	Routed       bool          `json:"routed"`
	InBattle     bool          `json:"in_battle"`
	Terrain      string        `json:"terrain"`
	UnitType     string        `json:"unit_type"`
	Formation    string        `json:"formation"`
	Facing       float64       `json:"facing"` // radians, world space
	Reforming    bool          `json:"reforming"`
	Order        *OrderDTO     `json:"order,omitempty"` // own divisions only
	Path         []PositionDTO `json:"path,omitempty"`  // own divisions only
	// Chain of command, own divisions only (absent without command units).
	CommanderID  string           `json:"commander_id,omitempty"`
	CommandLink  string           `json:"command_link,omitempty"` // in_range, out_of_range, no_command
	PendingOrder *PendingOrderDTO `json:"pending_order,omitempty"`
}

// PendingOrderDTO is an order a messenger is carrying to a division.
type PendingOrderDTO struct {
	MessengerID string   `json:"messenger_id"`
	ETATicks    int64    `json:"eta_ticks"`
	Order       OrderDTO `json:"order"`
}

// CommandUnitDTO is a general or a commander. Its position is the position
// of its host division.
type CommandUnitDTO struct {
	ID              string  `json:"id"`
	PlayerID        string  `json:"player_id"`
	Role            string  `json:"role"` // general, commander
	Name            string  `json:"name"`
	HostDivisionID  string  `json:"host_division_id"`
	X               float64 `json:"x"`
	Y               float64 `json:"y"`
	Status          string  `json:"status"` // active, incapacitated, eliminated
	CommRadius      float64 `json:"comm_radius"`
	InfluenceRadius float64 `json:"influence_radius"`
}

// MessengerDTO is a message in transit (sent only to its owner).
type MessengerDTO struct {
	ID         string   `json:"id"`
	SenderID   string   `json:"sender_id"`
	DivisionID string   `json:"division_id"`
	X          float64  `json:"x"`
	Y          float64  `json:"y"`
	SentTick   int64    `json:"sent_tick"`
	ETATicks   int64    `json:"eta_ticks"`
	Order      OrderDTO `json:"order"`
}

type BattleDTO struct {
	ID             string  `json:"id"`
	AttackerID     string  `json:"attacker_id"`
	DefenderID     string  `json:"defender_id"`
	X              float64 `json:"x"`
	Y              float64 `json:"y"`
	StartedTick    int64   `json:"started_tick"`
	Rounds         int     `json:"rounds"`
	AttackerLosses int     `json:"attacker_losses"`
	DefenderLosses int     `json:"defender_losses"`
}

type BattleSideDTO struct {
	DivisionID       string  `json:"division_id"`
	Exposure         string  `json:"exposure"` // front, flank, rear
	Losses           int     `json:"losses"`
	UnitCount        int     `json:"unit_count"`
	Morale           float64 `json:"morale"`
	Fatigue          float64 `json:"fatigue"`
	EffectiveAttack  float64 `json:"effective_attack"`
	EffectiveDefense float64 `json:"effective_defense"`
}

// ---------------------------------------------------------------------------
// Server -> client messages
// ---------------------------------------------------------------------------

// GameStateMessage is the periodic authoritative snapshot.
type GameStateMessage struct {
	Type           string        `json:"type"`
	GameID         string        `json:"game_id"`
	Status         string        `json:"status"`
	Tick           int64         `json:"tick"`
	CountdownTicks int           `json:"countdown_ticks,omitempty"`
	Divisions      []DivisionDTO `json:"divisions"`
	Battles        []BattleDTO   `json:"battles"`
	// Chain of command (absent when no army has command units).
	Commanders []CommandUnitDTO `json:"commanders,omitempty"`
	Messengers []MessengerDTO   `json:"messengers,omitempty"`
}

// GameJoinedMessage is sent as game_created (creator) or game_joined.
type GameJoinedMessage struct {
	Type         string           `json:"type"`
	RequestID    string           `json:"request_id,omitempty"`
	GameID       string           `json:"game_id"`
	PlayerID     string           `json:"player_id"`
	SessionToken string           `json:"session_token"`
	Side         int              `json:"side"`
	Reconnected  bool             `json:"reconnected"`
	TickRate     int              `json:"tick_rate"`
	Map          MapDTO           `json:"map"`
	State        GameStateMessage `json:"state"`
}

type LobbyUpdatedMessage struct {
	Type    string      `json:"type"`
	GameID  string      `json:"game_id"`
	Status  string      `json:"status"`
	Players []PlayerDTO `json:"players"`
}

type GameStartedMessage struct {
	Type   string           `json:"type"`
	GameID string           `json:"game_id"`
	Tick   int64            `json:"tick"`
	State  GameStateMessage `json:"state"`
}

type OrderAcceptedMessage struct {
	Type       string   `json:"type"`
	RequestID  string   `json:"request_id,omitempty"`
	DivisionID string   `json:"division_id"`
	Order      OrderDTO `json:"order"`
	// Delivery: "immediate" or "messenger" (then messenger_id and the
	// estimated eta_ticks until the division receives it).
	Delivery    string `json:"delivery"`
	MessengerID string `json:"messenger_id,omitempty"`
	ETATicks    int64  `json:"eta_ticks,omitempty"`
}

type DivisionUpdatedMessage struct {
	Type     string      `json:"type"`
	Tick     int64       `json:"tick"`
	Reason   string      `json:"reason"`
	Division DivisionDTO `json:"division"`
}

type BattleStartedMessage struct {
	Type       string  `json:"type"`
	Tick       int64   `json:"tick"`
	BattleID   string  `json:"battle_id"`
	AttackerID string  `json:"attacker_id"`
	DefenderID string  `json:"defender_id"`
	X          float64 `json:"x"`
	Y          float64 `json:"y"`
	// Side of each division hit by the other (front, flank, rear).
	AttackerExposure string `json:"attacker_exposure"`
	DefenderExposure string `json:"defender_exposure"`
}

// VolleyMessage: a ranged division shot at an enemy.
type VolleyMessage struct {
	Type      string      `json:"type"`
	Tick      int64       `json:"tick"`
	ShooterID string      `json:"shooter_id"`
	TargetID  string      `json:"target_id"`
	Losses    int         `json:"losses"`
	UnitCount int         `json:"unit_count"`
	Exposure  string      `json:"exposure"`
	From      PositionDTO `json:"from"`
	To        PositionDTO `json:"to"`
}

type BattleUpdatedMessage struct {
	Type     string        `json:"type"`
	Tick     int64         `json:"tick"`
	BattleID string        `json:"battle_id"`
	Round    int           `json:"round"`
	Attacker BattleSideDTO `json:"attacker"`
	Defender BattleSideDTO `json:"defender"`
}

type BattleEndedMessage struct {
	Type             string `json:"type"`
	Tick             int64  `json:"tick"`
	BattleID         string `json:"battle_id"`
	AttackerID       string `json:"attacker_id"`
	DefenderID       string `json:"defender_id"`
	Reason           string `json:"reason"`
	WinnerDivisionID string `json:"winner_division_id,omitempty"`
}

type DivisionDestroyedMessage struct {
	Type       string `json:"type"`
	Tick       int64  `json:"tick"`
	DivisionID string `json:"division_id"`
	PlayerID   string `json:"player_id"`
	BattleID   string `json:"battle_id,omitempty"`
}

// CommandUpdatedMessage: a general or commander changed status or was promoted.
type CommandUpdatedMessage struct {
	Type      string `json:"type"`
	Tick      int64  `json:"tick"`
	CommandID string `json:"command_id"`
	PlayerID  string `json:"player_id"`
	Role      string `json:"role"`
	Status    string `json:"status"`
	Reason    string `json:"reason"` // host_routed, host_rallied, host_destroyed, promoted
}

// MessengerUpdatedMessage: a messenger was dispatched, delivered its order or
// was cancelled (reason: dispatched, delivered, superseded,
// recipient_destroyed, game_finished or the validation error code).
type MessengerUpdatedMessage struct {
	Type        string   `json:"type"`
	Tick        int64    `json:"tick"`
	MessengerID string   `json:"messenger_id"`
	DivisionID  string   `json:"division_id"`
	Status      string   `json:"status"` // pending, delivered, cancelled
	Reason      string   `json:"reason"`
	Order       OrderDTO `json:"order"`
}

type GameFinishedMessage struct {
	Type           string `json:"type"`
	Tick           int64  `json:"tick"`
	WinnerPlayerID string `json:"winner_player_id,omitempty"`
	Reason         string `json:"reason"`
	Result         string `json:"result"` // victory, defeat or draw (for the receiver)
}

type ErrorMessage struct {
	Type      string `json:"type"`
	RequestID string `json:"request_id,omitempty"`
	Code      string `json:"code"`
	Message   string `json:"message"`
}

// ---------------------------------------------------------------------------
// HTTP DTOs
// ---------------------------------------------------------------------------

type HealthResponse struct {
	Status string `json:"status"`
	Games  int    `json:"games"`
}

type GameInfoResponse struct {
	ID           string      `json:"id"`
	Status       string      `json:"status"`
	Tick         int64       `json:"tick"`
	CreatedAt    string      `json:"created_at"`
	StartedAt    string      `json:"started_at,omitempty"`
	Players      []PlayerDTO `json:"players"`
	Divisions    int         `json:"divisions_alive"`
	Battles      int         `json:"battles_active"`
	WinnerID     string      `json:"winner_player_id,omitempty"`
	FinishReason string      `json:"finish_reason,omitempty"`
}

type CreateGameResponse struct {
	GameID string `json:"game_id"`
}
