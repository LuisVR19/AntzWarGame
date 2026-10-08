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
// passable tiles.
func (m *Map) LineOfPassage(a, b geom.Vec2) bool { return m.LineMinMovement(a, b) > 0 }

// LineMinMovement returns the lowest movement modifier among the tiles the
// segment a-b passes through (0 if any of them is impassable or the segment
// leaves the map). Tiles are traversed exactly, so a segment that only clips
// the corner of a water tile is reported as blocked.
func (m *Map) LineMinMovement(a, b geom.Vec2) float64 {
	if !m.InBounds(a) || !m.InBounds(b) {
		return 0
	}
	minMod := math.Inf(1)
	m.segmentCells(a, b, func(c Cell) bool {
		minMod = math.Min(minMod, m.CellModifiers(c).Movement)
		return minMod > 0
	})
	return minMod
}

// segmentCells calls visit for every tile crossed by the segment a-b, in
// order, until visit returns false (grid traversal of Amanatides & Woo).
// When the segment passes exactly through a tile corner both side tiles are
// visited, so diagonal moves cannot slip between two impassable tiles.
func (m *Map) segmentCells(a, b geom.Vec2, visit func(Cell) bool) {
	start, end := m.CellAt(a), m.CellAt(b)
	x0, y0 := a.X/m.CellSize, a.Y/m.CellSize
	dx, dy := b.X/m.CellSize-x0, b.Y/m.CellSize-y0
	axis := func(c int, p0, d float64) (step int, tMax, tDelta float64) {
		switch {
		case d > 0:
			return 1, (float64(c+1) - p0) / d, 1 / d
		case d < 0:
			return -1, (float64(c) - p0) / d, -1 / d
		}
		return 0, math.Inf(1), math.Inf(1)
	}
	stepX, tMaxX, tDeltaX := axis(start.Col, x0, dx)
	stepY, tMaxY, tDeltaY := axis(start.Row, y0, dy)
	c := start
	if !visit(c) {
		return
	}
	// Each iteration moves at least one tile closer to the end. Crossings at
	// t >= 1 are past b (b may lie exactly on a grid line); end is visited
	// explicitly below.
	for n := abs(end.Col-start.Col) + abs(end.Row-start.Row); n > 0 && c != end; n-- {
		if min(tMaxX, tMaxY) >= 1 {
			break
		}
		switch {
		case tMaxX < tMaxY:
			c.Col += stepX
			tMaxX += tDeltaX
		case tMaxY < tMaxX:
			c.Row += stepY
			tMaxY += tDeltaY
		default:
			if !visit(Cell{Col: c.Col + stepX, Row: c.Row}) || !visit(Cell{Col: c.Col, Row: c.Row + stepY}) {
				return
			}
			c.Col += stepX
			c.Row += stepY
			tMaxX += tDeltaX
			tMaxY += tDeltaY
			n--
		}
		if !visit(c) {
			return
		}
	}
	if c != end {
		visit(end)
	}
}

func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}
