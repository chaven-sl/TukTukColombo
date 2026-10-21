class_name IntersectionController
extends Node3D
## Owns right-of-way at one four-way junction. Traffic agents never guess
## priority themselves: they ask is_movement_open() while approaching and
## request_entry() when committing, and release() when they leave.
##
## Permission = signal phase AND no conflicting connector reserved/occupied
## AND space on the exit lane AND (for give-way movements) no priority traffic
## about to use a conflicting path. Connectors and their conflict sets are
## generated from the lanes that meet this box, so the controller works for any
## arm layout that touches its four edges.
##
## Local frame: chain direction is -Z. Arms: 0 = -Z edge, 1 = +X, 2 = +Z, 3 = -X.

enum Movement { STRAIGHT, LEFT, RIGHT }
enum Light { GREEN, AMBER, RED }

const EDGE_TOLERANCE := 0.75
const CONFLICT_DISTANCE := 2.3
const CONNECTOR_SPACING := 1.5

@export var size := 20.0
@export var green_through := 14.0
@export var green_cross := 9.0
@export var amber_time := 3.0
@export var all_red_time := 1.5
## Give-way movements wait for priority traffic closer than this (m).
@export var yield_check_distance := 32.0
## Free length required at the start of the exit lane (m, beyond vehicle length).
@export var exit_clearance := 4.0

var connectors: Array[Lane] = []
var incoming: Array[Lane] = []
var phase_index := 0
var phase_time := 0.0
var grants_issued := PackedInt32Array([0, 0])
var denied_requests := 0

# Phase table: [group (0 = arms 0/2, 1 = arms 1/3, -1 = none), state, duration]
var _phases: Array = []
var _signal_heads: Array[Dictionary] = []
var _materials: Dictionary = {}


# --- Chain interface ---

func chain_place(start: Transform3D) -> Transform3D:
	transform = start.translated_local(Vector3(0.0, 0.0, -size * 0.5))
	return start.translated_local(Vector3(0.0, 0.0, -size))


## Global transform at an arm's edge, facing out of the junction.
func arm_transform(arm: int) -> Transform3D:
	var half := size * 0.5
	var local := Transform3D.IDENTITY
	match arm:
		0:
			local = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -half))
		1:
			local = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(half, 0.0, 0.0))
		2:
			local = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, half))
		3:
			local = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-half, 0.0, 0.0))
	return global_transform * local


func _exit_tree() -> void:
	connectors.clear()
	incoming.clear()
	_signal_heads.clear()


func _ready() -> void:
	_phases = [
		[0, Light.GREEN, green_through],
		[0, Light.AMBER, amber_time],
		[-1, Light.RED, all_red_time],
		[1, Light.GREEN, green_cross],
		[1, Light.AMBER, amber_time],
		[-1, Light.RED, all_red_time],
	]


# --- Build ---

## Creates connector lanes between lanes that end/start on this box's edges.
func build(lanes: Array[Lane], materials: Dictionary) -> Array[Lane]:
	_materials = materials
	var inv := global_transform.affine_inverse()
	var half := size * 0.5
	var outgoing: Array[Lane] = []
	for lane in lanes:
		if lane.is_connector:
			continue
		var end_arm := _edge_arm(inv * lane.end_point(), half)
		if end_arm >= 0:
			lane.approach_arm = end_arm
			incoming.append(lane)
		var start_arm := _edge_arm(inv * lane.start_point(), half)
		if start_arm >= 0:
			outgoing.append(lane)
	for in_lane in incoming:
		var in_arm := in_lane.approach_arm
		var d_in := in_lane.end_tangent()
		for out_lane in outgoing:
			var out_arm := _edge_arm(inv * out_lane.start_point(), half)
			if out_arm == in_arm or out_arm < 0:
				continue
			var d_out := out_lane.start_tangent()
			var angle := rad_to_deg(d_in.signed_angle_to(d_out, Vector3.UP))
			var movement := Movement.STRAIGHT
			if angle > 35.0:
				movement = Movement.LEFT
			elif angle < -35.0:
				movement = Movement.RIGHT
			if absf(angle) > 150.0:
				continue
			if not _lane_rule_allows(in_lane, out_lane, movement):
				continue
			connectors.append(_make_connector(in_lane, out_lane, movement, in_arm))
	_compute_conflicts()
	_build_visuals(materials)
	return connectors


func _edge_arm(p: Vector3, half: float) -> int:
	if absf(p.z + half) < EDGE_TOLERANCE and absf(p.x) < half:
		return 0
	if absf(p.x - half) < EDGE_TOLERANCE and absf(p.z) < half:
		return 1
	if absf(p.z - half) < EDGE_TOLERANCE and absf(p.x) < half:
		return 2
	if absf(p.x + half) < EDGE_TOLERANCE and absf(p.z) < half:
		return 3
	return -1


