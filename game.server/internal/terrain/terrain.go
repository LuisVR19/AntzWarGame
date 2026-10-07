// Package terrain defines terrain types, their modifiers and the tile map.
package terrain

import "fmt"

// Type identifies a terrain kind.
type Type string

const (
	Plain  Type = "PLAIN"
	Forest Type = "FOREST"
	Hill   Type = "HILL"
	Water  Type = "WATER"
)

// AllTypes lists terrain types in a stable order.
var AllTypes = []Type{Plain, Forest, Hill, Water}

// Code returns the single-character code used to serialize the map.
func (t Type) Code() byte {
	switch t {
	case Forest:
		return 'F'
	case Hill:
		return 'H'
	case Water:
		return 'W'
	default:
		return 'P'
	}
}

// TypeFromCode is the inverse of Code.
func TypeFromCode(c byte) (Type, error) {
	switch c {
	case 'P':
		return Plain, nil
	case 'F':
		return Forest, nil
	case 'H':
		return Hill, nil
	case 'W':
		return Water, nil
	}
	return "", fmt.Errorf("unknown terrain code %q", c)
}

// Modifiers are multiplicative factors applied by a terrain type.
type Modifiers struct {
	Movement   float64 `json:"movement_modifier"`
	Attack     float64 `json:"attack_modifier"`
	Defense    float64 `json:"defense_modifier"`
	Visibility float64 `json:"visibility_modifier"`
}

// Passable reports whether units can enter terrain with these modifiers.
func (m Modifiers) Passable() bool { return m.Movement > 0 }

// Table maps each terrain type to its modifiers. It is the single source of
// truth for terrain values and is overridable from configuration.
type Table map[Type]Modifiers

// DefaultTable returns the default terrain values.
func DefaultTable() Table {
	return Table{
		Plain:  {Movement: 1.0, Attack: 1.0, Defense: 1.0, Visibility: 1.0},
		Forest: {Movement: 0.7, Attack: 0.9, Defense: 1.2, Visibility: 0.6},
		Hill:   {Movement: 0.8, Attack: 1.1, Defense: 1.3, Visibility: 1.3},
		Water:  {Movement: 0.0, Attack: 0.0, Defense: 0.0, Visibility: 1.0},
	}
}

// Get returns the modifiers for t, falling back to neutral values.
func (tb Table) Get(t Type) Modifiers {
	if m, ok := tb[t]; ok {
		return m
	}
	return Modifiers{Movement: 1, Attack: 1, Defense: 1, Visibility: 1}
}

// Validate checks that every terrain type is defined with sane values.
func (tb Table) Validate() error {
	for _, t := range AllTypes {
		m, ok := tb[t]
		if !ok {
			return fmt.Errorf("terrain %s: missing modifiers", t)
		}
		if m.Movement < 0 || m.Attack < 0 || m.Defense < 0 || m.Visibility < 0 {
			return fmt.Errorf("terrain %s: modifiers must be >= 0", t)
		}
		if m.Movement > 0 && m.Defense == 0 {
			return fmt.Errorf("terrain %s: passable terrain needs defense > 0", t)
		}
	}
	return nil
}
