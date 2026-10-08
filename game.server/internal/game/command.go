package game

import (
	"fmt"
	"math"

	"gameserver/internal/movement"
	"gameserver/internal/player"
)

// Chain of command
//
// Each army may have a general and several commanders (CommandUnit). A unit
// rides with its host division: it is where the division is, it is
// incapacitated while the division is routed and eliminated when the
// division is destroyed. Every division may report to a commander
// (Division.CommanderID); otherwise it reports directly to the general.
//
// An order reaches a division through its "order source": its commander if
// active, else the general if active, else nobody (CodeNoCommand). Inside the
// source's comm radius the order is immediate (applied next tick, as without
// a chain of command). Outside, a Messenger leaves the source, follows the
// division over the terrain and hands the order over when it arrives; the
// order is validated again then. Until that moment the division keeps its
// current order.

// CommandRole is the rank of a command unit.
type CommandRole string

const (
	RoleGeneral   CommandRole = "GENERAL"
	RoleCommander CommandRole = "COMMANDER"
)

// CommandStatus is the state of a command unit.
type CommandStatus string

const (
	CommandActive        CommandStatus = "ACTIVE"
	CommandIncapacitated CommandStatus = "INCAPACITATED" // host division routed
	CommandEliminated    CommandStatus = "ELIMINATED"    // host division destroyed
)

// CommandUnitID identifies a general or commander.
type CommandUnitID string

// CommandUnit is a general or a commander. Its position is the position of
// its host division; subordinates are the divisions whose CommanderID points
// to it (not stored here, to keep a single source of truth).
type CommandUnit struct {
	ID              CommandUnitID
	PlayerID        player.ID
	Role            CommandRole
	Name            string
	HostDivisionID  DivisionID
	CommRadius      float64
	InfluenceRadius float64
	Status          CommandStatus
}

// CommandLink describes how an order would reach a division right now.
type CommandLink string

const (
	LinkNone       CommandLink = ""             // the army has no chain of command
	LinkInRange    CommandLink = "IN_RANGE"     // immediate
	LinkOutOfRange CommandLink = "OUT_OF_RANGE" // by messenger
	LinkNoCommand  CommandLink = "NO_COMMAND"   // no active commander or general
)

// DeliveryMode tells how an accepted order travels to its division.
type DeliveryMode string

const (
	DeliveryImmediate DeliveryMode = "IMMEDIATE"
	DeliveryMessenger DeliveryMode = "MESSENGER"
)

// MessengerStatus is the lifecycle of a message.
type MessengerStatus string

const (
	MessagePending   MessengerStatus = "PENDING"
	MessageDelivered MessengerStatus = "DELIVERED"
	MessageCancelled MessengerStatus = "CANCELLED"
	// MessageIntercepted is reserved for a future interception mechanic.
	MessageIntercepted MessengerStatus = "INTERCEPTED"
)

// MessengerID identifies a message in transit.
type MessengerID string

// Messenger carries one order from a command unit to a division.
type Messenger struct {
	ID         MessengerID
	PlayerID   player.ID
	SenderID   CommandUnitID
	DivisionID DivisionID
	Order      *Order
	Status     MessengerStatus
	Reason     string
	SentTick   int64
	Position   Position
	// ETATicks is the estimated number of ticks left until delivery.
	ETATicks int64

	path       []Position
	pathTarget Position
	lastRepath int64
}

// CommandUnit returns a command unit by ID.
func (g *Game) CommandUnit(id CommandUnitID) (*CommandUnit, bool) {
	u, ok := g.commandUnits[id]
	return u, ok
}

// CommandUnits returns every command unit in creation order.
func (g *Game) CommandUnits() []*CommandUnit { return append([]*CommandUnit(nil), g.commandOrder...) }

// Messengers returns the messages in transit.
func (g *Game) Messengers() []*Messenger { return append([]*Messenger(nil), g.messengers...) }

// General returns the current general of a player (it may be eliminated
// while a successor is pending).
func (g *Game) General(pid player.ID) (*CommandUnit, bool) {
	a, ok := g.armies[pid]
	if !ok || a.GeneralID == "" {
		return nil, false
	}
	return g.CommandUnit(a.GeneralID)
}

