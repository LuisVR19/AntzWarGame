package movement

import (
	"errors"
	"math"
	"testing"

	"gameserver/internal/terrain"
	"gameserver/pkg/geom"
)

func mustMap(t *testing.T, rows ...string) *terrain.Map {
	t.Helper()
	m, err := terrain.NewMap(rows, 10, terrain.DefaultTable(), [2]geom.Vec2{{X: 5, Y: 5}, {X: 5, Y: 5}})
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func near(a, b float64) bool { return math.Abs(a-b) < 1e-6 }

func TestStepOnPlain(t *testing.T) {
	m := mustMap(t, "PPPPPPPPPP")
	res := Step(m, StepInput{Position: geom.V(5, 5), Waypoints: []geom.Vec2{geom.V(95, 5)}, Speed: 30, Multiplier: 1, DT: 0.1})
	if !near(res.Position.X, 8) || !near(res.Moved, 3) {
		t.Fatalf("moved to %v (%.3f), want x=8", res.Position, res.Moved)
	}
	if res.Arrived || res.Blocked {
		t.Fatalf("unexpected flags %+v", res)
	}
}

func TestStepTerrainSlowsMovement(t *testing.T) {
	m := mustMap(t, "FFFFFFFFFF", "HHHHHHHHHH")
	forest := Step(m, StepInput{Position: geom.V(5, 5), Waypoints: []geom.Vec2{geom.V(95, 5)}, Speed: 10, Multiplier: 1, DT: 1})
	if !near(forest.Moved, 7) {
		t.Errorf("forest moved %.3f, want 7", forest.Moved)
	}
	hill := Step(m, StepInput{Position: geom.V(5, 15), Waypoints: []geom.Vec2{geom.V(95, 15)}, Speed: 10, Multiplier: 1, DT: 1})
	if !near(hill.Moved, 8) {
		t.Errorf("hill moved %.3f, want 8", hill.Moved)
	}
	slowed := Step(m, StepInput{Position: geom.V(5, 5), Waypoints: []geom.Vec2{geom.V(95, 5)}, Speed: 10, Multiplier: 0.5, DT: 1})
	if !near(slowed.Moved, 3.5) {
		t.Errorf("multiplier not applied: moved %.3f", slowed.Moved)
	}
}

func TestStepDoesNotOvershootAndFollowsWaypoints(t *testing.T) {
	m := mustMap(t, "PPPPPPPPPP", "PPPPPPPPPP")
	res := Step(m, StepInput{
		Position:  geom.V(5, 5),
		Waypoints: []geom.Vec2{geom.V(10, 5), geom.V(10, 10)},
		Speed:     100, Multiplier: 1, DT: 1,
	})
	if !res.Arrived || !res.Position.Equal(geom.V(10, 10)) || !near(res.Moved, 10) {
		t.Fatalf("got %+v", res)
	}
}

func TestStepStopsAtWater(t *testing.T) {
	m := mustMap(t, "PPWPP")
	res := Step(m, StepInput{Position: geom.V(5, 5), Waypoints: []geom.Vec2{geom.V(45, 5)}, Speed: 100, Multiplier: 1, DT: 1})
	if !res.Blocked {
		t.Fatalf("expected blocked, got %+v", res)
	}
	if !m.Passable(res.Position) {
		t.Fatalf("ended on impassable terrain at %v", res.Position)
	}
}

func TestStepStaysInsideMap(t *testing.T) {
	m := mustMap(t, "PPP")
	res := Step(m, StepInput{Position: geom.V(5, 5), Waypoints: []geom.Vec2{geom.V(500, 5)}, Speed: 1000, Multiplier: 1, DT: 1})
	if !m.InBounds(res.Position) {
		t.Fatalf("left the map: %v", res.Position)
	}
}

func TestFindPathAroundWater(t *testing.T) {
	m := mustMap(t,
		"PPPPP",
		"PPWPP",
		"PPWPP",
		"PPWPP",
	)
	from, to := geom.V(5, 35), geom.V(45, 35)
	path, err := FindPath(m, from, to)
	if err != nil {
		t.Fatal(err)
	}
	if !path[len(path)-1].Equal(to) {
		t.Fatalf("path must end at target, got %v", path)
	}
	prev := from
	for _, p := range path {
		if !m.LineOfPassage(prev, p) {
			t.Fatalf("segment %v -> %v crosses water", prev, p)
		}
		prev = p
	}
	// The detour must go through the top row.
	minY := math.Inf(1)
	for _, p := range path {
		minY = math.Min(minY, p.Y)
	}
	if minY >= 10 {
		t.Fatalf("path did not go around the river: %v", path)
	}
}

func TestFindPathErrors(t *testing.T) {
	m := mustMap(t,
		"PWP",
		"WWP",
	)
	if _, err := FindPath(m, geom.V(5, 5), geom.V(15, 5)); !errors.Is(err, ErrImpassable) {
		t.Errorf("water target: err = %v", err)
	}
	if _, err := FindPath(m, geom.V(5, 5), geom.V(25, 5)); !errors.Is(err, ErrUnreachable) {
		t.Errorf("enclosed start: err = %v", err)
	}
	if _, err := FindPath(m, geom.V(5, 5), geom.V(500, 5)); !errors.Is(err, ErrOutOfBounds) {
		t.Errorf("outside map: err = %v", err)
	}
}

func TestFindPathPrefersFasterTerrain(t *testing.T) {
	// Straight line crosses a forest band; a plain corridor exists on row 0.
	m := mustMap(t,
		"PPPPPPP",
		"PPFFFPP",
		"PPFFFPP",
	)
	path, err := FindPath(m, geom.V(5, 25), geom.V(65, 25))
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range path {
		if m.TypeAt(p) == terrain.Forest {
			t.Fatalf("path crosses forest although a faster detour exists: %v", path)
		}
	}
}

// Regression: leaving a ford next to the water, the smoothed straight line
// clipped the corner of a water tile between two samples and the unit got
// stuck ("blocked") on its first step.
func TestPathDoesNotClipWaterCorners(t *testing.T) {
	m, err := terrain.DefaultMap(terrain.DefaultTable())
	if err != nil {
		t.Fatal(err)
	}
	from, to := geom.V(961.5874634287455, 850.1943433885668), geom.V(657.77, 810.22)
	path, err := FindPath(m, from, to)
	if err != nil {
		t.Fatal(err)
	}
	pos := from
	for i := 0; i < 2000 && len(path) > 0; i++ {
		res := Step(m, StepInput{Position: pos, Waypoints: path, Speed: 30, Multiplier: 1, DT: 0.1})
		if res.Blocked {
			t.Fatalf("unit blocked at %v following %v", pos, path)
		}
		pos, path = res.Position, res.Waypoints
	}
	if !pos.Equal(to) {
		t.Fatalf("unit did not arrive: %v", pos)
	}
	if m.LineOfPassage(from, to) {
		t.Fatal("a segment clipping a water corner must not count as passable")
	}
}

// Regression: an end point lying exactly on a grid line, reached from the
// positive side, must be checked (it was skipped and water was "passable").
func TestLineOfPassageEndOnGridLine(t *testing.T) {
	m, err := terrain.NewMap([]string{"PPPPPPPPPP", "PPPPPPPPPP", "PPPPPPPPPP", "PPWPPPPPPP"}, 30,
		terrain.DefaultTable(), [2]geom.Vec2{{X: 5, Y: 5}, {X: 5, Y: 5}})
	if err != nil {
		t.Fatal(err)
	}
	if m.Passable(geom.V(60, 90)) || m.LineOfPassage(geom.V(285, 15), geom.V(60, 90)) {
		t.Fatal("segment ending in water reported as passable")
	}
	if !m.LineOfPassage(geom.V(285, 15), geom.V(90, 60)) {
		t.Fatal("segment ending exactly on a tile corner over plain must be passable")
	}
}
