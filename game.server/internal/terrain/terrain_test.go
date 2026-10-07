package terrain

import (
	"testing"

	"gameserver/pkg/geom"
)

func TestDefaultTableValues(t *testing.T) {
	tb := DefaultTable()
	if err := tb.Validate(); err != nil {
		t.Fatalf("default table invalid: %v", err)
	}
	cases := []struct {
		typ            Type
		move, atk, def float64
		passable       bool
	}{
		{Plain, 1.0, 1.0, 1.0, true},
		{Forest, 0.7, 0.9, 1.2, true},
		{Hill, 0.8, 1.1, 1.3, true},
		{Water, 0, 0, 0, false},
	}
	for _, c := range cases {
		m := tb.Get(c.typ)
		if m.Movement != c.move || m.Attack != c.atk || m.Defense != c.def {
			t.Errorf("%s: got %+v", c.typ, m)
		}
		if m.Passable() != c.passable {
			t.Errorf("%s: passable=%v, want %v", c.typ, m.Passable(), c.passable)
		}
	}
}

func TestTableValidateRejectsMissingType(t *testing.T) {
	tb := DefaultTable()
	delete(tb, Hill)
	if err := tb.Validate(); err == nil {
		t.Fatal("expected error for missing terrain type")
	}
}

func TestMapLookups(t *testing.T) {
	rows := []string{
		"PPFF",
		"PHWW",
	}
	m, err := NewMap(rows, 10, DefaultTable(), [2]geom.Vec2{{X: 5, Y: 5}, {X: 15, Y: 5}})
	if err != nil {
		t.Fatal(err)
	}
	if m.Width() != 40 || m.Height() != 20 {
		t.Fatalf("size = %vx%v", m.Width(), m.Height())
	}
	checks := []struct {
		p    geom.Vec2
		want Type
	}{
		{geom.V(1, 1), Plain},
		{geom.V(25, 5), Forest},
		{geom.V(15, 15), Hill},
		{geom.V(35, 15), Water},
		{geom.V(-1, 5), Water}, // out of bounds counts as impassable
		{geom.V(40, 5), Water},
	}
	for _, c := range checks {
		if got := m.TypeAt(c.p); got != c.want {
			t.Errorf("TypeAt(%v) = %s, want %s", c.p, got, c.want)
		}
	}
	if m.Passable(geom.V(35, 15)) {
		t.Error("water must not be passable")
	}
	if got := m.ModifiersAt(geom.V(15, 15)).Defense; got != 1.3 {
		t.Errorf("hill defense = %v", got)
	}
	if c := m.Clamp(geom.V(-5, 100)); !m.InBounds(c) {
		t.Errorf("clamped point %v outside map", c)
	}
	enc := m.EncodeRows()
	for i := range rows {
		if enc[i] != rows[i] {
			t.Errorf("EncodeRows()[%d] = %q, want %q", i, enc[i], rows[i])
		}
	}
}

func TestNewMapErrors(t *testing.T) {
	spawns := [2]geom.Vec2{{X: 1, Y: 1}, {X: 1, Y: 1}}
	if _, err := NewMap([]string{"PP", "P"}, 10, DefaultTable(), spawns); err == nil {
		t.Error("ragged rows accepted")
	}
	if _, err := NewMap([]string{"PX"}, 10, DefaultTable(), spawns); err == nil {
		t.Error("unknown code accepted")
	}
	if _, err := NewMap([]string{"WP"}, 10, DefaultTable(), spawns); err == nil {
		t.Error("spawn on water accepted")
	}
}

func TestDefaultMapIsValid(t *testing.T) {
	m, err := DefaultMap(DefaultTable())
	if err != nil {
		t.Fatal(err)
	}
	// The river splits the map but fords must exist.
	fords := 0
	for r := 0; r < m.Rows; r++ {
		if m.CellPassable(Cell{Col: 19, Row: r}) {
			fords++
		}
	}
	if fords == 0 || fords == m.Rows {
		t.Fatalf("expected a river with fords, got %d passable rows of %d", fords, m.Rows)
	}
}
