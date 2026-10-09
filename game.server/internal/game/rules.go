package game

import (
	"errors"
	"fmt"

	"gameserver/internal/combat"
	"gameserver/pkg/geom"
)

// DivisionTemplate describes a division created at game start. Offset is
// relative to the side's spawn and mirrored horizontally for side 1.
//
// Type picks a unit type (Rules.UnitTypes): its stats are used for every
// stat the template leaves at zero. Formation is the starting formation
// (empty = FormationRules.Default).
type DivisionTemplate struct {
	Name      string    `json:"name"`
	Type      string    `json:"type,omitempty"`
	Formation string    `json:"formation,omitempty"`
	Offset    geom.Vec2 `json:"offset"`
	UnitCount int       `json:"unit_count"`
	// Stats: 0 (omitted) = the value of Type.
	Attack     float64 `json:"attack,omitempty"`
	Defense    float64 `json:"defense,omitempty"`
	Speed      float64 `json:"speed,omitempty"` // world units per second
	Morale     float64 `json:"morale,omitempty"`
	Experience float64 `json:"experience,omitempty"`
	// Leads makes this division host a command unit: "general" or the name
	// of a commander. The unit moves with the division and is eliminated
	// with it.
	Leads string `json:"leads,omitempty"`
	// Commander is the name of the commander the division reports to.
	// Empty: it reports directly to the general.
	Commander string `json:"commander,omitempty"`
}

// LeadsGeneral is the DivisionTemplate.Leads value of the general's host.
const LeadsGeneral = "general"

// CommandRules tunes the chain of command. An army whose templates have no
// Leads has no chain of command: all its orders are immediate.
type CommandRules struct {
	GeneralCommRadius        float64 `json:"general_comm_radius"`
	GeneralInfluenceRadius   float64 `json:"general_influence_radius"`
	CommanderCommRadius      float64 `json:"commander_comm_radius"`
	CommanderInfluenceRadius float64 `json:"commander_influence_radius"`
	// GeneralRelay: a division out of its commander's range still gets
	// orders immediately when it is within the general's comm radius.
	GeneralRelay bool `json:"general_relay"`
	// MessengerSpeed in world units per second (terrain modifiers apply).
	MessengerSpeed float64 `json:"messenger_speed"`
	// MessengerDeliveryRange: distance at which a messenger hands the order over.
	MessengerDeliveryRange float64 `json:"messenger_delivery_range"`
	// LeadershipMoraleBonus is added to the morale used in combat by
	// divisions inside the influence radius of their commander or general.
	// It is computed every round, never stored.
	LeadershipMoraleBonus float64 `json:"leadership_morale_bonus"`
	// LeadershipRecoveryFactor multiplies out-of-combat morale recovery
	// inside the influence radius.
	LeadershipRecoveryFactor float64 `json:"leadership_recovery_factor"`
	// SuccessionDelayTicks: after the general is eliminated, the first
	// active commander takes over after this delay.
	SuccessionDelayTicks int `json:"succession_delay_ticks"`
}

// DefaultCommandRules returns the default chain-of-command tuning.
func DefaultCommandRules() CommandRules {
	return CommandRules{
		GeneralCommRadius:        450,
		GeneralInfluenceRadius:   450,
		CommanderCommRadius:      350,
		CommanderInfluenceRadius: 350,
		MessengerSpeed:           120,
		MessengerDeliveryRange:   25,
		LeadershipMoraleBonus:    10,
		LeadershipRecoveryFactor: 1.5,
		SuccessionDelayTicks:     100,
	}
}

// Validate checks the chain-of-command tuning.
func (c CommandRules) Validate() error {
	switch {
	case c.GeneralCommRadius < 0 || c.GeneralInfluenceRadius < 0 || c.CommanderCommRadius < 0 || c.CommanderInfluenceRadius < 0:
		return errors.New("rules: command radii must be >= 0")
	case c.MessengerSpeed <= 0 || c.MessengerDeliveryRange <= 0:
		return errors.New("rules: messenger_speed and messenger_delivery_range must be > 0")
	case c.LeadershipMoraleBonus < 0 || c.LeadershipRecoveryFactor < 1:
		return errors.New("rules: leadership_morale_bonus must be >= 0 and leadership_recovery_factor >= 1")
	case c.SuccessionDelayTicks < 0:
		return errors.New("rules: succession_delay_ticks must be >= 0")
	}
	return nil
}

// Rules holds every tunable of the simulation. Values come from config.
type Rules struct {
	TickRate             int   `json:"tick_rate"`             // ticks per second
	StartCountdownTicks  int   `json:"start_countdown_ticks"` // STARTING duration
	MaxDurationTicks     int64 `json:"max_duration_ticks"`    // 0 = unlimited
	DisconnectGraceTicks int64 `json:"disconnect_grace_ticks"`

	EngagementRange    float64 `json:"engagement_range"`
	DisengageRange     float64 `json:"disengage_range"`
	CombatRoundTicks   int     `json:"combat_round_ticks"`
	PathRecomputeTicks int     `json:"path_recompute_ticks"`

	DestroyedUnitThreshold   int     `json:"destroyed_unit_threshold"`
	RoutMoraleThreshold      float64 `json:"rout_morale_threshold"`
	RallyMoraleThreshold     float64 `json:"rally_morale_threshold"`
	MoraleRecoveryPerSecond  float64 `json:"morale_recovery_per_second"`
	MaxMorale                float64 `json:"max_morale"`
	FatigueMovePerSecond     float64 `json:"fatigue_move_per_second"`
	FatigueRecoveryPerSecond float64 `json:"fatigue_recovery_per_second"`
	RetreatSpeedMultiplier   float64 `json:"retreat_speed_multiplier"`
	// MinFatigueSpeedFactor is the speed factor at 100 fatigue.
	MinFatigueSpeedFactor float64 `json:"min_fatigue_speed_factor"`

	Army    []DivisionTemplate `json:"army"`
	Combat  combat.Params      `json:"combat"`
	Command CommandRules       `json:"command"`

	// Formations and unit types (formation.go). Each division has its own
	// type (base stats, ranged attack) and formation, which it can change.
	Formations     map[string]Formation `json:"formations"`
	FormationRules FormationRules       `json:"formation_rules"`
	UnitTypes      map[string]UnitType  `json:"unit_types"`
}

