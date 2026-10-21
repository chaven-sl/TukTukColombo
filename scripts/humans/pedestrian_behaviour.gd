class_name PedestrianBehaviour
extends RefCounted
## Ambient roles: SIDEWALK_WALKER, CROSSING_PEDESTRIAN, WAITING_PEDESTRIAN,
## GROUP_MEMBER. Owns IDLE, WALKING, WAITING_TO_CROSS, CROSSING and REACTING.
##
## Crossing: walk to the kerb end of a crossing link, look (CrossingZone.assess)
## with this person's own margin, hesitate when questionable, cross when safe,
## hurry to the nearer side if danger appears mid-way. Uncontrolled crossings
## accept tighter gaps but never below time-to-clear + a minimum margin, so
## nobody steps out with no reaction time for the driver.


func tick(a: HumanAgent, delta: float, mgr: HumanManager) -> void:
	a.state_timer += delta
	match a.state:
		HumanAgent.State.IDLE:
			_idle(a, delta, mgr)
		HumanAgent.State.WALKING:
			_walk(a, delta, mgr)
		HumanAgent.State.WAITING_TO_CROSS:
			_wait_to_cross(a, delta, mgr)
		HumanAgent.State.CROSSING:
			_cross(a, delta, mgr)
		HumanAgent.State.REACTING:
			_react(a, delta, mgr)


func _idle(a: HumanAgent, delta: float, mgr: HumanManager) -> void:
	a.is_moving = false
	a.idle_timer -= delta
	if a.idle_timer > 0.0:
		return
	if a.role == HumanAgent.Role.GROUP_MEMBER:
		a.idle_timer = mgr.rng.randf_range(8.0, 20.0)
		return
	start_new_route(a, mgr)


## Picks a destination (via the graph) and starts walking.
func start_new_route(a: HumanAgent, mgr: HumanManager) -> void:
	var net := mgr.network
	var want_crossing := a.role == HumanAgent.Role.CROSSING_PEDESTRIAN
	var route := net.random_route(a.current_node, 4, 40, want_crossing, mgr.rng)
	if route.size() < 2:
		a.idle_timer = 2.0
		if a.state != HumanAgent.State.IDLE:
			a.set_state(HumanAgent.State.IDLE)
		return
	a.path = route
	a.path_index = 1
	a.set_state(HumanAgent.State.WALKING)


func _walk(a: HumanAgent, delta: float, mgr: HumanManager) -> void:
	if a.path_index >= a.path.size():
		_arrive(a, mgr)
		return
	var target_node := a.path[a.path_index]
	if a.step_towards(mgr.network.node_pos[target_node], delta):
		a.current_node = target_node
		a.path_index += 1
		if a.path_index >= a.path.size():
			_arrive(a, mgr)
			return
		var zone := mgr.network.crossing_between(a.current_node, a.path[a.path_index])
		if zone != null:
			a.crossing = zone
			a.crossing_from = mgr.network.node_pos[a.current_node]
			a.crossing_to = mgr.network.node_pos[a.path[a.path_index]]
			a.wait_time = 0.0
			zone.waiting_count += 1
			a.set_state(HumanAgent.State.WAITING_TO_CROSS)
			a.face(a.crossing_to - a.crossing_from)


func _arrive(a: HumanAgent, mgr: HumanManager) -> void:
	a.is_moving = false
	a.idle_timer = mgr.rng.randf_range(mgr.config.pause_seconds.x, mgr.config.pause_seconds.y)
	if a.role == HumanAgent.Role.WAITING_PEDESTRIAN:
		a.idle_timer = mgr.rng.randf_range(10.0, 30.0)
	a.set_state(HumanAgent.State.IDLE)


