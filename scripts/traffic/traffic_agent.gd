class_name TrafficAgent
extends AnimatableBody3D
## Lightweight kinematic lane follower — no rigid-body simulation.
##
## Position is (lane, s). Speed is controlled by the Intelligent Driver Model
## against the nearest of: the vehicle ahead (this lane and the next), the
## player, and an intersection stop line without permission. Curves are taken
## at curvature-limited advisory speeds. Pooled: activate()/deactivate().
## TrafficManager calls step() for every active agent each physics tick.

const LOOKAHEAD := 60.0
const TRAFFIC_LAYER := 4
const ADVISORY_PROBES: Array[float] = [0.0, 8.0, 16.0, 32.0]

var agent_id := -1
var vehicle_class: TrafficVehicleClass
var is_active := false

var lane: Lane
var next_lane: Lane
var prev_lane: Lane
var s := 0.0
var speed := 0.0
var target_speed := 10.0

var velocity_vec := Vector3.ZERO
var forward_vec := Vector3.FORWARD
var right_vec := Vector3.RIGHT
var half_length := 2.0
var half_width := 0.9

var hold_timer := 0.0
var stopped_time := 0.0
var at_sink := false
var waiting_for_signal := false
var granted_connector: Lane = null
var leader_gap := INF

## Scoring/collision timestamps (SimClock seconds).
var last_award_time := -1000.0
var last_collision_time := -1000.0
## v0.03A1: held stationary by a traffic incident (driver arguing). Never
## despawned or recycled while set; TrafficIncidentManager clears it.
var incident_hold := false

var body_meshes: Array[MeshInstance3D] = []

var _lead_gap := INF
var _lead_speed := 0.0
var _player_speed := 0.0


func activate(p_lane: Lane, p_s: float, p_speed: float, p_target: float, p_next: Lane) -> void:
	lane = p_lane
	s = p_s
	speed = p_speed
	target_speed = p_target
	next_lane = p_next
	prev_lane = p_lane.predecessors[0] if not p_lane.predecessors.is_empty() else null
	granted_connector = null
	hold_timer = 0.0
	stopped_time = 0.0
	incident_hold = false
	at_sink = false
	waiting_for_signal = false
	leader_gap = INF
	lane.agents.append(self)
	is_active = true
	visible = true
	_update_pose()
	# Teleport the physics body too so the jump from the pool is not treated
	# as a huge kinematic sweep.
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	collision_layer = TRAFFIC_LAYER
	reset_physics_interpolation()


func deactivate() -> void:
	if lane != null:
		lane.agents.erase(self)
	if granted_connector != null:
		granted_connector.intersection.release(self, granted_connector)
		granted_connector = null
	lane = null
	next_lane = null
	prev_lane = null
	is_active = false
	incident_hold = false
	visible = false
	collision_layer = 0
	speed = 0.0
	velocity_vec = Vector3.ZERO


## v0.03B: paint variant (index into the class body_colors).
func set_visual_variant(color_index: int) -> void:
	for mi in body_meshes:
		mi.mesh = TrafficArt.mesh_for(vehicle_class, color_index)


func set_body_material(material: Material) -> void:
	for mi in body_meshes:
		mi.material_override = material


func notify_player_contact(now: float) -> void:
	last_collision_time = now
	hold_timer = maxf(hold_timer, 1.5)


## Advances one physics tick. Returns false when the agent should be recycled.
func step(delta: float, ctx: TrafficManager) -> bool:
	if incident_hold:
		speed = move_toward(speed, 0.0, vehicle_class.max_decel * delta)
	elif hold_timer > 0.0:
		hold_timer -= delta
		speed = move_toward(speed, 0.0, vehicle_class.max_decel * delta)
	else:
		speed = maxf(0.0, speed + _compute_accel(ctx) * delta)
	if not _advance(speed * delta, ctx):
		return false
	_update_pose()
	stopped_time = stopped_time + delta if speed < 0.3 else 0.0
	return true


func _compute_accel(ctx: TrafficManager) -> float:
	var cls := vehicle_class
	var v := speed
	var a_max := cls.max_accel
	var b := cls.comfortable_decel
	var v0 := _desired_speed()
	var acc := maxf(a_max * (1.0 - pow(v / maxf(v0, 0.5), 4.0)), -b)

	_find_leader()
	var gap := _lead_gap
	var lead_v := _lead_speed
	var player_gap := _player_gap(ctx)
	if player_gap < gap:
		gap = player_gap
		lead_v = _player_speed
	var crossing_gap := _crossing_gap()
	if crossing_gap < gap:
		gap = crossing_gap
		lead_v = 0.0
	waiting_for_signal = false
	var stop_gap := _stop_line_gap()
	if stop_gap < gap:
		gap = stop_gap
		lead_v = 0.0
		waiting_for_signal = true
	if at_sink:
		gap = minf(gap, maxf(lane.length - s - half_length, 0.0))
		lead_v = 0.0
	leader_gap = gap

	if gap < LOOKAHEAD + 10.0:
		var dv := v - lead_v
		var s_star := cls.min_gap + maxf(0.0, v * cls.time_headway + v * dv / (2.0 * sqrt(a_max * b)))
		var ratio := s_star / maxf(gap, 0.05)
		acc -= a_max * ratio * ratio
	return clampf(acc, -cls.max_decel, a_max)


func _desired_speed() -> float:
	var v0 := target_speed
	var b := vehicle_class.comfortable_decel * 0.8
	for probe in ADVISORY_PROBES:
		var adv := _advisory(s + probe)
		var allowed := sqrt(adv * adv + 2.0 * b * probe)
		if allowed < v0:
			v0 = allowed
	return v0


