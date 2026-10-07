package terrain

import "gameserver/pkg/geom"

// rect is an inclusive tile rectangle used to paint presets.
type rect struct {
	c0, r0, c1, r1 int
	t              Type
}

// DefaultRows returns the built-in 1v1 map: 40x24 tiles, a river through the
// middle with two fords, forests and hills distributed symmetrically.
func DefaultRows() []string {
	const cols, rows = 40, 24
	grid := make([][]byte, rows)
	for r := range grid {
		grid[r] = make([]byte, cols)
		for c := range grid[r] {
			grid[r][c] = Plain.Code()
		}
	}
	paint := []rect{
		// River (two tiles wide) with fords on rows 5-6 and 17-18.
		{19, 0, 20, 4, Water},
		{19, 7, 20, 16, Water},
		{19, 19, 20, 23, Water},
		// Forests.
		{8, 2, 12, 6, Forest},
		{27, 17, 31, 21, Forest},
		{14, 14, 17, 19, Forest},
		{22, 4, 25, 9, Forest},
		// Hills overlooking the fords and the center.
		{15, 3, 17, 7, Hill},
		{22, 16, 24, 20, Hill},
		{5, 10, 7, 13, Hill},
		{32, 10, 34, 13, Hill},
	}
	for _, p := range paint {
		for r := p.r0; r <= p.r1; r++ {
			for c := p.c0; c <= p.c1; c++ {
				grid[r][c] = p.t.Code()
			}
		}
	}
	out := make([]string, rows)
	for r := range grid {
		out[r] = string(grid[r])
	}
	return out
}

// DefaultCellSize is the world size of a tile in the default map.
const DefaultCellSize = 50.0

// DefaultSpawns are the deployment centers of the default map.
func DefaultSpawns() [2]geom.Vec2 {
	return [2]geom.Vec2{{X: 200, Y: 600}, {X: 1800, Y: 600}}
}

// DefaultMap builds the default map with the given terrain table.
func DefaultMap(table Table) (*Map, error) {
	return NewMap(DefaultRows(), DefaultCellSize, table, DefaultSpawns())
}
