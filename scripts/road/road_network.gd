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
## v0.03A2: playable district footprint (x/z) — roads + margin; the district
## boundary ring sits just outside it, WorldRecoveryManager treats leaving it
## as a failsafe case.
var district_rect := Rect2()
@export var district_margin := 38.0


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
	district_rect = _compute_district_rect()
	DistrictBoundary.new().build(self, district_rect, scenery_seed + 1)
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
	WorldSurface.tag(body, WorldSurface.Type.FORECOURT)
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


func _compute_district_rect() -> Rect2:
	var r := Rect2()
	var first := true
	for lane in lanes:
		for p in lane.points:
			var p2 := Vector2(p.x, p.z)
			if first:
				r = Rect2(p2, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p2)
	return r.grow(district_margin)


## Horizontal distance (m) from `pos` to the nearest ordinary lane centre line.
func distance_to_road(pos: Vector3) -> float:
	var best := INF
	for lane in lanes:
		if lane.is_connector:
			continue
		var p := lane.sample_position(lane.closest_s(pos))
		best = minf(best, Vector2(p.x - pos.x, p.z - pos.z).length())
	return best


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
## Both ends snap to any ordinary lane within `radius`, either direction.
## Kept for tools/tests; gameplay uses route(), which avoids U-turn starts.
func route_distance(from_pos: Vector3, to_pos: Vector3, radius: float = 14.0) -> float:
	return _shortest(_lanes_near(from_pos, radius), _lanes_near(to_pos, radius), from_pos, to_pos)


## Route with a sensible start and end (v0.03A U-turn fix).
## - `from_heading` given (e.g. the tuk's facing): start only on lanes running
##   that way.
## - otherwise (a kerbside pickup): start on the lane nearest the point — the
##   kerb lane a tuk stops in — and its same-direction neighbours.
## The destination always snaps to its kerb-side lane direction.
## Falls back to the unrestricted search only if the directed one finds no
## route (e.g. a dead-end street), and reports that in "restricted".
func route(from_pos: Vector3, to_pos: Vector3, from_heading: Vector3 = Vector3.ZERO, radius: float = 14.0) -> Dictionary:
	var all_starts := _lanes_near(from_pos, radius)
	var all_ends := _lanes_near(to_pos, radius)
	var starts := _directed(all_starts, from_pos, from_heading)
	var ends := _directed(all_ends, to_pos, Vector3.ZERO)
	var d := _shortest(starts, ends, from_pos, to_pos)
	var restricted := true
	if d == INF or starts.is_empty() or ends.is_empty():
		d = _shortest(all_starts, all_ends, from_pos, to_pos)
		restricted = false
	var start_dir := Vector3.ZERO
	if not starts.is_empty():
		start_dir = (starts[0][0] as Lane).sample_tangent(float(starts[0][1]))
	if d == INF:
		d = from_pos.distance_to(to_pos) * 1.3
	return {"distance": d, "restricted": restricted, "start_dir": start_dir}


## Adds a lateral-offset cost so equal-length parallel lanes resolve to the
## one nearest `pos` (the tuk's own lane / the kerb lane), not an arbitrary one.
func _with_offset_cost(candidates: Array, pos: Vector3) -> Array:
	var out: Array = []
	for c in candidates:
		var p := (c[0] as Lane).sample_position(float(c[1]))
		out.append([c[0], c[1], Vector2(p.x - pos.x, p.z - pos.z).length() * 4.0])
	return out


func _directed(candidates: Array, pos: Vector3, heading: Vector3) -> Array:
	if candidates.is_empty():
		return candidates
	var reference := Vector3(heading.x, 0.0, heading.z)
	if reference.length_squared() < 0.0001:
		var nearest: Array = candidates[0]
		var nearest_d := INF
		for c in candidates:
			var dd := (c[0] as Lane).sample_position(float(c[1])).distance_squared_to(pos)
			if dd < nearest_d:
				nearest_d = dd
				nearest = c
		reference = (nearest[0] as Lane).sample_tangent(float(nearest[1]))
	reference = reference.normalized()
	var out: Array = []
	for c in candidates:
		if (c[0] as Lane).sample_tangent(float(c[1])).dot(reference) > 0.3:
			out.append(c)
	return out


func _shortest(starts: Array, ends: Array, _from_pos: Vector3, _to_pos: Vector3) -> float:
	return float(_search(starts, ends)["distance"])