// DefaultRules returns the default MVP tuning.
func DefaultRules() Rules {
	return Rules{
		TickRate:             10,
		StartCountdownTicks:  30,
		MaxDurationTicks:     20 * 60 * 10,
		DisconnectGraceTicks: 30 * 10,

		EngagementRange:    60,
		DisengageRange:     90,
		CombatRoundTicks:   10,
		PathRecomputeTicks: 5,

		DestroyedUnitThreshold:   100,
		RoutMoraleThreshold:      20,
		RallyMoraleThreshold:     50,
		MoraleRecoveryPerSecond:  1.0,
		MaxMorale:                100,
		FatigueMovePerSecond:     0.5,
		FatigueRecoveryPerSecond: 1.0,
		RetreatSpeedMultiplier:   1.2,
		MinFatigueSpeedFactor:    0.6,

		Army: []DivisionTemplate{
			// Infantry Command rides with the 1st Infantry and commands both
			// infantry divisions; the general rides with the armored reserve.
			{Name: "1st Infantry", Type: UnitWorker, Offset: geom.V(0, -150), UnitCount: 3000,
				Leads: "Infantry Command", Commander: "Infantry Command"},
			{Name: "2nd Infantry", Type: UnitWorker, Offset: geom.V(0, 150), UnitCount: 3000,
				Commander: "Infantry Command"},
			{Name: "1st Armored", Type: UnitSoldier, Offset: geom.V(-80, 0), UnitCount: 2000,
				Leads: LeadsGeneral},
		},
		Combat:         combat.DefaultParams(),
		Command:        DefaultCommandRules(),
		Formations:     DefaultFormations(),
		FormationRules: DefaultFormationRules(),
		UnitTypes:      DefaultUnitTypes(),
	}
}

// DT returns the simulated seconds per tick.
func (r Rules) DT() float64 { return 1 / float64(r.TickRate) }

// Validate checks the rules for obviously broken values.
func (r Rules) Validate() error {
	switch {
	case r.TickRate <= 0 || r.TickRate > 60:
		return errors.New("rules: tick_rate must be in 1..60")
	case r.StartCountdownTicks < 0:
		return errors.New("rules: start_countdown_ticks must be >= 0")
	case r.EngagementRange <= 0:
		return errors.New("rules: engagement_range must be > 0")
	case r.DisengageRange < r.EngagementRange:
		return errors.New("rules: disengage_range must be >= engagement_range")
	case r.CombatRoundTicks <= 0:
		return errors.New("rules: combat_round_ticks must be > 0")
	case r.PathRecomputeTicks <= 0:
		return errors.New("rules: path_recompute_ticks must be > 0")
	case r.RallyMoraleThreshold < r.RoutMoraleThreshold:
		return errors.New("rules: rally_morale_threshold must be >= rout_morale_threshold")
	case r.MaxMorale <= 0:
		return errors.New("rules: max_morale must be > 0")
	case len(r.Army) == 0:
		return errors.New("rules: army must contain at least one division")
	}
	if err := r.validateFormations(); err != nil {
		return err
	}
	for i, raw := range r.Army {
		t := r.Resolved(raw)
		if _, ok := r.UnitTypes[t.Type]; raw.Type != "" && !ok {
			return fmt.Errorf("rules: army[%d] %q has unknown type %q", i, t.Name, raw.Type)
		}
		if !r.hasFormation(t.Formation) {
			return fmt.Errorf("rules: army[%d] %q has unknown formation %q", i, t.Name, raw.Formation)
		}
		if t.UnitCount <= r.DestroyedUnitThreshold || t.Speed <= 0 || t.Attack < 0 || t.Defense <= 0 {
			return fmt.Errorf("rules: army[%d] %q has invalid stats", i, t.Name)
		}
	}
	if err := r.Command.Validate(); err != nil {
		return err
	}
	return r.validateChainOfCommand()
}

// validateChainOfCommand checks the Leads/Commander references of the army.
func (r Rules) validateChainOfCommand() error {
	leaders := map[string]bool{}
	generals := 0
	for i, t := range r.Army {
		switch {
		case t.Leads == "":
		case leaders[t.Leads]:
			return fmt.Errorf("rules: army[%d] %q: %q is led by two divisions", i, t.Name, t.Leads)
		case t.Leads == LeadsGeneral:
			generals++
		}
		if t.Leads != "" {
			leaders[t.Leads] = true
		}
	}
	for i, t := range r.Army {
		if t.Commander != "" && (t.Commander == LeadsGeneral || !leaders[t.Commander]) {
			return fmt.Errorf("rules: army[%d] %q reports to unknown commander %q", i, t.Name, t.Commander)
		}
		if t.Leads != "" && t.Leads != LeadsGeneral && t.Commander != "" && t.Commander != t.Leads {
			return fmt.Errorf("rules: army[%d] %q hosts %q and must report to it", i, t.Name, t.Leads)
		}
	}
	if len(leaders) > 0 && generals != 1 {
		return errors.New("rules: an army with command units needs exactly one general")
	}
	return nil
}