func _advisory(d: float) -> float:
	if d <= lane.length or next_lane == null:
		return lane.advisory_at(minf(d, lane.length))
	return next_lane.advisory_at(minf(d - lane.length, next_lane.length))


func _find_leader() -> void:
	_lead_gap = INF
	_lead_speed = 0.0
	for a in lane.agents:
		if a == self or a.s <= s:
			continue
		var g := a.s - s - a.half_length - half_length
		if g < _lead_gap:
			_lead_gap = g
			_lead_speed = a.speed
	if _lead_gap < LOOKAHEAD or next_lane == null:
		return
	var base := lane.length - s - half_length
	_scan_lane(next_lane, base, false)
	if lane.successors.size() > 1:
		# Sibling connectors share their first metres with ours.
		for sibling in lane.successors:
			if sibling != next_lane:
				_scan_lane(sibling, base, true)
	if _lead_gap >= LOOKAHEAD and next_lane.successors.size() == 1 and base + next_lane.length < LOOKAHEAD:
		_scan_lane(next_lane.successors[0], base + next_lane.length, false)


func _scan_lane(l: Lane, base: float, near_start_only: bool) -> void:
	for a in l.agents:
		if near_start_only and a.s > a.half_length + half_length + 4.0:
			continue
		var g := base + a.s - a.half_length
		if g < _lead_gap:
			_lead_gap = g
			_lead_speed = a.speed


func _player_gap(ctx: TrafficManager) -> float:
	var to := ctx.player_position - global_position
	var d_long := to.dot(forward_vec)
	if d_long <= 0.0 or d_long > ctx.config.player_detection_distance:
		return INF
	if absf(to.dot(right_vec)) > half_width + ctx.player_half_width + 0.4:
		return INF
	_player_speed = maxf(ctx.player_velocity.dot(forward_vec), 0.0)
	return d_long - half_length - ctx.player_half_length


## Yield to people on a pedestrian crossing ahead (this lane or the next).
## Vehicles already over the crossing line carry on.
func _crossing_gap() -> float:
	var best := INF
	for i in lane.crossings.size():
		if lane.crossings[i].occupied_count <= 0:
			continue
		var g := lane.crossing_s[i] - 2.5 - s - half_length
		if g > -0.5 and g < best:
			best = maxf(g, 0.0)
	if next_lane != null and best == INF:
		var base := lane.length - s - half_length
		for i in next_lane.crossings.size():
			if next_lane.crossings[i].occupied_count <= 0:
				continue
			var g2 := base + next_lane.crossing_s[i] - 2.5
			if g2 < LOOKAHEAD and g2 < best:
				best = maxf(g2, 0.0)
	return best


func _stop_line_gap() -> float:
	if next_lane == null or not next_lane.is_connector or granted_connector == next_lane:
		return INF
	var dist := lane.length - s - half_length
	if dist > LOOKAHEAD:
		return INF
	var ix := next_lane.intersection
	var commit := speed * speed / (2.0 * vehicle_class.comfortable_decel) + 5.0
	if dist <= commit:
		var can_stop := speed * speed / (2.0 * maxf(dist, 0.5)) <= vehicle_class.comfortable_decel * 1.3
		if ix.request_entry(next_lane, self, can_stop):
			granted_connector = next_lane
			return INF
		return maxf(dist - 0.5, 0.0)
	if ix.is_movement_open(next_lane, self):
		return INF
	return maxf(dist - 0.5, 0.0)


func _advance(ds: float, ctx: TrafficManager) -> bool:
	s += ds
	while s > lane.length:
		if next_lane == null:
			# End of a sink lane (inside a tunnel). Recycle unless the player
			# could see it vanish; then wait at the end until out of view.
			if ctx.can_despawn_silently(self):
				return false
			at_sink = true
			s = lane.length
			speed = 0.0
			return true
		if next_lane.is_connector and granted_connector != next_lane:
			# Safety net: never enter a junction without permission.
			if not next_lane.intersection.request_entry(next_lane, self, false):
				s = lane.length - 0.01
				speed = 0.0
				return true
			granted_connector = next_lane
		var overflow := s - lane.length
		lane.agents.erase(self)
		if lane.is_connector and granted_connector == lane:
			lane.intersection.release(self, lane)
			granted_connector = null
		prev_lane = lane
		lane = next_lane
		s = overflow
		lane.agents.append(self)
		next_lane = ctx.choose_next_lane(lane, vehicle_class.is_heavy)
	if next_lane == null and lane.length - s < half_length + 1.0:
		at_sink = true
	return true


func _update_pose() -> void:
	var span := half_length * 0.6
	var front := _sample(s + span)
	var rear := _sample(s - span)
	var dir := front - rear
	dir.y = 0.0
	if dir.length_squared() > 0.000001:
		dir = dir.normalized()
	else:
		dir = forward_vec
	forward_vec = dir
	right_vec = dir.cross(Vector3.UP)
	global_transform = Transform3D(MathUtil.basis_from_forward(dir), (front + rear) * 0.5)
	velocity_vec = dir * speed


func _sample(d: float) -> Vector3:
	if d > lane.length:
		if next_lane != null:
			return next_lane.sample_position(minf(d - lane.length, next_lane.length))
		return lane.end_point() + lane.end_tangent() * (d - lane.length)
	if d < 0.0:
		if prev_lane != null:
			return prev_lane.sample_position(maxf(prev_lane.length + d, 0.0))
		return lane.start_point() + lane.start_tangent() * d
	return lane.sample_position(d)
