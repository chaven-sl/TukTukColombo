class_name PedestrianNetwork
extends Node3D
## Walkable graph for people, generated from the road: sidewalk walking lines
## (from RoadSegment sidewalks), joins at segment ends and junction corners,
## crossing links (CrossingZone) and level-authored PedestrianSpots.
##
## Graph search is plain BFS over a few hundred nodes and only runs when a
## person picks a new destination — never per frame.

const JOIN_DISTANCE := 7.5
const NODE_SPACING := 4.0

var road: RoadNetwork
var node_pos := PackedVector3Array()
## Unit vector pointing away from the road (for stepping back).
var node_out := PackedVector3Array()
var node_links: Array[PackedInt32Array] = []
var crossings: Array[CrossingZone] = []
var spots: Array[PedestrianSpot] = []
var sidewalk_paths: Array[PackedInt32Array] = []
var debug_mesh_instance: MeshInstance3D
var is_built := false

var _crossing_by_edge: Dictionary = {}
var _materials: Dictionary = {}


func build(p_road: RoadNetwork) -> void:
	if is_built:
		return
	road = p_road
	_materials = road.materials
	var crossing_requests: Array = []
	for seg in road.segments:
		for side in [-1.0, 1.0]:
			if not seg.has_sidewalk(side):
				continue
			var pts := seg.sidewalk_points(side, NODE_SPACING)
			if pts.size() < 2:
				continue
			var path := PackedInt32Array()
			var out := (seg.global_transform.basis * seg.local_right(seg.length * 0.5) * float(side)).normalized()
			for i in pts.size():
				var s := lerpf(seg.sidewalk_trim_start, seg.length - seg.sidewalk_trim_end, float(i) / float(pts.size() - 1))
				out = (seg.global_transform.basis * seg.local_right(s) * float(side)).normalized()
				var id := _add_node(pts[i], out)
				if i > 0:
					_link(path[path.size() - 1], id)
				path.append(id)
			sidewalk_paths.append(path)
		for i in seg.crossing_s.size():
			crossing_requests.append([seg, seg.crossing_s[i], seg.crossing_styles[i] if i < seg.crossing_styles.size() else 0])
	_join_path_ends()
	for req in crossing_requests:
		_add_crossing(req[0], float(req[1]), int(req[2]))
	_collect_spots(self)
	for spot in spots:
		spot.node_id = nearest_node(spot.global_position)
		_build_dressing(spot)
	_build_debug_mesh()
	is_built = true
	print("[PedestrianNetwork] %d nodes, %d sidewalk paths, %d crossings, %d spots" % [
		node_pos.size(), sidewalk_paths.size(), crossings.size(), spots.size()])


func _add_node(p: Vector3, out: Vector3) -> int:
	node_pos.append(p)
	node_out.append(out)
	node_links.append(PackedInt32Array())
	return node_pos.size() - 1


func _link(a: int, b: int, crossing: CrossingZone = null) -> void:
	if a == b or node_links[a].has(b):
		return
	node_links[a].append(b)
	node_links[b].append(a)
	if crossing != null:
		_crossing_by_edge[_edge_key(a, b)] = crossing
		_crossing_by_edge[_edge_key(b, a)] = crossing


static func _edge_key(a: int, b: int) -> int:
	return a * 65536 + b


func crossing_between(a: int, b: int) -> CrossingZone:
	return _crossing_by_edge.get(_edge_key(a, b), null)


## Joins sidewalk ends that meet: consecutive segments and junction corners.
func _join_path_ends() -> void:
	var ends := PackedInt32Array()
	for path in sidewalk_paths:
		ends.append(path[0])
		ends.append(path[path.size() - 1])
	for i in ends.size():
		for j in range(i + 1, ends.size()):
			var a := ends[i]
			var b := ends[j]
			if node_pos[a].distance_to(node_pos[b]) <= JOIN_DISTANCE:
				_link(a, b)


