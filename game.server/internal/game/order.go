package game

import (
	"errors"
	"fmt"
	"time"

	"gameserver/internal/movement"
	"gameserver/internal/player"
)

// Order is an instruction accepted by the server for a division.
type Order struct {
	ID               string
	PlayerID         player.ID
	DivisionID       DivisionID
	Type             OrderType
	TargetPosition   *Position
	TargetDivisionID DivisionID
	CreatedAt        time.Time
	CreatedTick      int64
	// Delivery tells whether the order is immediate or carried by a
	// messenger (MessengerID, estimated ETATicks at acceptance).
	Delivery    DeliveryMode
	MessengerID MessengerID
	ETATicks    int64
}

// OrderRequest is an order as requested by a client, before validation.
// Clients only express intent; the server decides the outcome.
type OrderRequest struct {
	PlayerID         player.ID
	DivisionID       DivisionID
	Type             OrderType
	TargetPosition   *Position
	TargetDivisionID DivisionID
}

// ErrorCode is a stable machine-readable error identifier for clients.
type ErrorCode string

const (
	CodeGameNotRunning      ErrorCode = "game_not_running"
	CodeGameFull            ErrorCode = "game_full"
	CodeInvalidState        ErrorCode = "invalid_state"
	CodePlayerNotFound      ErrorCode = "player_not_found"
	CodeInvalidOrderType    ErrorCode = "invalid_order_type"
	CodeDivisionNotFound    ErrorCode = "division_not_found"
	CodeNotOwner            ErrorCode = "not_owner"
	CodeDivisionDestroyed   ErrorCode = "division_destroyed"
	CodeDivisionRouted      ErrorCode = "division_routed"
	CodeDivisionEngaged     ErrorCode = "division_engaged"
	CodeTargetRequired      ErrorCode = "target_required"
	CodeTargetNotFound      ErrorCode = "target_not_found"
	CodeTargetFriendly      ErrorCode = "target_friendly"
	CodeTargetDestroyed     ErrorCode = "target_destroyed"
	CodeInvalidPosition     ErrorCode = "invalid_position"
	CodeImpassable          ErrorCode = "impassable_position"
	CodeUnreachable         ErrorCode = "unreachable_position"
	CodeNoCommand           ErrorCode = "no_command"
	CodeCommanderNotFound   ErrorCode = "commander_not_found"
	CodeCommanderInactive   ErrorCode = "commander_inactive"
	CodeInvalidAssignment   ErrorCode = "invalid_assignment"
	CodeCommanderOutOfRange ErrorCode = "commander_out_of_range"
	CodeInvalidFormation    ErrorCode = "invalid_formation"
	CodeSameFormation       ErrorCode = "same_formation"
)

// Error is a domain error with a client-facing code.
type Error struct {
	Code    ErrorCode
	Message string
}

func (e *Error) Error() string { return fmt.Sprintf("%s: %s", e.Code, e.Message) }

func newErr(code ErrorCode, format string, args ...any) *Error {
	return &Error{Code: code, Message: fmt.Sprintf(format, args...)}
}

// CodeOf extracts the ErrorCode of err ("internal" if not a domain error).
func CodeOf(err error) ErrorCode {
	var e *Error
	if errors.As(err, &e) {
		return e.Code
	}
	return "internal"
}

// pendingOrder is a validated order waiting for the next tick, with the
// path precomputed during validation when applicable.
type pendingOrder struct {
	order *Order
	path  []Position
}

