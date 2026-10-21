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
var last_tick_usec := 0
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
		if a.role != HumanAgent.Role.PASSENGER:
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
	agent.set_body_color(HumanAgentFactory.SHIRTS[rng.randi() % HumanAgentFactory.SHIRTS.size()])
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
	agent.set_body_color(profile.marker_color.darkened(0.25))
	agent.set_state(HumanAgent.State.WAITING_FOR_PICKUP)
	return agent


func _evict_one_ambient() -> void:
	var far: HumanAgent = null
	var far_d := -1.0
	for a in active:
		if a.role == HumanAgent.Role.PASSENGER or a.state == HumanAgent.State.CROSSING:
			continue
		var d := a.global_position.distance_squared_to(player_position)
		if d > far_d:
			far_d = d
			far = a
	if far != null:
		release(far)


# --- Main loop ---

func _physics_process(delta: float) -> void:
	if network == null:
		return
	var t0 := Time.get_ticks_usec()
	_cache_player()
	var i := active.size() - 1
	while i >= 0:
		var agent := active[i]
		if agent.behaviour != null:
			agent.behaviour.tick(agent, delta, self)
		agent.update_visual(delta)
		i -= 1
	_check_player_safety()
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = config.spawn_interval
		_maintain_population()
	last_tick_usec = Time.get_ticks_usec() - t0


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
		if a.role == HumanAgent.Role.PASSENGER or a.state == HumanAgent.State.CROSSING:
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
	return maxi(config.reserved_for_passengers - passengers, 0)


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
	var node := candidates[rng.randi() % candidates.size()]
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
	for idx in range(active.size() - 1, -1, -1):
		var a := active[idx]
		if a.state == HumanAgent.State.RIDING or a.state == HumanAgent.State.BOARDING or not a.visible:
			continue
		var p := a.global_position
		var hp := Vector2(p.x, p.z)
		if hp.distance_squared_to(c) > 225.0:
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
