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
	MsgJoinGame        = "join_game"
	MsgReady           = "ready"
	MsgMoveDivision    = "move_division"
	MsgAttackDivision  = "attack_division"
	MsgDefendDivision  = "defend_division"
	MsgRetreatDivision = "retreat_division"
	MsgHoldDivision    = "hold_division"
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
	Order        *OrderDTO     `json:"order,omitempty"` // own divisions only
	Path         []PositionDTO `json:"path,omitempty"`  // own divisions only
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
