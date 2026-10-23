class_name Lane
extends RefCounted
## One directed traffic lane: a baked world-space polyline plus graph links.
##
## Lanes are produced by RoadSegment (ordinary lanes) and IntersectionController
## (junction connectors). Traffic agents store (lane, s) where s is the distance
## along the lane in metres.

var id := -1
var points := PackedVector3Array()
var cumulative := PackedFloat32Array()
## Curvature-limited advisory speed per point (internal m/s; ×3.6 = km/h).
var advisory := PackedFloat32Array()
var length := 0.0

var successors: Array[Lane] = []
var predecessors: Array[Lane] = []
## Same-direction lanes of the same segment (for future lane changes / autopilot).
var neighbours: Array[Lane] = []
var agents: Array[TrafficAgent] = []

## 0 = innermost lane (next to the centre line).
var lane_index := 0
var direction_lane_count := 1
var is_forward := true
var width := 3.4
var allow_spawn := true
## v0.03B zone traffic mix (see RoadSegment.bus_spawn_scale).
var bus_spawn_scale := 1.0
var source_name := ""

# --- Junction connector data (set by IntersectionController) ---
var is_connector := false
var intersection: IntersectionController = null
## Arm index the connector is entered from.
var approach_arm := -1
var movement := 0
## True for movements that must give way (right turns in left-hand traffic).
var yields := false
var conflicts: Array[Lane] = []
## Agents holding a junction grant for this connector (approaching or inside).
var reserved := 0

# --- Pedestrian crossings on this lane (set by PedestrianNetwork) ---
## Traffic yields at crossing_s[i] while crossings[i].occupied_count > 0.
var crossings: Array[CrossingZone] = []
var crossing_s := PackedFloat32Array()


func set_points(pts: PackedVector3Array, lateral_accel: float = 2.8, min_advisory: float = 3.5) -> void:
	points = pts
	var count := pts.size()
	cumulative.resize(count)
	var total := 0.0
	cumulative[0] = 0.0
	for i in range(1, count):
		total += pts[i].distance_to(pts[i - 1])
		cumulative[i] = total
	length = total
	_compute_advisory(lateral_accel, min_advisory)


func _compute_advisory(lateral_accel: float, min_advisory: float) -> void:
	var count := points.size()
	var raw := PackedFloat32Array()
	raw.resize(count)
	for i in count:
		var radius := 10000.0
		if i > 0 and i < count - 1:
			radius = _circumradius(points[i - 1], points[i], points[i + 1])
		raw[i] = clampf(sqrt(lateral_accel * radius), min_advisory, 40.0)
	if count >= 2:
		raw[0] = raw[1]
		raw[count - 1] = raw[count - 2]
	advisory.resize(count)
	for i in count:
		var v := raw[i]
		for k in range(maxi(i - 2, 0), mini(i + 3, count)):
			v = minf(v, raw[k])
		advisory[i] = v


static func _circumradius(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var area2 := (b - a).cross(c - a).length()
	if area2 < 0.0001:
		return 10000.0
	return (ab * bc * ca) / (2.0 * area2)


## Index i such that cumulative[i] <= s <= cumulative[i + 1].
func segment_index(s: float) -> int:
	var last := cumulative.size() - 1
	if s <= 0.0:
		return 0
	if s >= length:
		return last - 1
	var lo := 0
	var hi := last
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cumulative[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo


func sample_position(s: float) -> Vector3:
	var i := segment_index(s)
	var seg_len := cumulative[i + 1] - cumulative[i]
	if seg_len <= 0.0001:
		return points[i]
	return points[i].lerp(points[i + 1], clampf((s - cumulative[i]) / seg_len, 0.0, 1.0))


func sample_tangent(s: float) -> Vector3:
	var i := segment_index(s)
	return (points[i + 1] - points[i]).normalized()


func advisory_at(s: float) -> float:
	return advisory[segment_index(s)]


func start_point() -> Vector3:
	return points[0]


func end_point() -> Vector3:
	return points[points.size() - 1]


func start_tangent() -> Vector3:
	return (points[1] - points[0]).normalized()


func end_tangent() -> Vector3:
	var n := points.size()
	return (points[n - 1] - points[n - 2]).normalized()


## Distance along the lane of the point closest to `pos`.
## Searches the whole lane, or only near `hint_s` when a window is given.
func closest_s(pos: Vector3, hint_s: float = -1.0, window: float = -1.0) -> float:
	var first := 0
	var last := points.size() - 2
	if hint_s >= 0.0 and window > 0.0:
		first = maxi(segment_index(hint_s - window), 0)
		last = mini(segment_index(hint_s + window), points.size() - 2)
	var best_s := 0.0
	var best_d := INF
	for i in range(first, last + 1):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		var t := 0.0
		if len_sq > 0.000001:
			t = clampf((pos - a).dot(ab) / len_sq, 0.0, 1.0)
		var d := (a + ab * t).distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best_s = cumulative[i] + sqrt(len_sq) * t
	return best_s