// hasChainOfCommand reports whether the player's army uses command rules.
func (g *Game) hasChainOfCommand(pid player.ID) bool {
	a, ok := g.armies[pid]
	return ok && a.GeneralID != ""
}

// deployCommand creates the command units of one army from the template.
// divs[i] is the division created from Rules.Army[i].
func (g *Game) deployCommand(army *Army, divs []*Division) {
	byName := map[string]CommandUnitID{}
	for i, t := range g.Rules.Army {
		if t.Leads == "" {
			continue
		}
		g.commandSeq++
		u := &CommandUnit{
			PlayerID:       army.PlayerID,
			Role:           RoleCommander,
			Name:           t.Leads,
			HostDivisionID: divs[i].ID,
			Status:         CommandActive,
		}
		if t.Leads == LeadsGeneral {
			u.Role = RoleGeneral
			u.Name = "General"
			army.GeneralID = CommandUnitID(fmt.Sprintf("general-%d", g.commandSeq))
			u.ID = army.GeneralID
		} else {
			u.ID = CommandUnitID(fmt.Sprintf("commander-%d", g.commandSeq))
		}
		g.setRadii(u)
		g.commandUnits[u.ID] = u
		g.commandOrder = append(g.commandOrder, u)
		byName[t.Leads] = u.ID
	}
	for i, t := range g.Rules.Army {
		if t.Commander != "" {
			divs[i].CommanderID = byName[t.Commander]
		}
	}
	army.successionAt = -1
}

func (g *Game) setRadii(u *CommandUnit) {
	c := g.Rules.Command
	if u.Role == RoleGeneral {
		u.CommRadius, u.InfluenceRadius = c.GeneralCommRadius, c.GeneralInfluenceRadius
	} else {
		u.CommRadius, u.InfluenceRadius = c.CommanderCommRadius, c.CommanderInfluenceRadius
	}
}

// UnitPosition returns where a command unit is (its host division).
func (g *Game) UnitPosition(u *CommandUnit) Position {
	if d, ok := g.divisions[u.HostDivisionID]; ok {
		return d.Position
	}
	return Position{}
}

func (g *Game) activeUnit(id CommandUnitID) (*CommandUnit, bool) {
	u, ok := g.commandUnits[id]
	if !ok || u.Status != CommandActive {
		return nil, false
	}
	return u, true
}

// orderSource returns the command unit that transmits orders to d: the
// general if it rides with d, else d's commander if active, else the
// general if active.
func (g *Game) orderSource(d *Division) (*CommandUnit, bool) {
	a, ok := g.armies[d.PlayerID]
	if !ok {
		return nil, false
	}
	if gen, ok := g.activeUnit(a.GeneralID); ok && gen.HostDivisionID == d.ID {
		return gen, true
	}
	if u, ok := g.activeUnit(d.CommanderID); ok {
		return u, true
	}
	return g.activeUnit(a.GeneralID)
}

func (g *Game) inRadius(u *CommandUnit, d *Division, radius float64) bool {
	return g.UnitPosition(u).Dist(d.Position) <= radius
}

// commandLink computes how an order would reach d now.
func (g *Game) commandLink(d *Division) (CommandLink, *CommandUnit) {
	if !g.hasChainOfCommand(d.PlayerID) {
		return LinkNone, nil
	}
	src, ok := g.orderSource(d)
	if !ok {
		return LinkNoCommand, nil
	}
	if g.inRadius(src, d, src.CommRadius) {
		return LinkInRange, src
	}
	if g.Rules.Command.GeneralRelay {
		if gen, ok := g.activeUnit(g.armies[d.PlayerID].GeneralID); ok && g.inRadius(gen, d, gen.CommRadius) {
			return LinkInRange, gen
		}
	}
	return LinkOutOfRange, src
}

// CommandLinkOf is the exported form of commandLink (views, tests, AI).
func (g *Game) CommandLinkOf(id DivisionID) CommandLink {
	d, ok := g.divisions[id]
	if !ok || !d.Alive() {
		return LinkNone
	}
	link, _ := g.commandLink(d)
	return link
}

