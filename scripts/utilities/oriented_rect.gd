class_name OrientedRect
extends RefCounted
## Static helpers for oriented rectangles on the ground (XZ) plane.
##
## A rectangle is a centre, a unit forward axis, a half width (across) and a
## half length (along forward). Everything here is allocation-free so the
## near-miss detector can call it every physics tick.


static func overlaps(c1: Vector2, f1: Vector2, hw1: float, hl1: float,
		c2: Vector2, f2: Vector2, hw2: float, hl2: float) -> bool:
	var r1 := Vector2(-f1.y, f1.x)
	var r2 := Vector2(-f2.y, f2.x)
	var d := c2 - c1
	if _separated_on(d, f1, f1, r1, hw1, hl1, f2, r2, hw2, hl2):
		return false
	if _separated_on(d, r1, f1, r1, hw1, hl1, f2, r2, hw2, hl2):
		return false
	if _separated_on(d, f2, f1, r1, hw1, hl1, f2, r2, hw2, hl2):
		return false
	if _separated_on(d, r2, f1, r1, hw1, hl1, f2, r2, hw2, hl2):
		return false
	return true


## Distance from point `p` to the rectangle (0 when inside).
static func point_distance(p: Vector2, c: Vector2, f: Vector2, hw: float, hl: float) -> float:
	var d := p - c
	var r := Vector2(-f.y, f.x)
	var ex := maxf(absf(d.dot(r)) - hw, 0.0)
	var ey := maxf(absf(d.dot(f)) - hl, 0.0)
	return sqrt(ex * ex + ey * ey)


## Edge-to-edge distance between two rectangles (0 when overlapping).
## For separated convex polygons the closest pair always involves a vertex of
## one of them, so checking all 8 corners against the other rectangle is exact.
static func distance(c1: Vector2, f1: Vector2, hw1: float, hl1: float,
		c2: Vector2, f2: Vector2, hw2: float, hl2: float) -> float:
	if overlaps(c1, f1, hw1, hl1, c2, f2, hw2, hl2):
		return 0.0
	var a1 := f1 * hl1
	var b1 := Vector2(-f1.y, f1.x) * hw1
	var a2 := f2 * hl2
	var b2 := Vector2(-f2.y, f2.x) * hw2
	var best := point_distance(c1 + a1 + b1, c2, f2, hw2, hl2)
	best = minf(best, point_distance(c1 + a1 - b1, c2, f2, hw2, hl2))
	best = minf(best, point_distance(c1 - a1 + b1, c2, f2, hw2, hl2))
	best = minf(best, point_distance(c1 - a1 - b1, c2, f2, hw2, hl2))
	best = minf(best, point_distance(c2 + a2 + b2, c1, f1, hw1, hl1))
	best = minf(best, point_distance(c2 + a2 - b2, c1, f1, hw1, hl1))
	best = minf(best, point_distance(c2 - a2 + b2, c1, f1, hw1, hl1))
	best = minf(best, point_distance(c2 - a2 - b2, c1, f1, hw1, hl1))
	return best


static func _separated_on(d: Vector2, axis: Vector2,
		f1: Vector2, r1: Vector2, hw1: float, hl1: float,
		f2: Vector2, r2: Vector2, hw2: float, hl2: float) -> bool:
	var ra := hl1 * absf(f1.dot(axis)) + hw1 * absf(r1.dot(axis))
	var rb := hl2 * absf(f2.dot(axis)) + hw2 * absf(r2.dot(axis))
	return absf(d.dot(axis)) > ra + rb
