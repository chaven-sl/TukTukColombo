class_name RoadNetwork
extends Node3D
## Builds and owns the drivable network: chains -> segments -> lanes,
## intersections and their connectors, traffic spawn slots, scenery and the
## lane debug visualisation. Call build() once from the level composition root.

signal built()

@export var lane_connect_tolerance := 0.75
@export var spawn_slot_spacing := 12.0
@export var generate_scenery := true
@export var scenery_seed := 1337
@export var ground_size := 1600.0
@export var ground_center := Vector3(126.0, 0.0, -150.0)

var lanes: Array[Lane] = []
var intersections: Array[IntersectionController] = []
var segments: Array[RoadSegment] = []
var chains: Array[RoadChain] = []
var source_lanes: Array[Lane] = []
var sink_lanes: Array[Lane] = []
var spawn_slot_lanes: Array[Lane] = []
var spawn_slot_s := PackedFloat32Array()
var spawn_slot_pos := PackedVector3Array()
## RoadSegment -> Array of the Lanes it generated (used by pedestrian crossings).
var segment_lanes: Dictionary = {}
var debug_mesh_instance: MeshInstance3D
var materials: Dictionary = {}
var is_built := false


func build() -> void:
	if is_built:
		return
	materials = RoadMaterials.create()
	_collect(self)
	for chain in chains:
		chain.layout()
	_build_ground()
	for seg in segments:
		seg.build_geometry(materials)
		var seg_list: Array[Lane] = []
		for lane in seg.build_lanes():
			lane.id = lanes.size()
			lanes.append(lane)
			seg_list.append(lane)
		segment_lanes[seg] = seg_list
	_auto_connect()
	for ix in intersections:
		for connector in ix.build(lanes, materials):
			connector.id = lanes.size()
			lanes.append(connector)
	for chain in chains:
		chain.build_end_cap(materials)
	for lane in lanes:
		if lane.is_connector:
			continue
		if lane.predecessors.is_empty():
			source_lanes.append(lane)
		if lane.successors.is_empty():
			sink_lanes.append(lane)
	_build_spawn_slots()
	_build_debug_mesh()
	if generate_scenery:
		ScenerySpawner.new().populate(self, scenery_seed)
	is_built = true
	print("[RoadNetwork] %d segments, %d lanes (%d connectors), %d sources, %d sinks, %d spawn slots" % [
		segments.size(), lanes.size(), lanes.size() - _ordinary_lane_count(), source_lanes.size(),
		sink_lanes.size(), spawn_slot_lanes.size()])
	built.emit()


## Lanes reference each other (successors/predecessors/conflicts), which
## would leak as RefCounted cycles; break them when the level is freed.
func _exit_tree() -> void:
	for lane in lanes:
		lane.successors.clear()
		lane.predecessors.clear()
		lane.neighbours.clear()
		lane.conflicts.clear()
		lane.agents.clear()
		lane.crossings.clear()
		lane.intersection = null
	lanes.clear()
	segment_lanes.clear()
	source_lanes.clear()
	sink_lanes.clear()
	spawn_slot_lanes.clear()


func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is RoadChain:
			chains.append(child)
		elif child is RoadSegment:
			segments.append(child)
		elif child is IntersectionController:
			intersections.append(child)
		_collect(child)


func _ordinary_lane_count() -> int:
	var n := 0
	for lane in lanes:
		if not lane.is_connector:
			n += 1
	return n