func _wait_to_cross(a: HumanAgent, delta: float, mgr: HumanManager) -> void:
	a.is_moving = false
	a.wait_time += delta
	a.awareness_timer -= delta
	if a.awareness_timer > 0.0:
		return
	a.awareness_timer = mgr.config.awareness_interval
	var zone := a.crossing
	var time_to_clear := zone.length() / maxf(a.walk_speed, 0.3)
	var margin := a.crossing_margin
	if zone.style == CrossingZone.Style.UNCONTROLLED:
		margin = maxf(margin * mgr.config.uncontrolled_margin_scale, mgr.config.min_uncontrolled_margin)
	var level := zone.assess(time_to_clear, margin, mgr.traffic, mgr.player_position, mgr.player_velocity, mgr.config.awareness_range)
	match level:
		CrossingZone.Level.SAFE:
			a.set_reaction(HumanAgent.Reaction.NONE)
			a.crossing_progress = 0.0
			zone.occupied_count += 1
			a.set_state(HumanAgent.State.CROSSING)
			mgr.stats_crossings_started += 1
		CrossingZone.Level.QUESTIONABLE:
			a.set_reaction(HumanAgent.Reaction.HESITATE)
		CrossingZone.Level.DANGER:
			if zone.last_threat_is_player and zone.last_min_ttc < 2.0:
				a.set_reaction(HumanAgent.Reaction.STEP_BACK)
			else:
				a.set_reaction(HumanAgent.Reaction.HESITATE)
	if a.state == HumanAgent.State.WAITING_TO_CROSS and a.wait_time > mgr.config.give_up_wait_seconds:
		# Give up and walk somewhere on this side instead.
		a.set_reaction(HumanAgent.Reaction.NONE)
		mgr.stats_crossings_abandoned += 1
		a.path = PackedInt32Array([a.current_node])
		a.path_index = 1
		a.set_state(HumanAgent.State.WALKING)


func _cross(a: HumanAgent, delta: float, mgr: HumanManager) -> void:
	var zone := a.crossing
	var total := maxf(a.crossing_from.distance_to(a.crossing_to), 0.1)
	a.awareness_timer -= delta
	if a.awareness_timer <= 0.0 and a.reaction != HumanAgent.Reaction.HURRY:
		a.awareness_timer = mgr.config.awareness_interval
		var remaining := (1.0 - a.crossing_progress) * total
		var level := zone.assess(remaining / maxf(a.walk_speed, 0.3), 0.0, mgr.traffic, mgr.player_position,
				mgr.player_velocity, mgr.config.awareness_range)
		if level == CrossingZone.Level.DANGER:
			a.set_reaction(HumanAgent.Reaction.HURRY)
			a.speed_multiplier = mgr.config.hurry_multiplier
			if a.crossing_progress < 0.35:
				# Nearer to where we started: go back.
				var back := a.crossing_from
				a.crossing_from = a.crossing_to
				a.crossing_to = back
				a.crossing_progress = 1.0 - a.crossing_progress
				a.path = PackedInt32Array([a.path[a.path_index], a.current_node])
				a.path_index = 1
			if zone.last_threat_is_player:
				mgr.report_forced_hurry(a)
	a.crossing_progress = minf(a.crossing_progress + a.walk_speed * a.speed_multiplier * delta / total, 1.0)
	var flat := a.crossing_from.lerp(a.crossing_to, a.crossing_progress)
	var edge := minf(a.crossing_progress, 1.0 - a.crossing_progress) * total
	flat.y = RoadSegment.KERB_HEIGHT if edge < 1.6 else 0.0
	a.face(a.crossing_to - a.crossing_from)
	a.global_position = flat
	a.is_moving = true
	if a.crossing_progress >= 1.0:
		a.current_node = a.path[a.path_index]
		a.path_index += 1
		a.set_reaction(HumanAgent.Reaction.NONE)
		mgr.stats_crossings_completed += 1
		a.set_state(HumanAgent.State.WALKING)


## Step back from the kerb (or freeze) when the tuk comes at them, then resume.
func _react(a: HumanAgent, delta: float, mgr: HumanManager) -> void:
	a.reaction_timer -= delta
	if a.reaction == HumanAgent.Reaction.STEP_BACK and a.react_dir != Vector3.ZERO:
		a.global_position += a.react_dir * 0.9 * delta
		a.is_moving = true
	else:
		a.is_moving = false
	if a.reaction_timer <= 0.0:
		a.set_reaction(HumanAgent.Reaction.NONE)
		var back_to := a.resume_state
		if back_to == HumanAgent.State.WAITING_TO_CROSS and a.crossing != null:
			a.crossing.waiting_count += 1
		a.set_state(back_to)
		if back_to == HumanAgent.State.WALKING and a.current_node >= 0:
			# Re-join the path from the nearest node.
			a.path_index = maxi(a.path_index, 0)
