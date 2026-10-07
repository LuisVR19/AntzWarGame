package terrain

import (
	"errors"
	"fmt"
	"math"

	"gameserver/pkg/geom"
)

// Cell is an integer tile coordinate.
type Cell struct{ Col, Row int }

// Map is a rectangular grid of terrain tiles. World coordinates go from
// (0,0) to (Width, Height); each tile is CellSize x CellSize world units.
// A Map is immutable after construction and safe for concurrent reads.
type Map struct {
	Cols, Rows int
	CellSize   float64
	tiles      []Type
	table      Table
	// Spawns holds the deployment center of each side (index = side).
	Spawns [2]geom.Vec2
}

// NewMap builds a map from rows of terrain codes (see Type.Code).
func NewMap(rows []string, cellSize float64, table Table, spawns [2]geom.Vec2) (*Map, error) {
	if len(rows) == 0 || len(rows[0]) == 0 {
		return nil, errors.New("terrain: empty map")
	}
	if cellSize <= 0 {
		return nil, errors.New("terrain: cell size must be > 0")
	}
	if err := table.Validate(); err != nil {
		return nil, err
	}
	m := &Map{Cols: len(rows[0]), Rows: len(rows), CellSize: cellSize, table: table, Spawns: spawns}
	m.tiles = make([]Type, 0, m.Cols*m.Rows)
	for r, line := range rows {
		if len(line) != m.Cols {
			return nil, fmt.Errorf("terrain: row %d has %d columns, want %d", r, len(line), m.Cols)
		}
		for i := 0; i < len(line); i++ {
			t, err := TypeFromCode(line[i])
			if err != nil {
				return nil, fmt.Errorf("terrain: row %d col %d: %w", r, i, err)
			}
			m.tiles = append(m.tiles, t)
		}
	}
	for side, s := range spawns {
		if !m.Passable(s) {
			return nil, fmt.Errorf("terrain: spawn of side %d is not passable", side)
		}
	}
	return m, nil
}

func (m *Map) Width() float64  { return float64(m.Cols) * m.CellSize }
func (m *Map) Height() float64 { return float64(m.Rows) * m.CellSize }
func (m *Map) Table() Table    { return m.table }

// InBounds reports whether p lies inside the map.
func (m *Map) InBounds(p geom.Vec2) bool {
	return p.IsFinite() && p.X >= 0 && p.Y >= 0 && p.X < m.Width() && p.Y < m.Height()
}

// Clamp returns p moved inside the map bounds.
func (m *Map) Clamp(p geom.Vec2) geom.Vec2 {
	const eps = 1e-6
	return geom.Vec2{
		X: math.Min(math.Max(p.X, 0), m.Width()-eps),
		Y: math.Min(math.Max(p.Y, 0), m.Height()-eps),
	}
}

// CellAt returns the tile containing p (clamped to the map).
func (m *Map) CellAt(p geom.Vec2) Cell {
	p = m.Clamp(p)
	return Cell{Col: int(p.X / m.CellSize), Row: int(p.Y / m.CellSize)}
}

// CellCenter returns the world position of the center of c.
func (m *Map) CellCenter(c Cell) geom.Vec2 {
	return geom.Vec2{X: (float64(c.Col) + 0.5) * m.CellSize, Y: (float64(c.Row) + 0.5) * m.CellSize}
}

// ValidCell reports whether c is inside the grid.
func (m *Map) ValidCell(c Cell) bool {
	return c.Col >= 0 && c.Row >= 0 && c.Col < m.Cols && c.Row < m.Rows
}

// TypeAtCell returns the terrain of c. Out-of-grid cells are Water (impassable).
func (m *Map) TypeAtCell(c Cell) Type {
	if !m.ValidCell(c) {
		return Water
	}
	return m.tiles[c.Row*m.Cols+c.Col]
}

// TypeAt returns the terrain type at world position p.
func (m *Map) TypeAt(p geom.Vec2) Type {
	if !m.InBounds(p) {
		return Water
	}
	return m.TypeAtCell(m.CellAt(p))
}

// ModifiersAt returns the terrain modifiers at world position p.
func (m *Map) ModifiersAt(p geom.Vec2) Modifiers { return m.table.Get(m.TypeAt(p)) }

// CellModifiers returns the modifiers of tile c.
func (m *Map) CellModifiers(c Cell) Modifiers { return m.table.Get(m.TypeAtCell(c)) }

// Passable reports whether a unit may stand at p.
func (m *Map) Passable(p geom.Vec2) bool { return m.InBounds(p) && m.ModifiersAt(p).Passable() }

// CellPassable reports whether tile c can be entered.
func (m *Map) CellPassable(c Cell) bool { return m.ValidCell(c) && m.CellModifiers(c).Passable() }

// Rows returns the map encoded as one string per row (for clients).
func (m *Map) EncodeRows() []string {
	out := make([]string, m.Rows)
	buf := make([]byte, m.Cols)
	for r := 0; r < m.Rows; r++ {
		for c := 0; c < m.Cols; c++ {
			buf[c] = m.tiles[r*m.Cols+c].Code()
		}
		out[r] = string(buf)
	}
	return out
}

// LineOfPassage reports whether a straight segment from a to b crosses only
// passable tiles. It samples the segment at a fraction of the cell size.
func (m *Map) LineOfPassage(a, b geom.Vec2) bool {
	d := a.Dist(b)
	step := m.CellSize / 4
	n := int(math.Ceil(d/step)) + 1
	for i := 0; i <= n; i++ {
		t := float64(i) / float64(n)
		p := geom.Vec2{X: a.X + (b.X-a.X)*t, Y: a.Y + (b.Y-a.Y)*t}
		if !m.Passable(p) {
			return false
		}
	}
	return true
}

// LineMinMovement returns the lowest movement modifier found along the
// segment a-b (0 if any sample is impassable).
func (m *Map) LineMinMovement(a, b geom.Vec2) float64 {
	d := a.Dist(b)
	step := m.CellSize / 4
	n := int(math.Ceil(d/step)) + 1
	minMod := math.Inf(1)
	for i := 0; i <= n; i++ {
		t := float64(i) / float64(n)
		p := geom.Vec2{X: a.X + (b.X-a.X)*t, Y: a.Y + (b.Y-a.Y)*t}
		if !m.InBounds(p) {
			return 0
		}
		minMod = math.Min(minMod, m.ModifiersAt(p).Movement)
	}
	return minMod
}
