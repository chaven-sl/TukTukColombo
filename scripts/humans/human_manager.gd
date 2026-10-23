class_name HumanManager
extends Node3D
## Owns every HumanAgent: a fixed pool, ambient population around the player,
## waiting groups at GROUP spots, passengers on request, one update loop, and
## the player-safety checks that emit PEDESTRIAN_DANGER / PEDESTRIAN_IMPACT.
##
## Rules that must never change: pedestrian incidents are never scorable —
## they go to EventBus.pedestrian_* only, never to the vehicle near-miss
## detector or any reward path.

signal human_released(agent: HumanAgent)
signal passenger_lost(agent: HumanAgent)

@export var config: PedestrianConfig

var network: PedestrianNetwork
var traffic: TrafficManager
var player: TukController
var camera: Camera3D
var rng := RandomNumberGenerator.new()

var all_agents: Array[HumanAgent] = []
var active: Array[HumanAgent] = []
var _free: Array[HumanAgent] = []
var _pedestrian_behaviour := PedestrianBehaviour.new()

# Cached per tick.
var player_position := Vector3.ZERO
var player_velocity := Vector3.ZERO

# Diagnostics (debug HUD, tests).
var stats_spawned := 0
var stats_released := 0
var stats_crossings_started := 0
var stats_crossings_completed := 0
var stats_crossings_abandoned := 0
var stats_danger_events := 0
var stats_impacts := 0
var stats_reactions := 0
var stats_evasions := 0
var stats_dives := 0
var last_tick_usec := 0
var _camera_pos := Vector3.ZERO
var _spawn_timer := 0.0
var _group_spots_active: Dictionary = {}


func setup(p_network: PedestrianNetwork, p_traffic: TrafficManager, p_player: TukController, p_camera: Camera3D, seed_value: int = 0) -> void:
	network = p_network
	traffic = p_traffic
	player = p_player
	camera = p_camera
	if config == null:
		config = PedestrianConfig.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	for i in config.pool_capacity:
		var agent := HumanAgentFactory.create_agent(i)
		add_child(agent)
		all_agents.append(agent)
		_free.append(agent)
	_cache_player()


func pool_capacity() -> int:
	return all_agents.size()


func free_count() -> int:
	return _free.size()


func ambient_count() -> int:
	var n := 0
	for a in active:
		if a.role != HumanAgent.Role.PASSENGER and a.role != HumanAgent.Role.TRAFFIC_DRIVER:
			n += 1
	return n


func driver_count() -> int:
	var n := 0
	for a in active:
		if a.role == HumanAgent.Role.TRAFFIC_DRIVER:
			n += 1
	return n


func _exit_tree() -> void:
	active.clear()
	HumanAgentFactory.clear_cache()


# --- Pool ---

func _acquire(role: HumanAgent.Role, node: int) -> HumanAgent:
	if _free.is_empty() or node < 0:
		return null
	var agent: HumanAgent = _free.pop_back()
	agent.reset_for_pool()
	agent.role = role
	agent.current_node = node
	agent.global_position = network.node_pos[node]
	agent.visible = true
	agent.is_pooled_active = true
	agent.walk_speed = _roll_walk_speed()
	agent.crossing_margin = rng.randf_range(config.crossing_margin_seconds.x, config.crossing_margin_seconds.y)
	agent.set_appearance(rng.randi() % CharacterBuilder.variant_count())
	agent.awareness_timer = rng.randf() * config.awareness_interval
	agent.reset_physics_interpolation()
	active.append(agent)
	stats_spawned += 1
	return agent


func release(agent: HumanAgent) -> void:
	if not agent.is_pooled_active:
		return
	if agent.state != HumanAgent.State.RETURNING_TO_POOL:
		agent.set_state(HumanAgent.State.RETURNING_TO_POOL)
	agent.set_state(HumanAgent.State.INACTIVE)
	agent.is_pooled_active = false
	agent.visible = false
	agent.reset_for_pool()
	active.erase(agent)
	if _free.has(agent):
		push_error("[HumanManager] double release of %s" % agent.name)
	else:
		_free.append(agent)
	stats_released += 1
	human_released.emit(agent)