func _add_crossing(seg: RoadSegment, s: float, style: int) -> void:
	if not (seg.has_sidewalk(-1.0) and seg.has_sidewalk(1.0)):
		push_warning("[PedestrianNetwork] crossing on %s needs sidewalks on both sides" % seg.name)
		return
	var zone := CrossingZone.new()
	zone.id = crossings.size()
	zone.style = style as CrossingZone.Style
	zone.segment = seg
	zone.s = s
	zone.point_a = seg.sidewalk_point(s, -1.0)
	zone.point_b = seg.sidewalk_point(s, 1.0)
	zone.center = (zone.point_a + zone.point_b) * 0.5
	zone.center.y = 0.0
	zone.road_dir = (seg.global_transform.basis * seg.local_tangent(s)).normalized()
	zone.across_dir = (seg.global_transform.basis * seg.local_right(s)).normalized()
	zone.half_span = seg.sidewalk_offset(s)
	zone.road_half_width = seg.half_width(s)
	var out_a := -zone.across_dir
	var out_b := zone.across_dir
	zone.node_a = _add_node(zone.point_a, out_a)
	zone.node_b = _add_node(zone.point_b, out_b)
	_link(zone.node_a, _nearest_sidewalk_node(zone.point_a, zone.node_a))
	_link(zone.node_b, _nearest_sidewalk_node(zone.point_b, zone.node_b))
	_link(zone.node_a, zone.node_b, zone)
	for lane in road.segment_lanes.get(seg, []):
		var ln: Lane = lane
		var conflict := ln.closest_s(zone.center)
		zone.lanes.append(ln)
		zone.lane_conflict_s.append(conflict)
		ln.crossings.append(zone)
		ln.crossing_s.append(conflict)
	crossings.append(zone)