// ValidateOrder checks a request against the current state and returns the
// precomputed path for positional orders. It does not mutate the game.
func (g *Game) ValidateOrder(req OrderRequest) ([]Position, error) {
	if g.Status != StatusRunning {
		return nil, newErr(CodeGameNotRunning, "game is %s", g.Status)
	}
	if !req.Type.Valid() {
		return nil, newErr(CodeInvalidOrderType, "unknown order type %q", req.Type)
	}
	if _, ok := g.players[req.PlayerID]; !ok {
		return nil, newErr(CodePlayerNotFound, "player %s is not in this game", req.PlayerID)
	}
	d, ok := g.divisions[req.DivisionID]
	if !ok {
		return nil, newErr(CodeDivisionNotFound, "division %s does not exist", req.DivisionID)
	}
	if d.PlayerID != req.PlayerID {
		return nil, newErr(CodeNotOwner, "division %s belongs to another player", d.ID)
	}
	if !d.Alive() {
		return nil, newErr(CodeDivisionDestroyed, "division %s is destroyed", d.ID)
	}
	if d.Routed && req.Type != OrderRetreat {
		return nil, newErr(CodeDivisionRouted, "division %s is routed and only accepts RETREAT", d.ID)
	}
	if g.engaged(d.ID) && (req.Type == OrderMove || req.Type == OrderAttack) {
		return nil, newErr(CodeDivisionEngaged, "division %s is in combat; use RETREAT, DEFEND or HOLD", d.ID)
	}

	switch req.Type {
	case OrderMove:
		if req.TargetPosition == nil {
			return nil, newErr(CodeTargetRequired, "MOVE requires a target position")
		}
		return g.validatePath(d, *req.TargetPosition)
	case OrderRetreat:
		target := d.home
		if req.TargetPosition != nil {
			target = *req.TargetPosition
		}
		return g.validatePath(d, target)
	case OrderAttack:
		if req.TargetDivisionID == "" {
			return nil, newErr(CodeTargetRequired, "ATTACK requires a target division")
		}
		t, ok := g.divisions[req.TargetDivisionID]
		// A target the player cannot see is reported as nonexistent so
		// that fog of war cannot be probed through order errors.
		if !ok || !g.visibility.CanSee(g, d.PlayerID, t) {
			return nil, newErr(CodeTargetNotFound, "target division %s does not exist", req.TargetDivisionID)
		}
		if t.PlayerID == d.PlayerID {
			return nil, newErr(CodeTargetFriendly, "cannot attack a friendly division")
		}
		if !t.Alive() {
			return nil, newErr(CodeTargetDestroyed, "target division %s is destroyed", t.ID)
		}
		path, err := movement.FindPath(g.Map, d.Position, t.Position)
		if err != nil {
			return nil, newErr(CodeUnreachable, "target division %s cannot be reached", t.ID)
		}
		return path, nil
	}
	return nil, nil // DEFEND and HOLD need no target.
}

func (g *Game) validatePath(d *Division, target Position) ([]Position, error) {
	if !target.IsFinite() || !g.Map.InBounds(target) {
		return nil, newErr(CodeInvalidPosition, "position (%.1f, %.1f) is outside the map", target.X, target.Y)
	}
	path, err := movement.FindPath(g.Map, d.Position, target)
	switch {
	case errors.Is(err, movement.ErrImpassable):
		return nil, newErr(CodeImpassable, "terrain at (%.1f, %.1f) is impassable", target.X, target.Y)
	case err != nil:
		return nil, newErr(CodeUnreachable, "position (%.1f, %.1f) cannot be reached", target.X, target.Y)
	}
	return path, nil
}

// SubmitOrder validates a request and routes it through the chain of
// command (command.go). An immediate order takes effect during the next tick
// (step 1, "process orders"); if several are queued for the same division in
// one tick, the last one wins. Otherwise a messenger carries it, replacing
// any message already in transit to that division; an identical request
// returns the order already in transit instead of sending another messenger.
func (g *Game) SubmitOrder(req OrderRequest) (*Order, error) {
	path, err := g.ValidateOrder(req)
	if err != nil {
		return nil, err
	}
	d := g.divisions[req.DivisionID]
	immediate, src, err := g.routeOrder(d)
	if err != nil {
		return nil, err
	}
	pendingMsg := g.pendingMessenger(d.ID)
	if !immediate && pendingMsg != nil && sameRequest(pendingMsg.Order, req, d) {
		pendingMsg.Order.ETATicks = pendingMsg.ETATicks
		return pendingMsg.Order, nil
	}
	if pendingMsg != nil {
		g.endMessenger(pendingMsg, MessageCancelled, "superseded")
	}
	g.orderSeq++
	o := &Order{
		ID:               fmt.Sprintf("order-%d", g.orderSeq),
		PlayerID:         req.PlayerID,
		DivisionID:       req.DivisionID,
		Type:             req.Type,
		TargetDivisionID: req.TargetDivisionID,
		CreatedAt:        g.now(),
		CreatedTick:      g.CurrentTick,
	}
	switch {
	case req.TargetPosition != nil && (req.Type == OrderMove || req.Type == OrderRetreat):
		p := *req.TargetPosition
		o.TargetPosition = &p
	case req.Type == OrderRetreat:
		p := g.divisions[req.DivisionID].home
		o.TargetPosition = &p
	}
	if req.Type != OrderAttack {
		o.TargetDivisionID = ""
	}
	if !immediate {
		g.dispatch(src, d, o)
		return o, nil
	}
	o.Delivery = DeliveryImmediate
	g.pending = append(g.pending, pendingOrder{order: o, path: path})
	return o, nil
}