func _roll_walk_speed() -> float:
	var w := config.speed_band_weights
	var r := rng.randf() * (w.x + w.y + w.z)
	var band := config.normal_speed_kmh
	if r < w.x:
		band = config.slow_speed_kmh
	elif r > w.x + w.y:
		band = config.fast_speed_kmh
	return rng.randf_range(band.x, band.y) / 3.6


# --- Passengers ---

## A physical passenger waiting at `spot`. Never despawned by distance.
func acquire_passenger(profile: PassengerProfile, spot: PedestrianSpot) -> HumanAgent:
	if active.size() >= config.max_active:
		_evict_one_ambient()
	var agent := _acquire(HumanAgent.Role.PASSENGER, spot.node_id)
	if agent == null:
		return null
	agent.passenger_profile = profile
	agent.home_spot = spot
	agent.behaviour = PassengerBehaviour.new()
	agent.walk_speed = config.normal_speed_kmh.y / 3.6
	agent.show_passenger_marker(profile.marker_color)
	agent.set_appearance(profile.appearance_variant)
	agent.set_state(HumanAgent.State.WAITING_FOR_PICKUP)
	return agent


func _evict_one_ambient() -> void:
	var far: HumanAgent = null
	var far_d := -1.0
	for a in active:
		if a.role == HumanAgent.Role.PASSENGER or a.role == HumanAgent.Role.TRAFFIC_DRIVER or a.state == HumanAgent.State.CROSSING:
			continue
		var d := a.global_position.distance_squared_to(player_position)
		if d > far_d:
			far_d = d
			far = a
	if far != null:
		release(far)


# --- Traffic drivers (v0.03A1 incidents) ---

## A driver stepping out of a traffic vehicle at `door`. Uses the same pool
## (evicting a far ambient person if needed); returns null if none is free,
## in which case the incident stays in the vehicle (horn and shout only).
## The incident manager owns its lifetime and must release() it.
func acquire_driver(door: Vector3, facing: Vector3) -> HumanAgent:
	if active.size() >= config.max_active or _free.is_empty():
		_evict_one_ambient()
	var agent := _acquire(HumanAgent.Role.TRAFFIC_DRIVER, network.nearest_node(door))
	if agent == null:
		return null
	agent.global_position = Vector3(door.x, maxf(door.y, 0.0), door.z)
	agent.face(facing)
	agent.behaviour = DriverBehaviour.new()
	agent.set_appearance([0, 1, 2, 7][agent.human_id % 4])  # shirt/tee drivers
	agent.reset_physics_interpolation()
	agent.set_state(HumanAgent.State.EXITING_VEHICLE)
	return agent


# --- Main loop ---

func _physics_process(delta: float) -> void:
	var ps := PerfSections.begin()
	_physics_process_body(delta)
	PerfSections.end(PerfSections.HUMAN_LOGIC, ps)


func _physics_process_body(delta: float) -> void:
	if network == null:
		return
	var t0 := Time.get_ticks_usec()
	_cache_player()
	_camera_pos = camera.global_position if camera != null else player_position
	var pres_us := 0.0
	var i := active.size() - 1
	while i >= 0:
		var agent := active[i]
		if agent.state == HumanAgent.State.EVADING:
			_tick_evade(agent, delta)
		elif agent.behaviour != null:
			agent.behaviour.tick(agent, delta, self)
		var pv := PerfSections.begin()
		agent.update_visual(delta, _camera_pos)
		if PerfSections.enabled:
			pres_us += float(Time.get_ticks_usec() - pv)
		i -= 1
	_check_player_safety()
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = config.spawn_interval
		_maintain_population()
	last_tick_usec = Time.get_ticks_usec() - t0
	PerfSections.add(PerfSections.HUMAN_PRESENTATION, pres_us)


func _cache_player() -> void:
	if player != null:
		player_position = player.global_position
		player_velocity = player.linear_velocity


func is_in_view(pos: Vector3) -> bool:
	if camera == null:
		return false
	if pos.distance_squared_to(player_position) > 110.0 * 110.0:
		return false
	return camera.is_position_in_frustum(pos + Vector3.UP)


