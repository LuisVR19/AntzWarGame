// Package ai implements a simple rule-based opponent. A Bot only reads the
// GameView its player is allowed to see and answers with OrderRequests that
// go through the same validation as a human's orders: it never touches the
// game state directly. It has no knowledge of rooms or networking.
package ai

import "errors"

// Config holds the tunables of the bot. Distances are in world units.
type Config struct {
	// DecisionIntervalTicks is how often the bot evaluates the battle,
	// independently of the simulation tick rate.
	DecisionIntervalTicks int `json:"decision_interval_ticks"`
	// BaseThreatRadius: enemies closer than this to the bot's deployment
	// point are threats and switch the bot to defense.
	BaseThreatRadius float64 `json:"base_threat_radius"`
	// HomeRadius: a weak division closer than this to its base stays there
	// defending instead of retreating further.
	HomeRadius float64 `json:"home_radius"`
	// RetreatStrengthRatio: units/max_units below which a division retreats
	// for good (troops do not regenerate).
	RetreatStrengthRatio float64 `json:"retreat_strength_ratio"`
	// RetreatMorale: morale below which a division retreats until it
	// recovers RecoverMorale (hysteresis avoids attack/retreat flapping).
	RetreatMorale float64 `json:"retreat_morale"`
	RecoverMorale float64 `json:"recover_morale"`
	// MinAttackOdds: own power (plus allies already sent) / target power
	// required to attack. Below it the division regroups with allies.
	MinAttackOdds float64 `json:"min_attack_odds"`
	// KeepAttackOdds: a division already attacking keeps its target while
	// the odds stay above this (hysteresis, avoids attack/regroup flapping).
	KeepAttackOdds float64 `json:"keep_attack_odds"`
	// RegroupRadius: an ally within this distance means the division is
	// not isolated. Isolated divisions regroup with the nearest ally that is
	// closer to the base, so groups converge instead of chasing each other.
	RegroupRadius float64 `json:"regroup_radius"`
	// MaxAttackersPerTarget spreads the army over several targets while
	// there are unassigned ones.
	MaxAttackersPerTarget int `json:"max_attackers_per_target"`
	// TargetSwitchFactor: a new target must score this many times better
	// than the current one to replace it.
	TargetSwitchFactor float64 `json:"target_switch_factor"`
	// MoveTolerance: two MOVE orders whose destinations are closer than
	// this are considered the same order.
	MoveTolerance float64 `json:"move_tolerance"`
	// ReissueCooldownTicks: the same order is not sent again to a division
	// before this many ticks (covers rejected or just-completed orders).
	ReissueCooldownTicks int `json:"reissue_cooldown_ticks"`
}

// DefaultConfig returns the default tuning.
func DefaultConfig() Config {
	return Config{
		DecisionIntervalTicks: 10,
		BaseThreatRadius:      500,
		HomeRadius:            250,
		RetreatStrengthRatio:  0.3,
		RetreatMorale:         30,
		RecoverMorale:         60,
		MinAttackOdds:         0.8,
		KeepAttackOdds:        0.5,
		RegroupRadius:         300,
		MaxAttackersPerTarget: 2,
		TargetSwitchFactor:    1.5,
		MoveTolerance:         100,
		ReissueCooldownTicks:  50,
	}
}

// Validate checks the configuration for obviously broken values.
func (c Config) Validate() error {
	switch {
	case c.DecisionIntervalTicks <= 0:
		return errors.New("ai: decision_interval_ticks must be > 0")
	case c.BaseThreatRadius < 0 || c.HomeRadius < 0 || c.RegroupRadius < 0 || c.MoveTolerance < 0:
		return errors.New("ai: radii must be >= 0")
	case c.RecoverMorale < c.RetreatMorale:
		return errors.New("ai: recover_morale must be >= retreat_morale")
	case c.MinAttackOdds <= 0:
		return errors.New("ai: min_attack_odds must be > 0")
	case c.KeepAttackOdds <= 0 || c.KeepAttackOdds > c.MinAttackOdds:
		return errors.New("ai: keep_attack_odds must be in (0, min_attack_odds]")
	case c.MaxAttackersPerTarget <= 0:
		return errors.New("ai: max_attackers_per_target must be > 0")
	case c.TargetSwitchFactor < 1:
		return errors.New("ai: target_switch_factor must be >= 1")
	case c.ReissueCooldownTicks < 0:
		return errors.New("ai: reissue_cooldown_ticks must be >= 0")
	}
	return nil
}
