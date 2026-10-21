class_name RoadSegment
extends Node3D
## Modular road block: a straight or constant-radius arc centreline with a
## lane layout. Generates its own surface, markings, kerbs/barriers (with
## collision) and directed Lane data. Districts are assembled by chaining these.
##
## Local frame: starts at the origin heading -Z. Traffic drives on the LEFT
## (Sri Lanka): forward lanes lie left of the centre line, lane 0 is innermost.

enum Edge { KERB, BARRIER, NONE }

const KERB_WIDTH := 0.35
const KERB_HEIGHT := 0.15
const KERB_CHAMFER := 0.1
const KERB_STRIPE := 1.0
const BARRIER_BASE := 0.5
const BARRIER_HEIGHT := 0.85
const MARK_Y := 0.012
const LINE_WIDTH := 0.12

@export var length := 50.0
## Positive = right turn (clockwise seen from above), negative = left.
@export var turn_angle_deg := 0.0
@export_range(1, 4) var lanes_per_direction := 2
@export var lane_width := 3.4
## Values < 0 mean "same as start" (no taper).
@export var lane_width_end := -1.0
@export var median_width := 0.4
@export var median_width_end := -1.0
@export var shoulder_width := 0.6
@export var shoulder_width_end := -1.0
@export var edge_left: Edge = Edge.KERB
@export var edge_right: Edge = Edge.KERB
@export var allow_traffic_spawn := true
@export var sample_spacing := 2.0
@export var scenery_density := 1.0

@export_group("Pedestrians")
## Raised sidewalks behind the kerb (only where that edge is a KERB).
@export var sidewalk_left := false
@export var sidewalk_right := false
@export var sidewalk_width := 2.5
## Sidewalk omitted for this many metres at the start/end (e.g. tunnel mouths).
@export var sidewalk_trim_start := 0.0
@export var sidewalk_trim_end := 0.0
## Pedestrian crossings: distance along the segment (m) and style per entry
## (0 = designated zebra, 1 = uncontrolled / informal crossing point).
@export var crossing_s := PackedFloat32Array()
@export var crossing_styles := PackedInt32Array()

enum CrossingStyle { DESIGNATED, UNCONTROLLED }


# --- Chain interface ---

## Places this element at `start` (chain-local) and returns the end transform.
func chain_place(start: Transform3D) -> Transform3D:
	transform = start
	return start * end_transform_local()


func end_transform_local() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(turn_angle_deg)), local_center(length))


# --- Geometry ---

func _radius() -> float:
	return length / absf(deg_to_rad(turn_angle_deg))


func is_curved() -> bool:
	return absf(turn_angle_deg) > 0.01


func local_center(s: float) -> Vector3:
	if not is_curved():
		return Vector3(0.0, 0.0, -s)
	var r := _radius()
	var phi := s / r
	if turn_angle_deg > 0.0:
		return Vector3(r * (1.0 - cos(phi)), 0.0, -r * sin(phi))
	return Vector3(-r * (1.0 - cos(phi)), 0.0, -r * sin(phi))


func local_tangent(s: float) -> Vector3:
	if not is_curved():
		return Vector3.FORWARD
	var phi := s / _radius()
	if turn_angle_deg > 0.0:
		return Vector3(sin(phi), 0.0, -cos(phi))
	return Vector3(-sin(phi), 0.0, -cos(phi))


func local_right(s: float) -> Vector3:
	return local_tangent(s).cross(Vector3.UP)


func _lerp_end(a: float, b: float, s: float) -> float:
	if b < 0.0:
		return a
	return lerpf(a, b, s / length)


func lane_width_at(s: float) -> float:
	return _lerp_end(lane_width, lane_width_end, s)


func median_at(s: float) -> float:
	return _lerp_end(median_width, median_width_end, s)


func shoulder_at(s: float) -> float:
	return _lerp_end(shoulder_width, shoulder_width_end, s)


## Distance from the centre line to the outer edge of the outermost lane.
func carriageway_half(s: float) -> float:
	return median_at(s) * 0.5 + lanes_per_direction * lane_width_at(s)


## Distance from the centre line to the kerb/barrier face.
func half_width(s: float) -> float:
	return carriageway_half(s) + shoulder_at(s)


func has_sidewalk(side: float) -> bool:
	if side < 0.0:
		return sidewalk_left and edge_left == Edge.KERB
	return sidewalk_right and edge_right == Edge.KERB