func _maintain_population() -> void:
	# Despawn ambient people far away and out of view.
	var far_sq := config.despawn_distance * config.despawn_distance
	for idx in range(active.size() - 1, -1, -1):
		var a := active[idx]
		if a.role == HumanAgent.Role.PASSENGER or a.role == HumanAgent.Role.TRAFFIC_DRIVER or a.state == HumanAgent.State.CROSSING:
			continue
		if a.global_position.distance_squared_to(player_position) > far_sq and not is_in_view(a.global_position):
			if a.role == HumanAgent.Role.GROUP_MEMBER and a.home_spot != null:
				_group_spots_active.erase(a.home_spot)
			release(a)
	_maintain_groups()
	if ambient_count() >= config.ambient_target or active.size() >= config.max_active:
		return
	if _free.size() <= _reserved_needed():
		return
	_spawn_ambient()


func _reserved_needed() -> int:
	var passengers := 0
	for a in active:
		if a.role == HumanAgent.Role.PASSENGER:
			passengers += 1
	# One slot is always kept for a traffic driver getting out (v0.03A1).
	var driver_slot := 1 if driver_count() == 0 else 0
	return maxi(config.reserved_for_passengers - passengers, 0) + driver_slot


func _maintain_groups() -> void:
	for spot in network.spots_of_kind(PedestrianSpot.Kind.GROUP):
		if _group_spots_active.has(spot):
			continue
		if spot.global_position.distance_to(player_position) > config.group_activation_distance:
			continue
		if is_in_view(spot.global_position) and spot.global_position.distance_to(player_position) < 70.0:
			continue
		if config.max_active - active.size() < 3 or _free.size() - _reserved_needed() < 3:
			return
		var anchor := network.node_pos[spot.node_id]
		var out := network.node_out[spot.node_id]
		var side := out.cross(Vector3.UP)
		for k in 3:
			var agent := _acquire(HumanAgent.Role.GROUP_MEMBER, spot.node_id)
			if agent == null:
				break
			agent.home_spot = spot
			agent.behaviour = _pedestrian_behaviour
			agent.global_position = anchor + side * (k - 1) * 0.8 + out * (0.4 + 0.3 * (k % 2))
			agent.face(-out + side * (0.5 - k * 0.5))
			agent.idle_timer = rng.randf_range(5.0, 15.0)
			agent.set_state(HumanAgent.State.IDLE)
		_group_spots_active[spot] = true


func _spawn_ambient() -> void:
	var min_sq := config.spawn_min_distance * config.spawn_min_distance
	var max_sq := config.spawn_max_distance * config.spawn_max_distance
	var candidates := PackedInt32Array()
	for n in network.node_pos.size():
		var p := network.node_pos[n]
		var d2 := p.distance_squared_to(player_position)
		if d2 < min_sq or d2 > max_sq:
			continue
		if is_in_view(p) and d2 < 70.0 * 70.0:
			continue
		candidates.append(n)
	if candidates.is_empty():
		return
	# v0.03B: zone density — busy pavements (bus stand, market) attract more
	# people; quiet service streets fewer. Composition, not a bigger population.
	var total := 0.0
	for n in candidates:
		total += network.node_weight[n] if n < network.node_weight.size() else 1.0
	var pick := rng.randf() * total
	var node := candidates[candidates.size() - 1]
	for n in candidates:
		pick -= network.node_weight[n] if n < network.node_weight.size() else 1.0
		if pick <= 0.0:
			node = n
			break
	var w_walk := config.weight_sidewalk_walker
	var w_cross := config.weight_crossing_pedestrian
	var w_wait := config.weight_waiting_pedestrian
	var r := rng.randf() * (w_walk + w_cross + w_wait)
	var role := HumanAgent.Role.SIDEWALK_WALKER
	if r > w_walk + w_cross:
		role = HumanAgent.Role.WAITING_PEDESTRIAN
		var waits := network.spots_of_kind(PedestrianSpot.Kind.WAIT)
		if not waits.is_empty():
			var spot: PedestrianSpot = waits[rng.randi() % waits.size()]
			var sp := network.node_pos[spot.node_id]
			if sp.distance_squared_to(player_position) >= min_sq and not (is_in_view(sp) and sp.distance_squared_to(player_position) < 4900.0):
				node = spot.node_id
	elif r > w_walk:
		role = HumanAgent.Role.CROSSING_PEDESTRIAN
	var agent := _acquire(role, node)
	if agent == null:
		return
	agent.behaviour = _pedestrian_behaviour
	agent.idle_timer = rng.randf_range(0.2, 2.0) if role != HumanAgent.Role.WAITING_PEDESTRIAN else rng.randf_range(10.0, 30.0)
	agent.set_state(HumanAgent.State.IDLE)


