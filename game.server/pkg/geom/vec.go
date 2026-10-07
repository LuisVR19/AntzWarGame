// Package geom provides minimal 2D vector math used by the simulation.
package geom

import "math"

// Vec2 is a point or direction in world space.
type Vec2 struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

func V(x, y float64) Vec2 { return Vec2{X: x, Y: y} }

func (a Vec2) Add(b Vec2) Vec2      { return Vec2{a.X + b.X, a.Y + b.Y} }
func (a Vec2) Sub(b Vec2) Vec2      { return Vec2{a.X - b.X, a.Y - b.Y} }
func (a Vec2) Scale(s float64) Vec2 { return Vec2{a.X * s, a.Y * s} }
func (a Vec2) Len() float64         { return math.Hypot(a.X, a.Y) }
func (a Vec2) Dist(b Vec2) float64  { return a.Sub(b).Len() }
func (a Vec2) Equal(b Vec2) bool    { return a.Dist(b) < 1e-9 }
func (a Vec2) IsFinite() bool       { return isFinite(a.X) && isFinite(a.Y) }
func isFinite(f float64) bool       { return !math.IsNaN(f) && !math.IsInf(f, 0) }

// Normalize returns the unit vector in the direction of a, or the zero vector.
func (a Vec2) Normalize() Vec2 {
	l := a.Len()
	if l == 0 {
		return Vec2{}
	}
	return Vec2{a.X / l, a.Y / l}
}

// MoveTowards returns the point reached by moving from a towards b at most maxDist.
func (a Vec2) MoveTowards(b Vec2, maxDist float64) Vec2 {
	d := b.Sub(a)
	l := d.Len()
	if l <= maxDist || l == 0 {
		return b
	}
	return a.Add(d.Scale(maxDist / l))
}