## Dijkstra over lanes (v0.02 semantics, now with path reconstruction).
## dist[lane] = route distance from the start point to that lane's start.
## Start lanes are not seeded themselves — their successors are, with the
## remaining length — so a route may legally loop back over its own start
## lane (a lap) instead of being forced into a U-turn. prev[lane] is the
## previous Lane, or [start_lane, s0] for the first lane after a start.
## A same-lane route ahead of the start is recorded as "direct".
## Optional third entry per start/end = extra cost (GPS uses it to prefer the
## lane the tuk is actually in and the kerb lane at the destination).
func _search(starts: Array, ends: Array) -> Dictionary:
	var result := {"distance": INF, "end_lane": null, "end_s": 0.0, "prev": {}, "direct": []}
	if starts.is_empty() or ends.is_empty():
		return result
	var end_s: Dictionary = {}
	var end_cost: Dictionary = {}
	for e in ends:
		end_s[e[0]] = float(e[1])
		end_cost[e[0]] = float(e[2]) if e.size() > 2 else 0.0
	var best := INF
	var best_lane: Lane = null
	var direct: Array = []
	var dist: Dictionary = {}
	var prev: Dictionary = {}
	for st in starts:
		var lane: Lane = st[0]
		var s0: float = st[1]
		var c0 := float(st[2]) if st.size() > 2 else 0.0
		if end_s.has(lane) and float(end_s[lane]) >= s0 and float(end_s[lane]) - s0 + c0 + float(end_cost[lane]) < best:
			best = float(end_s[lane]) - s0 + c0 + float(end_cost[lane])
			best_lane = lane
			direct = [lane, s0]
		for succ in lane.successors:
			var d := lane.length - s0 + c0
			if d < float(dist.get(succ, INF)):
				dist[succ] = d
				prev[succ] = [lane, s0]
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
		if end_s.has(cur) and cur_d + float(end_s[cur]) + float(end_cost[cur]) < best:
			best = cur_d + float(end_s[cur]) + float(end_cost[cur])
			best_lane = cur
			direct = []
		for succ in cur.successors:
			var nd := cur_d + cur.length
			if nd < float(dist.get(succ, INF)):
				dist[succ] = nd
				prev[succ] = cur
	result["distance"] = best
	result["end_lane"] = best_lane
	result["end_s"] = float(end_s.get(best_lane, 0.0)) if best_lane != null else 0.0
	result["prev"] = prev
	result["direct"] = direct
	return result


## v0.03A1 GPS: the same direction-aware search as route(), plus the actual
## road geometry of the chosen route. Returns a RoutePlan (empty points when
## no route exists). Called on accept / boarding / off-route only — never
## every frame.
func route_path(from_pos: Vector3, to_pos: Vector3, from_heading: Vector3 = Vector3.ZERO, radius: float = 14.0) -> RoutePlan:
	var all_starts := _lanes_near(from_pos, radius)
	var all_ends := _lanes_near(to_pos, radius)
	var starts := _with_offset_cost(_directed(all_starts, from_pos, from_heading), from_pos)
	var ends := _with_offset_cost(_directed(all_ends, to_pos, Vector3.ZERO), to_pos)
	var res := _search(starts, ends)
	var plan := RoutePlan.new()
	plan.restricted = true
	if res["end_lane"] == null:
		res = _search(all_starts, all_ends)
		plan.restricted = false
	if res["end_lane"] == null:
		return plan
	# Rebuild [lane, from_s, to_s] spans back from the end lane.
	var spans: Array = []
	var se := float(res["end_s"])
	var direct: Array = res["direct"]
	if not direct.is_empty():
		spans.append([direct[0], float(direct[1]), se])
	else:
		var prev: Dictionary = res["prev"]
		var lane: Lane = res["end_lane"]
		var to_s := se
		var guard := 0
		while guard < 512:
			guard += 1
			spans.push_front([lane, 0.0, to_s])
			var p: Variant = prev.get(lane, null)
			if p is Array:
				spans.push_front([p[0], float(p[1]), (p[0] as Lane).length])
				break
			if p == null:
				break
			lane = p
			to_s = lane.length
	for i in spans.size():
		var l: Lane = spans[i][0]
		if l.is_connector and plan.points.size() > 0:
			plan.add_turn(plan.length(), l.start_tangent(), l.end_tangent())
		plan.append_lane_span(l, float(spans[i][1]), float(spans[i][2]))
	plan.target = to_pos
	return plan


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