## Left-hand traffic lane use: left turns from the kerb lane into the kerb
## lane, right turns from the inner lane into the inner lane, straight keeps
## its lane index. Single-lane approaches may make every movement.
func _lane_rule_allows(in_lane: Lane, out_lane: Lane, movement: Movement) -> bool:
	var n_in := in_lane.direction_lane_count
	var n_out := out_lane.direction_lane_count
	match movement:
		Movement.LEFT:
			return (n_in == 1 or in_lane.lane_index == n_in - 1) and out_lane.lane_index == n_out - 1
		Movement.RIGHT:
			return in_lane.lane_index == 0 and out_lane.lane_index == 0
	return out_lane.lane_index == mini(in_lane.lane_index, n_out - 1)


func _make_connector(in_lane: Lane, out_lane: Lane, movement: Movement, arm: int) -> Lane:
	var p0 := in_lane.end_point()
	var p3 := out_lane.start_point()
	var d0 := in_lane.end_tangent()
	var d3 := out_lane.start_tangent()
	var handle := p0.distance_to(p3) * (0.33 if movement == Movement.STRAIGHT else 0.42)
	var p1 := p0 + d0 * handle
	var p2 := p3 - d3 * handle
	var approx := p0.distance_to(p1) + p1.distance_to(p2) + p2.distance_to(p3)
	var count := maxi(4, int(ceil(approx / CONNECTOR_SPACING)))
	var pts := PackedVector3Array()
	pts.resize(count + 1)
	for i in count + 1:
		var t := float(i) / float(count)
		var u := 1.0 - t
		pts[i] = p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)
	var lane := Lane.new()
	lane.is_connector = true
	lane.intersection = self
	lane.approach_arm = arm
	lane.movement = movement
	lane.yields = movement == Movement.RIGHT
	lane.width = in_lane.width
	lane.allow_spawn = false
	lane.direction_lane_count = 1
	lane.source_name = "%s/%s" % [name, Movement.keys()[movement]]
	lane.set_points(pts, 2.5, 3.0)
	lane.predecessors.append(in_lane)
	lane.successors.append(out_lane)
	in_lane.successors.append(lane)
	out_lane.predecessors.append(lane)
	return lane


## Two connectors conflict when their paths come within CONFLICT_DISTANCE,
## unless they share the same approach lane (that is a queue, handled by
## car-following). Shared exits (merges) always conflict.
func _compute_conflicts() -> void:
	var limit := CONFLICT_DISTANCE * CONFLICT_DISTANCE
	for i in connectors.size():
		var a := connectors[i]
		for j in range(i + 1, connectors.size()):
			var b := connectors[j]
			if a.predecessors[0] == b.predecessors[0]:
				continue
			var conflict := a.successors[0] == b.successors[0]
			if not conflict:
				for pa in a.points:
					for pb in b.points:
						if pa.distance_squared_to(pb) < limit:
							conflict = true
							break
					if conflict:
						break
			if conflict:
				a.conflicts.append(b)
				b.conflicts.append(a)


# --- Runtime ---

func _physics_process(delta: float) -> void:
	if _phases.is_empty():
		return
	phase_time += delta
	var duration: float = _phases[phase_index][2]
	if phase_time >= duration:
		phase_time = 0.0
		phase_index = (phase_index + 1) % _phases.size()
		_update_signal_heads()


func group_state(group: int) -> Light:
	var phase: Array = _phases[phase_index]
	if int(phase[0]) != group:
		return Light.RED
	return int(phase[1]) as Light


func phase_description() -> String:
	var phase: Array = _phases[phase_index]
	var group := int(phase[0])
	var label := "ALL RED" if group < 0 else ("THROUGH" if group == 0 else "CROSS")
	return "%s %s %.1fs" % [label, Light.keys()[int(phase[1])], float(phase[2]) - phase_time]


func _approach_group(connector: Lane) -> int:
	return connector.approach_arm % 2


## Would this movement be allowed now? Used while approaching (no reservation).
func is_movement_open(connector: Lane, agent: TrafficAgent) -> bool:
	if agent.granted_connector == connector:
		return true
	if group_state(_approach_group(connector)) != Light.GREEN:
		return false
	return _conflicts_clear(connector) and _exit_clear(connector, agent) and _yield_clear(connector)


## Reserves the movement for `agent` when allowed. During AMBER only agents
## that cannot stop comfortably (or give-way agents already waiting at the
## line) may go.
func request_entry(connector: Lane, agent: TrafficAgent, can_stop: bool) -> bool:
	if agent.granted_connector == connector:
		return true
	var state := group_state(_approach_group(connector))
	if state == Light.RED:
		denied_requests += 1
		return false
	if state == Light.AMBER:
		var waiting_give_way := connector.yields and agent.speed < 1.0
		if can_stop and not waiting_give_way:
			denied_requests += 1
			return false
	if not (_conflicts_clear(connector) and _exit_clear(connector, agent) and _yield_clear(connector)):
		denied_requests += 1
		return false
	connector.reserved += 1
	grants_issued[_approach_group(connector)] += 1
	return true


