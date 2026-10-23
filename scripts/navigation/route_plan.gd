class_name RoutePlan
extends RefCounted
## A computed road route (v0.03A1 GPS): the polyline of lane geometry the
## route follows, cumulative distances, and the meaningful turns along it.
## Pure data + geometry so it can be unit tested without a scene.
##
## Turns are only recorded at junction connectors whose heading change is
## large (see MIN_TURN_DEG); gentle bends and lane-level wiggles never become
## instructions.

enum Kind { NONE, STRAIGHT, LEFT, RIGHT, PICKUP, DESTINATION, STOP_TO_PICK_UP, STOP_HERE }

const MIN_TURN_DEG := 35.0
const KEYS := {
	Kind.STRAIGHT: "GPS_STRAIGHT", Kind.LEFT: "GPS_LEFT", Kind.RIGHT: "GPS_RIGHT",
	Kind.PICKUP: "GPS_PICKUP", Kind.DESTINATION: "GPS_DESTINATION",
	Kind.STOP_TO_PICK_UP: "GPS_STOP_TO_PICK_UP", Kind.STOP_HERE: "GPS_STOP_HERE",
}

var points := PackedVector3Array()
var cumulative := PackedFloat32Array()
## Distance along the route of each turn and its direction (-1 left, +1 right).
var turn_along := PackedFloat32Array()
var turn_dir := PackedInt32Array()
## Whether the direction-aware search succeeded (false = fallback route).
var restricted := true
var target := Vector3.ZERO


func is_empty() -> bool:
	return points.size() < 2


func length() -> float:
	return cumulative[cumulative.size() - 1] if not cumulative.is_empty() else 0.0


func add_point(p: Vector3) -> void:
	if not points.is_empty():
		var last := points[points.size() - 1]
		var d := last.distance_to(p)
		if d < 0.05:
			return
		cumulative.append(cumulative[cumulative.size() - 1] + d)
	else:
		cumulative.append(0.0)
	points.append(p)


## Appends lane geometry between s = a and s = b (a <= b).
func append_lane_span(lane: Lane, a: float, b: float) -> void:
	add_point(lane.sample_position(a))
	for i in lane.points.size():
		var s := lane.cumulative[i]
		if s > a and s < b:
			add_point(lane.points[i])
	add_point(lane.sample_position(b))


## Records a turn at `along` if the heading change is meaningful.
func add_turn(along: float, from_dir: Vector3, to_dir: Vector3) -> void:
	var a := Vector2(from_dir.x, from_dir.z)
	var b := Vector2(to_dir.x, to_dir.z)
	if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
		return
	var angle := rad_to_deg(a.angle_to(b))
	if absf(angle) < MIN_TURN_DEG:
		return
	# Godot: -Z forward, +X right. A positive 2D angle (x, z) is a right turn.
	turn_along.append(along)
	turn_dir.append(1 if angle > 0.0 else -1)


func position_at(along: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	var i := _segment_index(clampf(along, 0.0, length()))
	var seg := cumulative[i + 1] - cumulative[i]
	var t := (along - cumulative[i]) / seg if seg > 0.0001 else 0.0
	return points[i].lerp(points[i + 1], clampf(t, 0.0, 1.0))


func tangent_at(along: float) -> Vector3:
	if points.size() < 2:
		return Vector3.FORWARD
	var i := _segment_index(clampf(along, 0.0, length()))
	return (points[i + 1] - points[i]).normalized()


func _segment_index(along: float) -> int:
	var lo := 0
	var hi := cumulative.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cumulative[mid] <= along:
			lo = mid
		else:
			hi = mid
	return mini(lo, points.size() - 2)


## Closest point on the route (horizontal distance). Searches only a window
## of segments around `hint_along` when hint_along >= 0 (cheap per-tick use).
## Returns Vector2(along, lateral_distance).
func project(pos: Vector3, hint_along: float = -1.0, back_m: float = 20.0, ahead_m: float = 120.0) -> Vector2:
	if points.size() < 2:
		return Vector2(0.0, INF)
	var first := 0
	var last := points.size() - 2
	if hint_along >= 0.0:
		first = _segment_index(maxf(hint_along - back_m, 0.0))
		last = _segment_index(minf(hint_along + ahead_m, length()))
	var p := Vector2(pos.x, pos.z)
	var best_along := 0.0
	var best_d := INF
	for i in range(first, last + 1):
		var a := Vector2(points[i].x, points[i].z)
		var b := Vector2(points[i + 1].x, points[i + 1].z)
		var ab := b - a
		var len_sq := ab.length_squared()
		var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0) if len_sq > 0.000001 else 0.0
		var d := (a + ab * t).distance_squared_to(p)
		if d < best_d:
			best_d = d
			best_along = cumulative[i] + sqrt(len_sq) * t
	return Vector2(best_along, sqrt(best_d))


## Next GPS instruction for a player `progress` metres along the route.
## `to_pickup` picks PICKUP vs DESTINATION wording; `stop_now` (caller-decided,
## e.g. within the pickup radius) turns it into a STOP instruction.
## Returns Vector2(kind, distance_m).
func next_instruction(progress: float, to_pickup: bool, stop_now: bool, announce_m: float) -> Vector2:
	if stop_now:
		return Vector2(Kind.STOP_TO_PICK_UP if to_pickup else Kind.STOP_HERE, 0.0)
	var remaining := maxf(length() - progress, 0.0)
	for i in turn_along.size():
		var d := turn_along[i] - progress
		if d < -2.0 or d > remaining:
			continue
		d = maxf(d, 0.0)
		if d <= announce_m:
			return Vector2(Kind.RIGHT if turn_dir[i] > 0 else Kind.LEFT, d)
		return Vector2(Kind.STRAIGHT, d)
	return Vector2(Kind.PICKUP if to_pickup else Kind.DESTINATION, remaining)


## Rounded for display: 10 m steps above 100 m, 5 m below.
static func display_distance(m: float) -> int:
	if m >= 100.0:
		return int(roundf(m / 10.0)) * 10
	return int(roundf(m / 5.0)) * 5