// led reports whether d is inside the influence radius of its own active
// commander or of its active general.
func (g *Game) led(d *Division) bool {
	if !g.hasChainOfCommand(d.PlayerID) {
		return false
	}
	if u, ok := g.activeUnit(d.CommanderID); ok && g.inRadius(u, d, u.InfluenceRadius) {
		return true
	}
	gen, ok := g.activeUnit(g.armies[d.PlayerID].GeneralID)
	return ok && g.inRadius(gen, d, gen.InfluenceRadius)
}

// combatMorale is the morale used in combat: stored morale plus the
// leadership bonus. The bonus is never written back to the division.
func (g *Game) combatMorale(d *Division) float64 {
	if g.led(d) {
		return math.Min(d.Morale+g.Rules.Command.LeadershipMoraleBonus, g.Rules.MaxMorale)
	}
	return d.Morale
}

// ---------------------------------------------------------------------------
// Orders and messengers
// ---------------------------------------------------------------------------

// routeOrder decides how a validated order travels (called by SubmitOrder
// before the order gets an ID). It returns the source for messenger delivery.
func (g *Game) routeOrder(d *Division) (immediate bool, src *CommandUnit, err error) {
	link, src := g.commandLink(d)
	switch link {
	case LinkNone, LinkInRange:
		return true, src, nil
	case LinkNoCommand:
		return false, nil, newErr(CodeNoCommand, "division %s has no active commander or general to receive orders from", d.ID)
	}
	return false, src, nil
}

// pendingMessenger returns the message in transit for a division.
func (g *Game) pendingMessenger(id DivisionID) *Messenger {
	for _, m := range g.messengers {
		if m.DivisionID == id {
			return m
		}
	}
	return nil
}

// PendingOrder returns the order a messenger is carrying to the division.
func (g *Game) PendingOrder(id DivisionID) (*Messenger, bool) {
	m := g.pendingMessenger(id)
	return m, m != nil
}

// sameRequest reports whether an order already carries req for d. A RETREAT
// without destination means "back to the deployment point", as stored.
func sameRequest(o *Order, req OrderRequest, d *Division) bool {
	if o.Type != req.Type || o.TargetDivisionID != req.TargetDivisionID {
		return false
	}
	target := req.TargetPosition
	if target == nil && req.Type == OrderRetreat {
		target = &d.home
	}
	switch {
	case target == nil || o.TargetPosition == nil:
		return target == nil && o.TargetPosition == nil
	}
	return o.TargetPosition.Dist(*target) < 1e-6
}

// dispatch sends o to d by messenger from src.
func (g *Game) dispatch(src *CommandUnit, d *Division, o *Order) *Messenger {
	g.messengerSeq++
	m := &Messenger{
		ID:         MessengerID(fmt.Sprintf("messenger-%d", g.messengerSeq)),
		PlayerID:   d.PlayerID,
		SenderID:   src.ID,
		DivisionID: d.ID,
		Order:      o,
		Status:     MessagePending,
		SentTick:   g.CurrentTick,
		Position:   g.UnitPosition(src),
	}
	g.routeMessenger(m, d.Position)
	m.ETATicks = g.messengerETA(m, d)
	o.Delivery, o.MessengerID, o.ETATicks = DeliveryMessenger, m.ID, m.ETATicks
	g.messengers = append(g.messengers, m)
	g.emit(MessengerUpdated{At: g.CurrentTick, MessengerID: m.ID, PlayerID: m.PlayerID, DivisionID: d.ID, Status: m.Status, Reason: "dispatched", Order: o})
	g.log.Info("messenger dispatched", "game_id", g.ID, "messenger_id", m.ID, "player_id", m.PlayerID, "sender_id", src.ID,
		"division_id", d.ID, "order_type", o.Type, "eta_ticks", m.ETATicks, "tick", g.CurrentTick)
	return m
}

func (g *Game) routeMessenger(m *Messenger, target Position) {
	path, err := movement.FindPath(g.Map, m.Position, target)
	if err != nil {
		path = []Position{target}
	}
	m.path, m.pathTarget, m.lastRepath = path, target, g.CurrentTick
}