# --- Player safety (cheap footprint checks; never a reward path) ---

func _check_player_safety() -> void:
	if player == null:
		return
	var xf := player.global_transform
	var f3 := -xf.basis.z
	var f := Vector2(f3.x, f3.z)
	if f.length_squared() < 0.0001:
		return
	f = f.normalized()
	var body_offset := xf.basis * player.tuning.body_center
	var c := Vector2(xf.origin.x + body_offset.x, xf.origin.z + body_offset.z)
	var ext := player.half_extents()
	var speed_kmh := player.speed_kmh
	var v2 := Vector2(player_velocity.x, player_velocity.z)
	var on_raised_surface := xf.origin.y > 0.08
	var now := SimClock.now()
	var speed_ms := v2.length()
	var horizon := config.pavement_threat_horizon_s if on_raised_surface else config.threat_horizon_s
	var scan := maxf(15.0, speed_ms * horizon + 4.0)
	for idx in range(active.size() - 1, -1, -1):
		var a := active[idx]
		if a.state == HumanAgent.State.RIDING or a.state == HumanAgent.State.BOARDING or not a.visible:
			continue
		var p := a.global_position
		var hp := Vector2(p.x, p.z)
		if hp.distance_squared_to(c) > scan * scan:
			continue
		if config.emergency_evasion and speed_kmh >= config.evade_min_kmh and _check_threat(a, hp, c, v2, ext, horizon, speed_kmh):
			continue
		var clearance := OrientedRect.point_distance(hp, c, f, ext.x, ext.y) - config.person_radius
		if clearance <= 0.0 and speed_kmh >= config.impact_min_speed_kmh:
			_pedestrian_impact(a, clearance, speed_kmh)
			continue
		# Reaction to an approaching tuk.
		var to := hp - c
		var dist := to.length()
		if dist < config.react_distance and dist > 0.01:
			var closing := v2.dot(to / dist) * 3.6
			var lateral := absf(to.dot(Vector2(-f.y, f.x)))
			if closing > config.react_closing_speed_kmh and lateral < config.react_lateral:
				# Step away from the tuk's line of travel (not blindly "off the road").
				var side := Vector2(-f.y, f.x)
				var sign_side := signf(to.dot(side))
				if sign_side == 0.0:
					sign_side = 1.0
				var away2 := side * sign_side
				a.react_dir = Vector3(away2.x, 0.0, away2.y)
				_react_to_player(a)
		if now < a.danger_cooldown_until:
			continue
		var close_pass := clearance < config.danger_clearance and speed_kmh > config.danger_speed_kmh
		var sidewalk := on_raised_surface and not a.is_on_road() and clearance < config.sidewalk_danger_clearance \
				and speed_kmh > config.sidewalk_danger_speed_kmh
		if close_pass or sidewalk:
			var cause := PedestrianEvent.Cause.SIDEWALK_DRIVING if sidewalk and not close_pass else PedestrianEvent.Cause.CLOSE_PASS
			_emit_danger(a, cause, clearance, speed_kmh)


# --- Emergency evasion (v0.03A2) ---

## Projects the tuk's straight-line path `horizon` seconds ahead; a person
## inside the corridor before the closest approach evades (EVADE) or dives
## aside (DIVE) — before any contact, never only on touch. Returns true when
## the person is (now) evading.
func _check_threat(a: HumanAgent, hp: Vector2, c: Vector2, v2: Vector2, ext: Vector2, horizon: float, speed_kmh: float) -> bool:
	if a.state == HumanAgent.State.EVADING:
		return true
	if not _can_evade(a):
		return false
	var to := hp - c
	var vv := v2.length_squared()
	if vv < 0.25:
		return false
	var t := to.dot(v2) / vv
	if t <= 0.0 or t > horizon:
		return false
	var miss := (to - v2 * t).length()
	if miss > ext.x + config.threat_corridor_margin:
		return false
	var dive := speed_kmh >= config.dive_min_kmh or t < config.dive_ttc_s
	start_evade(a, Vector3(v2.x, 0.0, v2.y).normalized(), Vector3(c.x, a.global_position.y, c.y), dive)
	return true