func _nearest_sidewalk_node(p: Vector3, exclude: int) -> int:
	var best := -1
	var best_d := INF
	for i in node_pos.size():
		if i == exclude:
			continue
		var d := node_pos[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


func nearest_node(p: Vector3) -> int:
	return _nearest_sidewalk_node(p, -1)


func _collect_spots(node: Node) -> void:
	for child in node.get_children():
		if child is PedestrianSpot:
			spots.append(child)
		_collect_spots(child)


func spots_of_kind(kind: PedestrianSpot.Kind) -> Array[PedestrianSpot]:
	var result: Array[PedestrianSpot] = []
	for spot in spots:
		if spot.kind == kind:
			result.append(spot)
	return result


func find_spot(spot_id: StringName) -> PedestrianSpot:
	for spot in spots:
		if spot.spot_id == spot_id:
			return spot
	return null


## Shortest path by hops (BFS). Empty when unreachable.
func path_between(from: int, to: int) -> PackedInt32Array:
	var parents := _bfs(from)
	return _reconstruct(parents, from, to)


## Random walk destination between min/max hops. When `want_crossing`, prefers
## destinations whose path uses a crossing. Returns the full node path.
func random_route(from: int, min_hops: int, max_hops: int, want_crossing: bool, rng: RandomNumberGenerator) -> PackedInt32Array:
	var parents := _bfs(from)
	var hops := _hops
	var candidates := PackedInt32Array()
	var crossing_candidates := PackedInt32Array()
	for i in node_pos.size():
		var h := hops[i]
		if h < min_hops or h > max_hops:
			continue
		candidates.append(i)
		if want_crossing and _crossed[i] == 1:
			crossing_candidates.append(i)
	var pool := crossing_candidates if want_crossing and not crossing_candidates.is_empty() else candidates
	if pool.is_empty():
		return PackedInt32Array()
	return _reconstruct(parents, from, pool[rng.randi() % pool.size()])


var _hops := PackedInt32Array()
var _crossed := PackedByteArray()


func _bfs(from: int) -> PackedInt32Array:
	var n := node_pos.size()
	var parents := PackedInt32Array()
	parents.resize(n)
	parents.fill(-1)
	_hops.resize(n)
	_hops.fill(-1)
	_crossed.resize(n)
	_crossed.fill(0)
	var queue := PackedInt32Array([from])
	_hops[from] = 0
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for nxt in node_links[cur]:
			if _hops[nxt] >= 0:
				continue
			_hops[nxt] = _hops[cur] + 1
			parents[nxt] = cur
			_crossed[nxt] = 1 if (_crossed[cur] == 1 or _crossing_by_edge.has(_edge_key(cur, nxt))) else 0
			queue.append(nxt)
	return parents


func _reconstruct(parents: PackedInt32Array, from: int, to: int) -> PackedInt32Array:
	if to < 0 or (to != from and parents[to] < 0):
		return PackedInt32Array()
	var reversed := PackedInt32Array([to])
	var cur := to
	while cur != from:
		cur = parents[cur]
		reversed.append(cur)
	reversed.reverse()
	return reversed


func _build_dressing(spot: PedestrianSpot) -> void:
	if spot.dressing == 0 or spot.node_id < 0:
		return
	var anchor := node_pos[spot.node_id]
	var out := node_out[spot.node_id]
	var root := Node3D.new()
	root.name = "Dressing_%s" % spot.spot_id
	root.position = anchor + out * 1.0
	root.basis = MathUtil.basis_from_forward(out)
	add_child(root)
	# v0.03A2: dressing is physical (shelter posts are street furniture,
	# shop blocks are buildings) — no more driving through them.
	var body := StaticBody3D.new()
	body.name = "DressingCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	WorldSurface.tag(body, WorldSurface.Type.PROP if spot.dressing == 1 else WorldSurface.Type.BUILDING)
	root.add_child(body)
	if spot.dressing == 1:
		_solid(body, Vector3(0.2, 2.5, 0.2), Vector3(-1.8, 1.25, 0.6))
		_solid(body, Vector3(0.2, 2.5, 0.2), Vector3(1.8, 1.25, 0.6))
	elif spot.dressing == 2:
		_solid(body, Vector3(6.0, 3.2, 3.0), Vector3(0, 1.6, 2.8))
	if spot.dressing == 1:
		# Bus shelter: roof on two posts.
		_box(root, Vector3(4.0, 0.12, 1.6), Vector3(0, 2.5, 0), _materials["dark"])
		_box(root, Vector3(0.12, 2.5, 0.12), Vector3(-1.8, 1.25, 0.6), _materials["concrete"])
		_box(root, Vector3(0.12, 2.5, 0.12), Vector3(1.8, 1.25, 0.6), _materials["concrete"])
		_box(root, Vector3(3.0, 0.1, 0.4), Vector3(0, 0.55, 0.5), _materials["concrete"])
	elif spot.dressing == 2:
		# Shop front: block with a coloured awning.
		_box(root, Vector3(6.0, 3.2, 3.0), Vector3(0, 1.6, 2.8), _materials["concrete"])
		_box(root, Vector3(6.2, 0.12, 1.4), Vector3(0, 2.6, 0.9), _materials["lamp_amber_on"])


func _solid(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)


func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _build_debug_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var lift := Vector3.UP * 0.3
	for a in node_links.size():
		for b in node_links[a]:
			if b < a:
				continue
			var color := Color(0.9, 0.9, 0.9)
			var zone := crossing_between(a, b)
			if zone != null:
				color = Color(0.2, 1.0, 0.4) if zone.style == CrossingZone.Style.DESIGNATED else Color(1.0, 0.5, 0.1)
			st.set_color(color)
			st.add_vertex(node_pos[a] + lift)
			st.set_color(color)
			st.add_vertex(node_pos[b] + lift)
	for spot in spots:
		var p := spot.global_position
		var color := Color(0.3, 0.6, 1.0) if spot.kind == PedestrianSpot.Kind.PICKUP else Color(1, 0.3, 0.9)
		st.set_color(color)
		st.add_vertex(p)
		st.set_color(color)
		st.add_vertex(p + Vector3.UP * 3.0)
	debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.name = "PedestrianDebug"
	debug_mesh_instance.mesh = st.commit()
	debug_mesh_instance.material_override = _materials["debug_lines"]
	debug_mesh_instance.visible = false
	add_child(debug_mesh_instance)


func _exit_tree() -> void:
	for zone in crossings:
		zone.lanes.clear()
	crossings.clear()
	_crossing_by_edge.clear()
