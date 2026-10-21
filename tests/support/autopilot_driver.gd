class_name AutopilotDriver
extends Node
## TEST-ONLY driver. Follows forward lanes of the loop with pure-pursuit
## steering, changes lanes around slower traffic and deliberately hugs the
## lane edge while overtaking so near misses happen naturally. It writes the
## same VehicleInputState a human would; it is never used in gameplay.

var vehicle: TukController
var network: RoadNetwork
var traffic: TrafficManager
var cruise_kmh := 58.0
var rng := RandomNumberGenerator.new()

var lane: Lane
var s := 0.0
var lateral_offset := 0.0
var lane_changes := 0

var _target_offset := 0.0
var _change_cooldown := 0.0
var _reacquire_timer := 0.0


func setup(p_vehicle: TukController, p_network: RoadNetwork, p_traffic: TrafficManager, seed_value: int) -> void:
	vehicle = p_vehicle
	network = p_network
	traffic = p_traffic
	rng.seed = seed_value
	process_physics_priority = -20
	vehicle.get_node("PlayerInput").set("enabled", false)
	vehicle.was_reset.connect(func() -> void: lane = null)
	_acquire_lane()


func _acquire_lane() -> void:
	var pos := vehicle.global_position
	var fwd := -vehicle.global_transform.basis.z
	var best: Lane = null
	var best_d := INF
	for l in network.lanes:
		if l.is_connector or l.successors.is_empty():
			continue
		var ls := l.closest_s(pos)
		var p := l.sample_position(ls)
		var d := p.distance_squared_to(pos)
		if l.sample_tangent(ls).dot(fwd) < 0.3:
			d += 400.0
		if d < best_d:
			best_d = d
			best = l
	lane = best
	if lane != null:
		s = lane.closest_s(pos)


func _pick_next(l: Lane) -> Lane:
	if l.successors.is_empty():
		return null
	for succ in l.successors:
		if not succ.is_connector:
			return succ
	for succ in l.successors:
		if succ.movement == IntersectionController.Movement.STRAIGHT:
			return succ
	return l.successors[0]


func _sample_ahead(distance: float) -> Vector3:
	var l := lane
	var d := s + distance
	var guard := 0
	while d > l.length and guard < 4:
		var nxt := _pick_next(l)
		if nxt == null:
			return l.end_point()
		d -= l.length
		l = nxt
		guard += 1
	var p := l.sample_position(d)
	var right := l.sample_tangent(d).cross(Vector3.UP)
	return p + right * lateral_offset


func _physics_process(delta: float) -> void:
	if vehicle == null:
		return
	if lane == null:
		_reacquire_timer -= delta
		if _reacquire_timer <= 0.0:
			_reacquire_timer = 0.5
			_acquire_lane()
		vehicle.input.clear()
		return
	var pos := vehicle.global_position
	s = lane.closest_s(pos, s, 15.0)
	while s > lane.length - 0.3:
		var nxt := _pick_next(lane)
		if nxt == null:
			lane = null
			return
		lane = nxt
		s = lane.closest_s(pos, 0.0, 15.0)
	_change_cooldown -= delta

	var speed := absf(vehicle.forward_speed)
	var fwd := -vehicle.global_transform.basis.z
	var right := fwd.cross(Vector3.UP)

	# --- Traffic awareness ---
	var lead_gap := INF
	var lead_speed := 0.0
	var pass_side := 0.0
	var pass_reach := 0.0
	for agent in traffic.active_agents:
		var to := agent.global_position - pos
		var along := to.dot(fwd)
		var across := to.dot(right) - lateral_offset
		if along < -2.0 or along > 40.0:
			continue
		var same_dir := agent.forward_vec.dot(fwd) > 0.5
		var my_lane := agent.lane == lane or lane.successors.has(agent.lane)
		if my_lane and same_dir and along > 0.0 and absf(across) < 2.2:
			var gap := along - agent.half_length - 1.3
			if gap < lead_gap:
				lead_gap = gap
				lead_speed = agent.speed
		elif absf(across) < 5.5 and along > -1.0 and along < 22.0 and (same_dir or agent.forward_vec.dot(fwd) < -0.5):
			pass_side = signf(across)
			# How far we may lean towards it: leave ~0.3-0.9 m of air.
			pass_reach = maxf(absf(across) - agent.half_width - 0.65 - rng.randf_range(0.3, 0.9), 0.0)

	# Overtake: move to a free neighbour lane when blocked by slower traffic.
	if lead_gap < 30.0 and lead_speed < cruise_kmh / 3.6 - 1.5 and _change_cooldown <= 0.0:
		for n in lane.neighbours:
			if _lane_clear(n, pos):
				lane = n
				s = lane.closest_s(pos)
				lane_changes += 1
				_change_cooldown = 3.0
				lateral_offset = 0.0
				break

	# Hug the lane edge towards traffic being passed (near-miss bait).
	if pass_side != 0.0:
		if absf(_target_offset) < 0.1 or signf(_target_offset) != pass_side:
			_target_offset = pass_side * minf(pass_reach, 1.6)
	else:
		_target_offset = 0.0
	lateral_offset = move_toward(lateral_offset, _target_offset, 1.2 * delta)

	# --- Speed ---
	var target := cruise_kmh / 3.6
	for probe in [8.0, 20.0, 35.0]:
		var adv := _advisory_ahead(probe) * 1.3
		target = minf(target, sqrt(adv * adv + 2.0 * 3.0 * probe))
	if lead_gap < 25.0:
		target = minf(target, lead_speed + maxf(lead_gap - 6.0, 0.0) * 0.4)
	var err := target - speed
	vehicle.input.throttle = clampf(err * 0.6 + 0.35, 0.0, 1.0) if err > -0.3 else 0.0
	vehicle.input.brake = clampf(-err * 0.35, 0.0, 1.0) if err < -1.0 else 0.0

	# --- Pure-pursuit steering ---
	var look := clampf(speed * 0.75 + 4.0, 5.0, 16.0)
	var aim := vehicle.global_transform.affine_inverse() * _sample_ahead(look)
	var alpha := atan2(aim.x, -aim.z)
	var wheel := atan(2.0 * vehicle.tuning.wheelbase * sin(alpha) / look)
	var limit := deg_to_rad(vehicle.tuning.steer_limit_deg(vehicle.speed_kmh))
	vehicle.input.steer = clampf(wheel / maxf(limit, 0.01), -1.0, 1.0)
	vehicle.input.handbrake = false


func _advisory_ahead(distance: float) -> float:
	var l := lane
	var d := s + distance
	while d > l.length:
		var nxt := _pick_next(l)
		if nxt == null:
			return l.advisory_at(l.length)
		d -= l.length
		l = nxt
	return l.advisory_at(d)


func _lane_clear(candidate: Lane, pos: Vector3) -> bool:
	for agent in candidate.agents:
		if agent.global_position.distance_to(pos) < 14.0:
			return false
	return true