func _can_evade(a: HumanAgent) -> bool:
	match a.state:
		HumanAgent.State.IDLE, HumanAgent.State.WALKING, HumanAgent.State.WAITING_TO_CROSS, HumanAgent.State.REACTING, \
		HumanAgent.State.WAITING_FOR_PICKUP, HumanAgent.State.EXITING, HumanAgent.State.EXITING_VEHICLE, \
		HumanAgent.State.APPROACHING_PLAYER, HumanAgent.State.ARGUING, HumanAgent.State.RETURNING_TO_VEHICLE:
			return true
	# CROSSING people keep the v0.02 HURRY (onwards across, not into a lane).
	return false


## Starts an escape away from a threat moving along `dir` from `threat_pos`.
func start_evade(a: HumanAgent, dir: Vector3, threat_pos: Vector3, dive: bool) -> void:
	var resume := HumanAgent.State.IDLE
	match a.role:
		HumanAgent.Role.PASSENGER:
			resume = HumanAgent.State.EXITING if a.state == HumanAgent.State.EXITING else HumanAgent.State.WAITING_FOR_PICKUP
		HumanAgent.Role.TRAFFIC_DRIVER:
			resume = HumanAgent.State.RETURNING_TO_VEHICLE
	a.evade_target = pick_evade_target(a.global_position, dir, threat_pos, config.dive_distance if dive else config.evade_distance)
	a.evade_speed = (config.dive_speed_kmh if dive else config.evade_speed_kmh) / 3.6
	a.evade_settle = rng.randf_range(config.evade_settle_s.x, config.evade_settle_s.y)
	a.evade_dive = dive
	a.evade_resume = resume
	if a.state == HumanAgent.State.WAITING_TO_CROSS:
		a.crossing = null
	if not a.set_state(HumanAgent.State.EVADING):
		return
	a.set_reaction(HumanAgent.Reaction.DIVE if dive else HumanAgent.Reaction.EVADE)
	a.face(Vector3(threat_pos.x - a.global_position.x, 0.0, threat_pos.z - a.global_position.z))
	if dive:
		stats_dives += 1
	else:
		stats_evasions += 1


## Chooses where to escape to. Preference: away from the tuk's path, deeper
## onto pavement/forecourt (not into a traffic lane), towards the pedestrian
## network, never through a building/wall (ray + point checks), never off map.
func pick_evade_target(from: Vector3, dir: Vector3, threat_pos: Vector3, dist: float) -> Vector3:
	var side := Vector3(-dir.z, 0.0, dir.x)
	var rel := from - threat_pos
	var my_side := signf(rel.dot(side))
	if my_side == 0.0:
		my_side = 1.0
	var candidates: Array[Vector3] = [
		side * my_side, (side * my_side + dir * 0.4).normalized(), (side * my_side - dir * 0.3).normalized(),
		-side * my_side, (-side * my_side + dir * 0.4).normalized(),
	]
	var best := from
	var best_score := -INF
	var road := traffic.network if traffic != null else null
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	for k in candidates.size():
		var target := from + candidates[k] * dist
		target.y = from.y
		var score := 0.0
		if k < 3:
			score += 4.0  # stay on the side you are already on: away from the path
		if road != null:
			if not road.district_rect.has_point(Vector2(target.x, target.z)):
				score -= 50.0
			if WorldSurface.is_on_carriageway(road, target, 0.3):
				score -= 8.0  # never prefer a live traffic lane
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.9, target + Vector3.UP * 0.9, 1)
			if not space.intersect_ray(q).is_empty():
				score -= 30.0  # building / wall / post in the way
		var node := network.nearest_node(target)
		if node >= 0:
			score -= network.node_pos[node].distance_to(target) * 0.3
		if score > best_score:
			best_score = score
			best = target
	return best