func release(_agent: TrafficAgent, connector: Lane) -> void:
	connector.reserved = maxi(connector.reserved - 1, 0)


func _conflicts_clear(connector: Lane) -> bool:
	for other in connector.conflicts:
		if other.reserved > 0 or not other.agents.is_empty():
			return false
	return true


func _exit_clear(connector: Lane, agent: TrafficAgent) -> bool:
	var exit_lane := connector.successors[0]
	var needed := agent.half_length * 2.0 + exit_clearance
	for other in exit_lane.agents:
		if other.s - other.half_length < needed:
			return false
	return true


func _yield_clear(connector: Lane) -> bool:
	if not connector.yields:
		return true
	for other in connector.conflicts:
		if other.yields:
			continue
		var state := group_state(_approach_group(other))
		if state == Light.RED:
			continue
		var approach := other.predecessors[0]
		for a in approach.agents:
			if a.next_lane != other:
				continue
			if approach.length - a.s > yield_check_distance:
				continue
			if a.granted_connector == other:
				return false
			if state == Light.GREEN and a.speed > 0.5:
				return false
	return true


# --- Visuals ---

func _build_visuals(materials: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	st.set_normal(Vector3.UP)
	st.set_color(Color(0.21, 0.21, 0.23))
	for v in [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half),
			Vector3(-half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]:
		st.add_vertex(v)
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = st.commit()
	surface.material_override = materials["asphalt"]
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)

	# Stop lines and signal heads per incoming lane group.
	var marks := SurfaceTool.new()
	marks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arms_done := {}
	var inv := global_transform.affine_inverse()
	for lane in incoming:
		var end := inv * lane.end_point()
		var tangent := (inv.basis * lane.end_tangent()).normalized()
		var across := tangent.cross(Vector3.UP)
		var back := end - tangent * 0.6
		var w := lane.width * 0.5
		marks.set_normal(Vector3.UP)
		marks.set_color(Color(0.92, 0.92, 0.88))
		var y := Vector3.UP * 0.014
		var a := back - across * w + y
		var b := back + across * w + y
		var c := b - tangent * 0.4
		var d := a - tangent * 0.4
		for v in [a, b, c, a, c, d]:
			marks.add_vertex(v)
		if not arms_done.has(lane.approach_arm):
			arms_done[lane.approach_arm] = true
			# Signal head on the kerb (left) side of the approach.
			var left := -across
			var outer := back + left * (lane.width * (lane.direction_lane_count - lane.lane_index) + 1.2)
			_make_signal_head(outer, tangent, lane.approach_arm % 2)
	var mark_mesh := MeshInstance3D.new()
	mark_mesh.name = "StopLines"
	mark_mesh.mesh = marks.commit()
	mark_mesh.material_override = materials["markings"]
	mark_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mark_mesh)
	_update_signal_heads()


func _make_signal_head(local_pos: Vector3, facing: Vector3, group: int) -> void:
	var root := Node3D.new()
	root.name = "Signal%d" % _signal_heads.size()
	root.position = local_pos
	root.basis = MathUtil.basis_from_forward(-facing)
	add_child(root)
	var pole := MeshInstance3D.new()
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.15, 3.2, 0.15)
	pole.mesh = pole_mesh
	pole.position = Vector3(0, 1.6, 0)
	pole.material_override = _materials["dark"]
	root.add_child(pole)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.42, 1.1, 0.3)
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.position = Vector3(0, 3.4, 0)
	head.material_override = _materials["dark"]
	root.add_child(head)
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.26, 0.26, 0.06)
	var lamps: Array[MeshInstance3D] = []
	for i in 3:
		var lamp := MeshInstance3D.new()
		lamp.mesh = lamp_mesh
		lamp.position = Vector3(0, 3.75 - i * 0.34, -0.17)
		root.add_child(lamp)
		lamps.append(lamp)
	for mi in [pole, head]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_signal_heads.append({"group": group, "lamps": lamps})


func _update_signal_heads() -> void:
	if _materials.is_empty():
		return
	for head in _signal_heads:
		var state := group_state(int(head["group"]))
		var lamps: Array[MeshInstance3D] = head["lamps"]
		lamps[0].material_override = _materials["lamp_red_on"] if state == Light.RED else _materials["lamp_off"]
		lamps[1].material_override = _materials["lamp_amber_on"] if state == Light.AMBER else _materials["lamp_off"]
		lamps[2].material_override = _materials["lamp_green_on"] if state == Light.GREEN else _materials["lamp_off"]