// messengerETA estimates the ticks left from the remaining path length.
func (g *Game) messengerETA(m *Messenger, d *Division) int64 {
	length, prev := 0.0, m.Position
	for _, p := range m.path {
		length += prev.Dist(p)
		prev = p
	}
	length += prev.Dist(d.Position) // the division may have moved
	length = math.Max(length-g.Rules.Command.MessengerDeliveryRange, 0)
	return int64(math.Ceil(length / (g.Rules.Command.MessengerSpeed * g.Rules.DT())))
}

// endMessenger finishes a message and removes it from the transit list.
func (g *Game) endMessenger(m *Messenger, status MessengerStatus, reason string) {
	m.Status, m.Reason = status, reason
	kept := g.messengers[:0]
	for _, x := range g.messengers {
		if x != m {
			kept = append(kept, x)
		}
	}
	for i := len(kept); i < len(g.messengers); i++ {
		g.messengers[i] = nil
	}
	g.messengers = kept
	g.emit(MessengerUpdated{At: g.CurrentTick, MessengerID: m.ID, PlayerID: m.PlayerID, DivisionID: m.DivisionID, Status: status, Reason: reason, Order: m.Order})
	g.log.Info("messenger "+string(status), "game_id", g.ID, "messenger_id", m.ID, "division_id", m.DivisionID, "reason", reason, "tick", g.CurrentTick)
}

// updateMessengers moves every messenger towards its division and delivers
// the order on arrival. A delivered order is validated again and queued like
// an immediate one (it takes effect next tick).
func (g *Game) updateMessengers() {
	cfg := g.Rules.Command
	for _, m := range append([]*Messenger(nil), g.messengers...) {
		d := g.divisions[m.DivisionID]
		if d == nil || !d.Alive() {
			g.endMessenger(m, MessageCancelled, "recipient_destroyed")
			continue
		}
		if m.Position.Dist(d.Position) > cfg.MessengerDeliveryRange {
			// Follow the division: recompute the route when it moved away.
			if len(m.path) == 0 || (d.Position.Dist(m.pathTarget) > g.Map.CellSize/2 &&
				g.CurrentTick-m.lastRepath >= int64(g.Rules.PathRecomputeTicks)) {
				g.routeMessenger(m, d.Position)
			}
			res := movement.Step(g.Map, movement.StepInput{
				Position: m.Position, Waypoints: m.path, Speed: cfg.MessengerSpeed, Multiplier: 1, DT: g.Rules.DT(),
			})
			m.Position, m.path = res.Position, res.Waypoints
			if res.Blocked {
				m.path = nil
			}
		}
		if m.Position.Dist(d.Position) <= cfg.MessengerDeliveryRange {
			g.deliver(m, d)
			continue
		}
		m.ETATicks = g.messengerETA(m, d)
	}
}

func (g *Game) deliver(m *Messenger, d *Division) {
	o := m.Order
	req := OrderRequest{PlayerID: m.PlayerID, DivisionID: d.ID, Type: o.Type, TargetPosition: o.TargetPosition, TargetDivisionID: o.TargetDivisionID}
	path, err := g.ValidateOrder(req)
	if err != nil {
		g.endMessenger(m, MessageCancelled, string(CodeOf(err)))
		return
	}
	g.pending = append(g.pending, pendingOrder{order: o, path: path})
	g.endMessenger(m, MessageDelivered, "delivered")
}

// ---------------------------------------------------------------------------
// Command unit lifecycle
// ---------------------------------------------------------------------------