func _tick_evade(a: HumanAgent, delta: float) -> void:
	a.state_timer += delta
	var mult := a.evade_speed / maxf(a.walk_speed, 0.3)
	a.speed_multiplier = mult
	var arrived := a.global_position.distance_to(a.evade_target) < 0.15 or a.step_towards(a.evade_target, delta)
	if a.visual != null:
		if not arrived and a.evade_dive:
			# Placeholder "jump aside": hop + lean until real animation exists.
			a.visual.position.y = absf(sin(a.state_timer * 9.0)) * 0.35
			a.visual.rotation.z = 0.35
		else:
			a.visual.rotation.z = 0.0
	if not arrived:
		a.idle_timer = a.evade_settle
		return
	a.is_moving = false
	a.idle_timer -= delta
	var to_player := player_position - a.global_position
	a.face(Vector3(to_player.x, 0.0, to_player.z))
	if a.idle_timer > 0.0:
		return
	a.speed_multiplier = 1.0
	a.set_reaction(HumanAgent.Reaction.NONE)
	if a.visual != null:
		a.visual.rotation.z = 0.0
	if a.role != HumanAgent.Role.PASSENGER and a.role != HumanAgent.Role.TRAFFIC_DRIVER:
		a.current_node = network.nearest_node(a.global_position)  # rejoin the network
		a.path = PackedInt32Array()
		a.idle_timer = rng.randf_range(0.3, 1.0)
	a.set_state(a.evade_resume)


func _react_to_player(a: HumanAgent) -> void:
	match a.state:
		HumanAgent.State.IDLE, HumanAgent.State.WALKING, HumanAgent.State.WAITING_TO_CROSS, HumanAgent.State.WAITING_FOR_PICKUP:
			if a.reaction != HumanAgent.Reaction.NONE and a.state == HumanAgent.State.REACTING:
				return
			a.resume_state = a.state
			a.reaction_timer = config.reaction_seconds
			a.set_reaction(HumanAgent.Reaction.STEP_BACK if a.state != HumanAgent.State.WAITING_FOR_PICKUP else HumanAgent.Reaction.FREEZE)
			if a.behaviour is PassengerBehaviour:
				return  # passengers flinch (indicator) but keep their state
			a.set_state(HumanAgent.State.REACTING)
			stats_reactions += 1
		HumanAgent.State.CROSSING:
			if a.reaction != HumanAgent.Reaction.HURRY:
				a.set_reaction(HumanAgent.Reaction.HURRY)
				a.speed_multiplier = config.hurry_multiplier
				stats_reactions += 1
				report_forced_hurry(a)


## A crossing person had to hurry because of the player: unsafe driving.
func report_forced_hurry(a: HumanAgent) -> void:
	if SimClock.now() < a.danger_cooldown_until:
		return
	var hp := Vector2(a.global_position.x, a.global_position.z)
	var clearance := hp.distance_to(Vector2(player_position.x, player_position.z))
	_emit_danger(a, PedestrianEvent.Cause.FORCED_HURRY, clearance, player.speed_kmh if player != null else 0.0)


func _emit_danger(a: HumanAgent, cause: PedestrianEvent.Cause, clearance: float, speed_kmh: float) -> void:
	a.danger_cooldown_until = SimClock.now() + config.danger_cooldown
	var ev := PedestrianEvent.new()
	ev.kind = PedestrianEvent.Kind.DANGER
	ev.cause = cause
	ev.human_id = a.human_id
	ev.clearance = maxf(clearance, 0.0)
	ev.player_speed_kmh = speed_kmh
	ev.position = a.global_position
	ev.timestamp = SimClock.now()
	stats_danger_events += 1
	EventBus.pedestrian_danger.emit(ev)


## Non-graphic: the person is removed from the scene immediately (no ragdoll,
## no physics toy), the event is broadcast, gameplay systems react.
func _pedestrian_impact(a: HumanAgent, clearance: float, speed_kmh: float) -> void:
	var ev := PedestrianEvent.new()
	ev.kind = PedestrianEvent.Kind.IMPACT
	ev.cause = PedestrianEvent.Cause.CONTACT
	ev.human_id = a.human_id
	ev.clearance = clearance
	ev.player_speed_kmh = speed_kmh
	ev.position = a.global_position
	ev.timestamp = SimClock.now()
	stats_impacts += 1
	var was_passenger := a.role == HumanAgent.Role.PASSENGER
	if a.role == HumanAgent.Role.GROUP_MEMBER and a.home_spot != null:
		_group_spots_active.erase(a.home_spot)
	release(a)
	if was_passenger:
		passenger_lost.emit(a)
	EventBus.pedestrian_impact.emit(ev)


## Debug summary of human states.
func state_counts() -> Dictionary:
	var counts := {}
	for a in active:
		var key: String = HumanAgent.State.keys()[a.state]
		counts[key] = int(counts.get(key, 0)) + 1
	return counts