## Lateral distance from the centre line to the walking line of a sidewalk.
func sidewalk_offset(s: float) -> float:
	return half_width(s) + KERB_WIDTH + sidewalk_width * 0.5


## Outermost extent of the built road on a side (kerb/barrier/sidewalk included).
func outer_extent(s: float, side: float) -> float:
	if has_sidewalk(side):
		return half_width(s) + KERB_WIDTH + sidewalk_width
	return half_width(s) + KERB_WIDTH


## Global walking-line points of a sidewalk (side −1 = left of travel).
func sidewalk_points(side: float, spacing: float = 4.0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var s0 := sidewalk_trim_start
	var s1 := length - sidewalk_trim_end
	if s1 - s0 < 1.0:
		return pts
	var n := maxi(1, int(ceil((s1 - s0) / spacing)))
	var xf := global_transform
	for k in n + 1:
		var s := lerpf(s0, s1, float(k) / float(n))
		var p := xf * (local_center(s) + local_right(s) * (side * sidewalk_offset(s)))
		p.y = KERB_HEIGHT
		pts.append(p)
	return pts


## Global walking-line point of a sidewalk at distance s.
func sidewalk_point(s: float, side: float) -> Vector3:
	var p := global_transform * (local_center(s) + local_right(s) * (side * sidewalk_offset(s)))
	p.y = KERB_HEIGHT
	return p


## Signed lateral offset of a lane centre (positive = right of travel).
func lane_offset(index: int, s: float, forward: bool) -> float:
	var off := median_at(s) * 0.5 + (index + 0.5) * lane_width_at(s)
	return -off if forward else off


func sample_count() -> int:
	var spacing := sample_spacing
	if is_curved():
		spacing = minf(spacing, maxf(_radius() * 0.08, 0.75))
	return maxi(2, int(ceil(length / spacing)))


# --- Lanes ---

func build_lanes() -> Array[Lane]:
	var result: Array[Lane] = []
	var n := sample_count()
	var xf := global_transform
	for dir in 2:
		var forward := dir == 0
		var group: Array[Lane] = []
		for i in lanes_per_direction:
			var pts := PackedVector3Array()
			pts.resize(n + 1)
			for k in n + 1:
				var s := length * float(k) / float(n)
				pts[k] = xf * (local_center(s) + local_right(s) * lane_offset(i, s, forward))
				pts[k].y = 0.0
			if not forward:
				pts.reverse()
			var lane := Lane.new()
			lane.lane_index = i
			lane.direction_lane_count = lanes_per_direction
			lane.is_forward = forward
			lane.width = lane_width
			lane.allow_spawn = allow_traffic_spawn
			lane.source_name = name
			lane.set_points(pts)
			group.append(lane)
			result.append(lane)
		for lane in group:
			for other in group:
				if other != lane:
					lane.neighbours.append(other)
	return result


# --- Visual and collision geometry ---

func build_geometry(materials: Dictionary) -> void:
	_build_surface(materials["asphalt"])
	_build_markings(materials["markings"])
	var edges := SurfaceTool.new()
	edges.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_edges := false
	for side in [-1.0, 1.0]:
		var edge: Edge = edge_left if side < 0.0 else edge_right
		if edge == Edge.KERB:
			_build_kerb(edges, side)
			if has_sidewalk(side):
				_build_sidewalk(edges, side)
			has_edges = true
		elif edge == Edge.BARRIER:
			_build_barrier(edges, side)
			has_edges = true
	if has_edges:
		var mesh := edges.commit()
		var mi := MeshInstance3D.new()
		mi.name = "Edges"
		mi.mesh = mesh
		mi.material_override = materials["kerb"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var body := StaticBody3D.new()
		body.name = "EdgeCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		add_child(body)


func _build_surface(material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := sample_count()
	var lane_col := Color(0.2, 0.2, 0.22)
	var shoulder_col := Color(0.29, 0.28, 0.27)
	var median_col := Color(0.24, 0.24, 0.25)
	for k in n:
		var s0 := length * float(k) / float(n)
		var s1 := length * float(k + 1) / float(n)
		var m0 := median_at(s0) * 0.5
		var m1 := median_at(s1) * 0.5
		var c0 := carriageway_half(s0)
		var c1 := carriageway_half(s1)
		var h0 := half_width(s0)
		var h1 := half_width(s1)
		_strip(st, s0, s1, -h0, -c0, -h1, -c1, 0.0, shoulder_col)
		_strip(st, s0, s1, -c0, -m0, -c1, -m1, 0.0, lane_col)
		_strip(st, s0, s1, -m0, m0, -m1, m1, 0.0, median_col)
		_strip(st, s0, s1, m0, c0, m1, c1, 0.0, lane_col)
		_strip(st, s0, s1, c0, h0, c1, h1, 0.0, shoulder_col)
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Flat quad strip between lateral offsets (a0..b0 at s0, a1..b1 at s1).
func _strip(st: SurfaceTool, s0: float, s1: float, a0: float, b0: float, a1: float, b1: float, y: float, color: Color) -> void:
	var c0 := local_center(s0)
	var c1 := local_center(s1)
	var r0 := local_right(s0)
	var r1 := local_right(s1)
	var up := Vector3.UP * y
	var p00 := c0 + r0 * a0 + up
	var p01 := c0 + r0 * b0 + up
	var p10 := c1 + r1 * a1 + up
	var p11 := c1 + r1 * b1 + up
	_quad(st, p00, p01, p11, p10, Vector3.UP, color)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	st.set_normal(normal)
	st.set_color(color)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


func _build_markings(material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color(0.92, 0.92, 0.88)
	var yellow := Color(0.95, 0.78, 0.2)
	var steps := maxi(2, int(ceil(length / 1.0)))
	var half_line := LINE_WIDTH * 0.5
	for k in steps:
		var s0 := length * float(k) / float(steps)
		var s1 := length * float(k + 1) / float(steps)
		var s_mid := (s0 + s1) * 0.5
		var dash_on := fmod(s_mid, 8.0) < 3.0
		for side in [-1.0, 1.0]:
			# Edge line at the carriageway edge.
			var e0: float = side * carriageway_half(s0)
			var e1: float = side * carriageway_half(s1)
			_strip(st, s0, s1, e0 - half_line, e0 + half_line, e1 - half_line, e1 + half_line, MARK_Y, white)
			# Dashed dividers between same-direction lanes.
			if dash_on:
				for li in range(1, lanes_per_direction):
					var d0: float = side * (median_at(s0) * 0.5 + li * lane_width_at(s0))
					var d1: float = side * (median_at(s1) * 0.5 + li * lane_width_at(s1))
					_strip(st, s0, s1, d0 - half_line, d0 + half_line, d1 - half_line, d1 + half_line, MARK_Y, white)
		# Centre: two lines for a wide median, a double line otherwise.
		var m0 := median_at(s0) * 0.5
		var m1 := median_at(s1) * 0.5
		if m0 >= 0.5:
			for side in [-1.0, 1.0]:
				var o0: float = side * m0
				var o1: float = side * m1
				_strip(st, s0, s1, o0 - half_line, o0 + half_line, o1 - half_line, o1 + half_line, MARK_Y, yellow)
		else:
			_strip(st, s0, s1, -0.13 - half_line * 0.7, -0.13 + half_line * 0.7, -0.13 - half_line * 0.7, -0.13 + half_line * 0.7, MARK_Y, white)
			_strip(st, s0, s1, 0.13 - half_line * 0.7, 0.13 + half_line * 0.7, 0.13 - half_line * 0.7, 0.13 + half_line * 0.7, MARK_Y, white)
	# Zebra stripes for designated pedestrian crossings.
	for i in crossing_s.size():
		var style := crossing_styles[i] if i < crossing_styles.size() else CrossingStyle.DESIGNATED
		if style != CrossingStyle.DESIGNATED:
			continue
		var cs := crossing_s[i]
		var half := carriageway_half(cs)
		var o := -half + 0.3
		while o < half - 0.3:
			_strip(st, cs - 1.5, cs + 1.5, o, o + 0.5, o, o + 0.5, MARK_Y + 0.001, white)
			o += 1.0
	var mi := MeshInstance3D.new()
	mi.name = "Markings"
	mi.mesh = st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_sidewalk(st: SurfaceTool, side: float) -> void:
	var s_start := sidewalk_trim_start
	var s_end := length - sidewalk_trim_end
	if s_end - s_start < 1.0:
		return
	var steps := maxi(1, int(ceil((s_end - s_start) / 2.0)))
	var paving := Color(0.68, 0.66, 0.62)
	var paving_alt := Color(0.62, 0.6, 0.57)
	for k in steps:
		var s0 := lerpf(s_start, s_end, float(k) / float(steps))
		var s1 := lerpf(s_start, s_end, float(k + 1) / float(steps))
		var inner0 := half_width(s0) + KERB_WIDTH
		var inner1 := half_width(s1) + KERB_WIDTH
		var color := paving if k % 2 == 0 else paving_alt
		_face(st, _p(s0, side, inner0, KERB_HEIGHT), _p(s1, side, inner1, KERB_HEIGHT),
				_p(s1, side, inner1 + sidewalk_width, KERB_HEIGHT), _p(s0, side, inner0 + sidewalk_width, KERB_HEIGHT), color)
		_face(st, _p(s0, side, inner0 + sidewalk_width, KERB_HEIGHT), _p(s1, side, inner1 + sidewalk_width, KERB_HEIGHT),
				_p(s1, side, inner1 + sidewalk_width, 0.0), _p(s0, side, inner0 + sidewalk_width, 0.0), paving_alt)


## Point at distance s, lateral offset `o` (outward from centre on `side`), height h.
func _p(s: float, side: float, o: float, h: float) -> Vector3:
	return local_center(s) + local_right(s) * (side * o) + Vector3.UP * h


func _build_kerb(st: SurfaceTool, side: float) -> void:
	var steps := maxi(2, int(ceil(length / KERB_STRIPE)))
	for k in steps:
		var s0 := length * float(k) / float(steps)
		var s1 := length * float(k + 1) / float(steps)
		var color := Color(0.92, 0.92, 0.9) if k % 2 == 0 else Color(0.1, 0.1, 0.1)
		var h0 := half_width(s0)
		var h1 := half_width(s1)
		# Chamfered inner face (so wheels ride up instead of snagging).
		_face(st, _p(s0, side, h0, 0.0), _p(s1, side, h1, 0.0),
				_p(s1, side, h1 + KERB_CHAMFER, KERB_HEIGHT), _p(s0, side, h0 + KERB_CHAMFER, KERB_HEIGHT), color)
		# Top.
		_face(st, _p(s0, side, h0 + KERB_CHAMFER, KERB_HEIGHT), _p(s1, side, h1 + KERB_CHAMFER, KERB_HEIGHT),
				_p(s1, side, h1 + KERB_WIDTH, KERB_HEIGHT), _p(s0, side, h0 + KERB_WIDTH, KERB_HEIGHT), color)
		# Outer face.
		_face(st, _p(s0, side, h0 + KERB_WIDTH, KERB_HEIGHT), _p(s1, side, h1 + KERB_WIDTH, KERB_HEIGHT),
				_p(s1, side, h1 + KERB_WIDTH, 0.0), _p(s0, side, h0 + KERB_WIDTH, 0.0), color)


func _build_barrier(st: SurfaceTool, side: float) -> void:
	var steps := maxi(2, int(ceil(length / 2.0)))
	for k in steps:
		var s0 := length * float(k) / float(steps)
		var s1 := length * float(k + 1) / float(steps)
		var color := Color(0.72, 0.72, 0.7) if (k / 2) % 4 != 0 else Color(0.85, 0.65, 0.15)
		var h0 := half_width(s0)
		var h1 := half_width(s1)
		# Jersey profile: lower slope, upper face, top, outer face.
		_face(st, _p(s0, side, h0, 0.0), _p(s1, side, h1, 0.0),
				_p(s1, side, h1 + 0.12, 0.25), _p(s0, side, h0 + 0.12, 0.25), color)
		_face(st, _p(s0, side, h0 + 0.12, 0.25), _p(s1, side, h1 + 0.12, 0.25),
				_p(s1, side, h1 + 0.2, BARRIER_HEIGHT), _p(s0, side, h0 + 0.2, BARRIER_HEIGHT), color)
		_face(st, _p(s0, side, h0 + 0.2, BARRIER_HEIGHT), _p(s1, side, h1 + 0.2, BARRIER_HEIGHT),
				_p(s1, side, h1 + 0.35, BARRIER_HEIGHT), _p(s0, side, h0 + 0.35, BARRIER_HEIGHT), color)
		_face(st, _p(s0, side, h0 + 0.35, BARRIER_HEIGHT), _p(s1, side, h1 + 0.35, BARRIER_HEIGHT),
				_p(s1, side, h1 + BARRIER_BASE, 0.0), _p(s0, side, h0 + BARRIER_BASE, 0.0), color)


func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var normal := (b - a).cross(d - a).normalized()
	if normal.y < -0.01:
		normal = -normal
	_quad(st, a, b, c, d, normal, color)