## Links lane ends to lane starts that coincide (segment joints, loop closure).
func _auto_connect() -> void:
	var tol_sq := lane_connect_tolerance * lane_connect_tolerance
	for a in lanes:
		for b in lanes:
			if a == b:
				continue
			if a.end_point().distance_squared_to(b.start_point()) > tol_sq:
				continue
			if a.end_tangent().dot(b.start_tangent()) < 0.8:
				continue
			a.successors.append(b)
			b.predecessors.append(a)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"is_ground", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ground_size, 2.0, ground_size)
	shape.shape = box
	shape.position = ground_center + Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(ground_size, ground_size)
	var mi := MeshInstance3D.new()
	mi.name = "GroundMesh"
	mi.mesh = mesh
	mi.position = ground_center + Vector3(0.0, -0.03, 0.0)
	mi.material_override = materials["ground"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	add_child(body)


func _build_spawn_slots() -> void:
	for lane in lanes:
		if lane.is_connector or not lane.allow_spawn:
			continue
		var approach_zone := 0.0
		for succ in lane.successors:
			if succ.is_connector:
				approach_zone = 25.0
		var s := 8.0
		while s < lane.length - 8.0 - approach_zone:
			spawn_slot_lanes.append(lane)
			spawn_slot_s.append(s)
			spawn_slot_pos.append(lane.sample_position(s))
			s += spawn_slot_spacing


func spawn_slot_count() -> int:
	return spawn_slot_lanes.size()


## Nearest point on an ordinary lane, as an upright pose facing along the lane.
func find_reset_transform(position: Vector3) -> Transform3D:
	var best_lane: Lane = null
	var best_d := INF
	for lane in lanes:
		if lane.is_connector:
			continue
		for p in lane.points:
			var d := p.distance_squared_to(position)
			if d < best_d:
				best_d = d
				best_lane = lane
	if best_lane == null:
		return Transform3D(Basis.IDENTITY, position + Vector3.UP)
	var s := best_lane.closest_s(position)
	var p := best_lane.sample_position(s)
	return Transform3D(MathUtil.basis_from_forward(best_lane.sample_tangent(s)), p + Vector3.UP * 0.35)


## Shortest driving distance (m) between two points along the directed lane
## graph (Dijkstra over lanes; a few dozen lanes, so cheap enough at ~1 Hz).
## Both ends snap to any ordinary lane within `radius`, either direction, so a
## route may start with a U-turn. Falls back to 1.3 × straight-line distance.
func route_distance(from_pos: Vector3, to_pos: Vector3, radius: float = 14.0) -> float:
	var starts := _lanes_near(from_pos, radius)
	var ends := _lanes_near(to_pos, radius)
	if starts.is_empty() or ends.is_empty():
		return from_pos.distance_to(to_pos) * 1.3
	var end_s: Dictionary = {}
	for e in ends:
		end_s[e[0]] = float(e[1])
	var best := INF
	var dist: Dictionary = {}
	for st in starts:
		var lane: Lane = st[0]
		var s0: float = st[1]
		if end_s.has(lane) and float(end_s[lane]) >= s0:
			best = minf(best, float(end_s[lane]) - s0)
		for succ in lane.successors:
			var d := lane.length - s0
			if d < float(dist.get(succ, INF)):
				dist[succ] = d
	var visited: Dictionary = {}
	while true:
		var cur: Lane = null
		var cur_d := INF
		for lane_key in dist.keys():
			if visited.has(lane_key):
				continue
			var d2: float = dist[lane_key]
			if d2 < cur_d:
				cur_d = d2
				cur = lane_key
		if cur == null or cur_d >= best:
			break
		visited[cur] = true
		if end_s.has(cur):
			best = minf(best, cur_d + float(end_s[cur]))
		for succ in cur.successors:
			var nd := cur_d + cur.length
			if nd < float(dist.get(succ, INF)):
				dist[succ] = nd
	if best == INF:
		return from_pos.distance_to(to_pos) * 1.3
	return best


func _lanes_near(pos: Vector3, radius: float) -> Array:
	var result: Array = []
	var r_sq := radius * radius
	for lane in lanes:
		if lane.is_connector:
			continue
		var s := lane.closest_s(pos)
		if lane.sample_position(s).distance_squared_to(pos) <= r_sq:
			result.append([lane, s])
	return result


func _build_debug_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var lift := Vector3.UP * 0.25
	for lane in lanes:
		var color := Color(0.2, 0.6, 1.0)
		if lane.is_connector:
			color = Color(1.0, 0.45, 0.1) if lane.yields else Color(1.0, 0.85, 0.1)
		elif not lane.is_forward:
			color = Color(0.2, 1.0, 0.5)
		if lane.successors.is_empty():
			color = Color(1.0, 0.2, 0.2)
		for i in lane.points.size() - 1:
			st.set_color(color)
			st.add_vertex(lane.points[i] + lift)
			st.set_color(color)
			st.add_vertex(lane.points[i + 1] + lift)
		# Direction tick at the lane end.
		var end := lane.end_point() + lift
		var back := end - lane.end_tangent() * 1.2
		var side := lane.end_tangent().cross(Vector3.UP) * 0.5
		st.set_color(color)
		st.add_vertex(end)
		st.set_color(color)
		st.add_vertex(back + side)
	debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.name = "LaneDebug"
	debug_mesh_instance.mesh = st.commit()
	debug_mesh_instance.material_override = materials["debug_lines"]
	debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	debug_mesh_instance.visible = false
	add_child(debug_mesh_instance)
