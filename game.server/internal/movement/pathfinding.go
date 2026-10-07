// Package movement computes server-side unit movement: path finding over the
// terrain grid and per-tick position integration. It is independent of the
// game package so it can be tested and replaced in isolation.
package movement

import (
	"container/heap"
	"errors"
	"math"

	"gameserver/internal/terrain"
	"gameserver/pkg/geom"
)

var (
	ErrOutOfBounds  = errors.New("destination is outside the map")
	ErrImpassable   = errors.New("destination terrain is impassable")
	ErrUnreachable  = errors.New("destination is unreachable")
	ErrInvalidStart = errors.New("start position is not passable")
)

// FindPath returns the waypoints (excluding from, ending exactly at to) of the
// cheapest route between two world positions. Cost of a tile is inversely
// proportional to its movement modifier, so faster terrain is preferred.
func FindPath(m *terrain.Map, from, to geom.Vec2) ([]geom.Vec2, error) {
	if !m.InBounds(to) {
		return nil, ErrOutOfBounds
	}
	if !m.Passable(to) {
		return nil, ErrImpassable
	}
	if !m.Passable(from) {
		return nil, ErrInvalidStart
	}
	start, goal := m.CellAt(from), m.CellAt(to)
	if start == goal {
		return []geom.Vec2{to}, nil
	}

	maxMod := 0.0
	for _, mod := range m.Table() {
		maxMod = math.Max(maxMod, mod.Movement)
	}
	idx := func(c terrain.Cell) int { return c.Row*m.Cols + c.Col }
	h := func(c terrain.Cell) float64 {
		return math.Hypot(float64(c.Col-goal.Col), float64(c.Row-goal.Row)) / maxMod
	}

	n := m.Cols * m.Rows
	gScore := make([]float64, n)
	for i := range gScore {
		gScore[i] = math.Inf(1)
	}
	came := make([]int, n)
	for i := range came {
		came[i] = -1
	}
	closed := make([]bool, n)

	open := &nodeHeap{}
	gScore[idx(start)] = 0
	heap.Push(open, node{cell: start, f: h(start)})

	found := false
	for open.Len() > 0 {
		cur := heap.Pop(open).(node)
		ci := idx(cur.cell)
		if closed[ci] {
			continue
		}
		if cur.cell == goal {
			found = true
			break
		}
		closed[ci] = true
		for _, d := range neighbors {
			nc := terrain.Cell{Col: cur.cell.Col + d.dc, Row: cur.cell.Row + d.dr}
			if !m.CellPassable(nc) {
				continue
			}
			// No corner cutting through impassable tiles on diagonals.
			if d.dc != 0 && d.dr != 0 {
				if !m.CellPassable(terrain.Cell{Col: cur.cell.Col + d.dc, Row: cur.cell.Row}) ||
					!m.CellPassable(terrain.Cell{Col: cur.cell.Col, Row: cur.cell.Row + d.dr}) {
					continue
				}
			}
			ni := idx(nc)
			if closed[ni] {
				continue
			}
			// Average of both tiles' cost, scaled by step length.
			cost := d.len * 0.5 * (1/m.CellModifiers(cur.cell).Movement + 1/m.CellModifiers(nc).Movement)
			if g := gScore[ci] + cost; g < gScore[ni] {
				gScore[ni] = g
				came[ni] = ci
				heap.Push(open, node{cell: nc, f: g + h(nc)})
			}
		}
	}
	if !found {
		return nil, ErrUnreachable
	}

	// Rebuild cell chain goal -> start.
	var cells []terrain.Cell
	for i := idx(goal); i != idx(start); i = came[i] {
		cells = append(cells, terrain.Cell{Col: i % m.Cols, Row: i / m.Cols})
	}
	points := make([]geom.Vec2, 0, len(cells)+1)
	for i := len(cells) - 1; i >= 1; i-- { // skip goal cell; use exact target
		points = append(points, m.CellCenter(cells[i]))
	}
	points = append(points, to)
	return smooth(m, from, points), nil
}

// smooth removes intermediate waypoints when a straight segment is passable
// and not slower than the terrain the grid path traversed.
func smooth(m *terrain.Map, from geom.Vec2, pts []geom.Vec2) []geom.Vec2 {
	out := make([]geom.Vec2, 0, len(pts))
	anchor := from
	i := 0
	for i < len(pts) {
		best := i
		pathMin := math.Inf(1)
		for j := i; j < len(pts); j++ {
			pathMin = math.Min(pathMin, m.ModifiersAt(pts[j]).Movement)
			if lm := m.LineMinMovement(anchor, pts[j]); lm > 0 && lm >= pathMin {
				best = j
			}
		}
		out = append(out, pts[best])
		anchor = pts[best]
		i = best + 1
	}
	return out
}

type dir struct {
	dc, dr int
	len    float64
}

var neighbors = []dir{
	{1, 0, 1}, {-1, 0, 1}, {0, 1, 1}, {0, -1, 1},
	{1, 1, math.Sqrt2}, {1, -1, math.Sqrt2}, {-1, 1, math.Sqrt2}, {-1, -1, math.Sqrt2},
}

type node struct {
	cell terrain.Cell
	f    float64
}

type nodeHeap []node

func (h nodeHeap) Len() int           { return len(h) }
func (h nodeHeap) Less(i, j int) bool { return h[i].f < h[j].f }
func (h nodeHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *nodeHeap) Push(x any)        { *h = append(*h, x.(node)) }
func (h *nodeHeap) Pop() any          { old := *h; n := old[len(old)-1]; *h = old[:len(old)-1]; return n }