// updateCommand follows the host divisions (incapacitated while routed,
// eliminated when destroyed) and handles the general's succession.
func (g *Game) updateCommand() {
	for _, u := range g.commandOrder {
		if u.Status == CommandEliminated {
			continue
		}
		host := g.divisions[u.HostDivisionID]
		switch {
		case host == nil || !host.Alive():
			g.setCommandStatus(u, CommandEliminated, "host_destroyed")
		case host.Routed:
			g.setCommandStatus(u, CommandIncapacitated, "host_routed")
		default:
			g.setCommandStatus(u, CommandActive, "host_rallied")
		}
	}
	for _, pid := range g.playerOrder {
		a := g.armies[pid]
		if a == nil || a.GeneralID == "" {
			continue
		}
		if gen := g.commandUnits[a.GeneralID]; gen.Status != CommandEliminated {
			a.successionAt = -1
			continue
		}
		if a.successionAt < 0 {
			a.successionAt = g.CurrentTick + int64(g.Rules.Command.SuccessionDelayTicks)
			g.log.Info("general lost, succession pending", "game_id", g.ID, "player_id", pid, "until_tick", a.successionAt)
		}
		if g.CurrentTick < a.successionAt {
			continue
		}
		for _, u := range g.commandOrder {
			if u.PlayerID == pid && u.Role == RoleCommander && u.Status == CommandActive {
				g.promote(a, u)
				break
			}
		}
	}
}

// promote makes commander u the general of army a. Its divisions keep
// reporting to it.
func (g *Game) promote(a *Army, u *CommandUnit) {
	u.Role = RoleGeneral
	g.setRadii(u)
	a.GeneralID = u.ID
	a.successionAt = -1
	g.emit(CommandUpdated{At: g.CurrentTick, UnitID: u.ID, PlayerID: u.PlayerID, Role: u.Role, Status: u.Status, Reason: "promoted"})
	g.log.Info("commander promoted to general", "game_id", g.ID, "player_id", u.PlayerID, "unit_id", u.ID, "tick", g.CurrentTick)
}

func (g *Game) setCommandStatus(u *CommandUnit, s CommandStatus, reason string) {
	if u.Status == s {
		return
	}
	u.Status = s
	g.emit(CommandUpdated{At: g.CurrentTick, UnitID: u.ID, PlayerID: u.PlayerID, Role: u.Role, Status: s, Reason: reason})
	g.log.Info("command unit "+string(s), "game_id", g.ID, "player_id", u.PlayerID, "unit_id", u.ID, "role", u.Role, "reason", reason, "tick", g.CurrentTick)
}

// AssignCommander puts a division under another command unit of the same
// player (e.g. after its commander was eliminated). The new unit must have
// the division within its comm radius (it takes command in person), so a
// reassignment can never be used to skip a messenger ride. It takes effect
// immediately.
func (g *Game) AssignCommander(pid player.ID, divID DivisionID, unitID CommandUnitID) error {
	if g.Status != StatusRunning {
		return newErr(CodeGameNotRunning, "game is %s", g.Status)
	}
	d, ok := g.divisions[divID]
	switch {
	case !ok:
		return newErr(CodeDivisionNotFound, "division %s does not exist", divID)
	case d.PlayerID != pid:
		return newErr(CodeNotOwner, "division %s belongs to another player", divID)
	case !d.Alive():
		return newErr(CodeDivisionDestroyed, "division %s is destroyed", divID)
	}
	u, ok := g.commandUnits[unitID]
	switch {
	case !ok || u.PlayerID != pid:
		return newErr(CodeCommanderNotFound, "command unit %s does not exist", unitID)
	case u.Status != CommandActive:
		return newErr(CodeCommanderInactive, "command unit %s is %s", unitID, u.Status)
	case !g.inRadius(u, d, u.CommRadius):
		return newErr(CodeCommanderOutOfRange, "division %s is outside the comm radius of %s", divID, unitID)
	}
	// A commander's host division always reports to that commander.
	for _, host := range g.commandOrder {
		if host.HostDivisionID == divID && host.Role == RoleCommander && host.Status != CommandEliminated && host.ID != unitID {
			return newErr(CodeInvalidAssignment, "division %s hosts %s and cannot report to another unit", divID, host.ID)
		}
	}
	if d.CommanderID == unitID {
		return nil
	}
	d.CommanderID = unitID
	g.log.Info("commander assigned", "game_id", g.ID, "player_id", pid, "division_id", divID, "unit_id", unitID, "tick", g.CurrentTick)
	g.emit(DivisionUpdated{At: g.CurrentTick, DivisionID: d.ID, Reason: "commander_assigned"})
	return nil
}
