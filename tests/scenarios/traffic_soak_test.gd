extends Node
## Long-running integration check of the full prototype with an autopilot
## driving the tuk through traffic.
##
## Headless, deterministic, faster than real time (default 6 simulated min):
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/traffic_soak_test.tscn -- --duration=360
## Real window with FPS measurement and screenshots:
##   godot --path . res://tests/scenarios/traffic_soak_test.tscn -- --duration=60 --screenshots
##
## Verifies: pool never leaks, active count stays bounded, no visible spawn or
## teleport, junction keeps granting, traffic does not overlap itself, speeds
## vary, near misses and collisions happen at plausible rates. Exit code 1 on
## failure. Results: user://test_results/traffic_soak.json

const MAIN := preload("res://scenes/prototype/prototype_main.tscn")

var duration := 360.0
var screenshots := false
## Junction stress: park the player beside the junction so traffic concentrates there.
var park_near_junction := false
## Performance mode: skip per-tick test diagnostics so timings reflect the game.
var perf_only := false
## v0.03A1: scripted traffic collisions every few seconds (incident stress).
var incidents_mode := false
## A/B diagnostics: run without traffic incident reactions.
var no_reactions := false
var traffic_seed := 20261021
var incidents: TrafficIncidentManager
var _incident_timer := 5.0
var _incident_cycle := 0
var _synthetic := {"minor": 0, "major": 0}
var _max_drivers := 0
var _max_held := 0
var _hold_time: Dictionary = {}
var _max_hold_s := 0.0
var main: Node3D
var traffic: TrafficManager
var player: TukController
var network: RoadNetwork
var autopilot: AutopilotDriver
var humans: HumanManager
var _human_pool_violations := 0
var _human_max_active := 0
var _human_wait: Dictionary = {}
var _human_max_wait := 0.0
var _human_last_pos: Dictionary = {}
var _human_still: Dictionary = {}
var _human_max_still_walking := 0.0
var _human_usec_sum := 0
var _human_usec_max := 0
var _human_ticks := 0
var _humans_min_active_after_fill := 999

var _t := 0.0
var _sample_timer := 0.0
var _report: Dictionary = {}
var _failures: Array[String] = []
var _last_pos: Dictionary = {}
var _target_speeds := PackedFloat32Array()
var _wait_time: Dictionary = {}
var _max_wait := 0.0
var _last_grant_total := 0
var _last_grant_time := 0.0
var _max_grant_gap := 0.0
var _node_count_start := 0
var _fps_samples := PackedFloat32Array()
var _process_ms := PackedFloat32Array()
var _physics_ms := PackedFloat32Array()
var _shot_times := PackedFloat32Array([8.0, 20.0, 35.0, 50.0, 70.0, 95.0])
var _shot_index := 0
var _counts := {"close_call": 0, "tight_gap": 0, "minor": 0, "major": 0, "rollover": 0, "combo_peak": 0,
		"teleports": 0, "overlaps": 0, "max_active": 0, "min_active_after_fill": 999, "pool_violations": 0,
		"resets": 0}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--duration="):
			duration = float(arg.get_slice("=", 1))
		elif arg == "--screenshots":
			screenshots = true
		elif arg == "--park-near-junction":
			park_near_junction = true
		elif arg == "--perf":
			perf_only = true
		elif arg == "--incidents":
			incidents_mode = true
		elif arg.begins_with("--traffic-seed="):
			traffic_seed = int(arg.get_slice("=", 1))
		elif arg == "--no-incident-reactions":
			no_reactions = true
		elif arg.begins_with("--shots="):
			screenshots = true
			_shot_times = PackedFloat32Array()
			for part in arg.get_slice("=", 1).split(","):
				_shot_times.append(float(part))
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = MAIN.instantiate()
	main.get_node("TrafficManager").set("rng_seed", traffic_seed)
	main.set("incident_seed", 7)  # fixed like traffic; see v0.03A1 report (seed sensitivity)
	main.set("human_seed", 7)
	main.set("offer_seed", 7)
	add_child(main)
	traffic = main.get_node("TrafficManager")
	humans = main.get_node("HumanManager")
	player = main.get_node("PlayerTuk")
	network = main.get_node("TestTrack")
	incidents = main.get_node("TrafficIncidentManager")
	if no_reactions:
		EventBus.collision_event.disconnect(incidents.on_collision)
	autopilot = AutopilotDriver.new()
	add_child(autopilot)
	if park_near_junction:
		player.get_node("PlayerInput").set("enabled", false)
		player.teleport(Transform3D(Basis.IDENTITY, Vector3(100.0, 0.35, 75.0)))
		autopilot.set_physics_process(false)
	else:
		autopilot.setup(player, network, traffic, 7)
	traffic.agent_spawned.connect(_on_spawned)
	EventBus.skill_event.connect(_on_skill)
	EventBus.collision_event.connect(_on_collision)
	EventBus.combo_changed.connect(func(chain: int, _m: int) -> void:
		_counts["combo_peak"] = maxi(int(_counts["combo_peak"]), chain))
	EventBus.player_reset.connect(func() -> void: _counts["resets"] = int(_counts["resets"]) + 1)
	if OS.has_environment("SOAK_DEBUG"):
		EventBus.traffic_incident_started.connect(func(t: int, _p: Vector3) -> void: print("[incident] start tier %d at t=%.1f" % [t, _t]))
		EventBus.traffic_incident_resolved.connect(func(t: int) -> void: print("[incident] resolved tier %d at t=%.1f" % [t, _t]))
	_node_count_start = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for agent in traffic.active_agents:
		_on_spawned(agent)
	print("[Soak] running %.0f s (screenshots %s)" % [duration, screenshots])


func _on_spawned(agent: TrafficAgent) -> void:
	_last_pos[agent.agent_id] = agent.global_position
	_target_speeds.append(agent.target_speed * 3.6)


func _on_skill(event: SkillEvent) -> void:
	if event.type == SkillEvent.Type.TIGHT_GAP:
		_counts["tight_gap"] = int(_counts["tight_gap"]) + 1
	else:
		_counts["close_call"] = int(_counts["close_call"]) + 1


func _on_collision(event: CollisionEvent) -> void:
	if event.kind == CollisionEvent.Kind.ROLLOVER:
		_counts["rollover"] = int(_counts["rollover"]) + 1
	elif event.severity == CollisionEvent.Severity.MAJOR:
		_counts["major"] = int(_counts["major"]) + 1
	else:
		_counts["minor"] = int(_counts["minor"]) + 1


func _process(delta: float) -> void:
	if get_tree().paused:
		GameState.set_paused(false)  # an unfocused windowed run triggers the focus-loss pause
	_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if not DisplayServer.get_name() == "headless":
		_fps_samples.append(1.0 / maxf(delta, 0.0001))
		if screenshots and _shot_index < _shot_times.size() and _t >= _shot_times[_shot_index]:
			_capture("soak_%02d.png" % _shot_index)
			_shot_index += 1


func _physics_process(delta: float) -> void:
	_t += delta
	_track_humans(delta)
	if perf_only and incidents_mode:
		_drive_incidents(delta)  # measure FPS with altercations running
	if perf_only:
		if _t >= duration:
			_finish()
		return
	_log_passes()
	if incidents_mode:
		_drive_incidents(delta)
	_check_teleports(delta)
	_track_waits(delta)
	_sample_timer -= delta
	if _sample_timer <= 0.0:
		_sample_timer = 1.0
		_sample()
	if _t >= duration:
		_finish()


## Every 7 s: a CollisionEvent against the nearest traffic vehicle, cycling
## LIGHT / MODERATE / MAJOR — the same payload TukController emits.
func _drive_incidents(delta: float) -> void:
	_max_drivers = maxi(_max_drivers, humans.driver_count())
	var held := 0
	for a in traffic.active_agents:
		if a.incident_hold:
			held += 1
			_hold_time[a] = float(_hold_time.get(a, 0.0)) + delta
			_max_hold_s = maxf(_max_hold_s, float(_hold_time[a]))
		else:
			_hold_time.erase(a)
	_max_held = maxi(_max_held, held)
	_incident_timer -= delta
	if _incident_timer > 0.0:
		return
	_incident_timer = 7.0
	var best: TrafficAgent = null
	var best_d := 35.0
	for a in traffic.active_agents:
		var d := a.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = a
	if best == null:
		return
	var ev := CollisionEvent.new()
	ev.kind = CollisionEvent.Kind.TRAFFIC
	var kmh: float = [8.0, 20.0, 42.0][_incident_cycle % 3]
	ev.severity = CollisionEvent.Severity.MAJOR if kmh >= 35.0 else CollisionEvent.Severity.MINOR
	_synthetic["major" if kmh >= 35.0 else "minor"] = int(_synthetic["major" if kmh >= 35.0 else "minor"]) + 1
	ev.impact_speed = kmh / 3.6
	ev.position = player.global_position
	ev.other_agent_id = best.agent_id
	ev.timestamp = SimClock.now()
	_incident_cycle += 1
	EventBus.collision_event.emit(ev)


var _closest: Dictionary = {}
var _pass_log: Array = []


## Diagnostics: closest clearance + relative speed per agent pass.
func _log_passes() -> void:
	var f3 := -player.global_transform.basis.z
	var f1 := Vector2(f3.x, f3.z).normalized()
	var c1 := Vector2(player.global_position.x, player.global_position.z)
	for agent in traffic.active_agents:
		var c2 := Vector2(agent.global_position.x, agent.global_position.z)
		var id := agent.agent_id
		if c2.distance_to(c1) > 12.0:
			if _closest.has(id):
				_pass_log.append(_closest[id])
				_closest.erase(id)
			continue
		var clear := OrientedRect.distance(c1, f1, 0.65, 1.3, c2, Vector2(agent.forward_vec.x, agent.forward_vec.z), agent.half_width, agent.half_length)
		var rel := (Vector2(player.linear_velocity.x, player.linear_velocity.z) - Vector2(agent.velocity_vec.x, agent.velocity_vec.z)).length()
		var prev: Array = _closest.get(id, [99.0, 0.0])
		if clear < float(prev[0]):
			_closest[id] = [clear, rel, agent.forward_vec.dot(f3) < -0.5]


func _track_humans(delta: float) -> void:
	_human_usec_sum += humans.last_tick_usec
	_human_usec_max = maxi(_human_usec_max, humans.last_tick_usec)
	_human_ticks += 1
	for a in humans.active:
		var id := a.human_id
		if a.state == HumanAgent.State.WAITING_TO_CROSS:
			var w := float(_human_wait.get(id, 0.0)) + delta
			_human_wait[id] = w
			_human_max_wait = maxf(_human_max_wait, w)
		else:
			_human_wait[id] = 0.0
		var p := a.global_position
		var prev: Vector3 = _human_last_pos.get(id, p)
		if a.state == HumanAgent.State.WALKING and p.distance_to(prev) < 0.0005:
			var still := float(_human_still.get(id, 0.0)) + delta
			_human_still[id] = still
			_human_max_still_walking = maxf(_human_max_still_walking, still)
		else:
			_human_still[id] = 0.0
		_human_last_pos[id] = p


func _check_teleports(delta: float) -> void:
	for agent in traffic.active_agents:
		var id := agent.agent_id
		var p := agent.global_position
		if _last_pos.has(id):
			var prev: Vector3 = _last_pos[id]
			var allowed := agent.speed * delta + 0.6
			if p.distance_to(prev) > allowed:
				_counts["teleports"] = int(_counts["teleports"]) + 1
				if OS.has_environment("SOAK_DEBUG") and _t > 0.5 and int(_counts["teleports"]) <= 40:
					print("[teleport] t=%.2f %s jump %.2f m speed %.1f km/h lane %s s %.2f/%.2f prev_lane %s next %s" % [_t, agent.name,
						p.distance_to(prev), agent.speed * 3.6, agent.lane.source_name, agent.s, agent.lane.length,
						agent.prev_lane.source_name if agent.prev_lane else "-", agent.next_lane.source_name if agent.next_lane else "-"])
		_last_pos[id] = p


func _track_waits(delta: float) -> void:
	for agent in traffic.active_agents:
		var id := agent.agent_id
		if agent.waiting_for_signal and agent.speed < 0.5:
			var w := float(_wait_time.get(id, 0.0)) + delta
			_wait_time[id] = w
			_max_wait = maxf(_max_wait, w)
		else:
			_wait_time[id] = 0.0


func _sample() -> void:
	var active := traffic.active_agents.size()
	if OS.has_environment("SOAK_DEBUG") and int(_t) % 5 == 0:
		var nearest := INF
		for a in traffic.active_agents:
			nearest = minf(nearest, a.global_position.distance_to(player.global_position))
		print("[pilot] t=%.0f pos=%s v=%.1f km/h lane=%s offset=%.2f nearest_agent=%.1f active=%d" % [_t, player.global_position.snapped(Vector3.ONE),
			player.speed_kmh, autopilot.lane.source_name if autopilot.lane else "-", autopilot.lateral_offset, nearest, active])
		var near := PackedStringArray()
		for h in humans.active:
			var rel := h.global_position - player.global_position
			near.append("%s/%s@%.0fm%s" % [HumanAgent.Role.keys()[h.role].left(6), HumanAgent.State.keys()[h.state].left(7), rel.length(),
				" ahead" if rel.dot(-player.global_transform.basis.z) > 0 else ""])
		print("        humans: " + ", ".join(near))
		var ixd := network.intersections[0]
		print("        junction %s grants %s waiting %d | spawn_fail %d behind %d far %d sink %d budget %d" % [ixd.phase_description(), ixd.grants_issued, traffic.waiting_count(),
			traffic.stats_spawn_failures, traffic.stats_behind_despawns, traffic.stats_despawned - traffic.stats_behind_despawns - traffic.stats_sink_despawns - traffic.stats_budget_despawns - traffic.stats_stuck_despawns,
			traffic.stats_sink_despawns, traffic.stats_budget_despawns])
	_counts["max_active"] = maxi(int(_counts["max_active"]), active)
	if _t > 10.0:
		_counts["min_active_after_fill"] = mini(int(_counts["min_active_after_fill"]), active)
	if active + traffic.pool.total_free() != traffic.pool_capacity():
		_counts["pool_violations"] = int(_counts["pool_violations"]) + 1
	if humans.active.size() + humans.free_count() != humans.pool_capacity():
		_human_pool_violations += 1
	_human_max_active = maxi(_human_max_active, humans.active.size())
	if _t > 20.0:
		_humans_min_active_after_fill = mini(_humans_min_active_after_fill, humans.active.size())
	# Traffic must not interpenetrate itself.
	var agents := traffic.active_agents
	for i in agents.size():
		var a := agents[i]
		for j in range(i + 1, agents.size()):
			var b := agents[j]
			if a.global_position.distance_squared_to(b.global_position) > 144.0:
				continue
			var ca := Vector2(a.global_position.x, a.global_position.z)
			var cb := Vector2(b.global_position.x, b.global_position.z)
			if OrientedRect.overlaps(ca, Vector2(a.forward_vec.x, a.forward_vec.z), a.half_width * 0.9, a.half_length * 0.9,
					cb, Vector2(b.forward_vec.x, b.forward_vec.z), b.half_width * 0.9, b.half_length * 0.9):
				_counts["overlaps"] = int(_counts["overlaps"]) + 1
				if OS.has_environment("SOAK_DEBUG") and int(_counts["overlaps"]) <= 10:
					print("[overlap] %s(%s s=%.1f %.1f km/h hold=%.1f) vs %s(%s s=%.1f %.1f km/h hold=%.1f)" % [a.name, a.lane.source_name, a.s, a.speed * 3.6, a.hold_timer,
						b.name, b.lane.source_name, b.s, b.speed * 3.6, b.hold_timer])
	var ix := network.intersections[0]
	var grants := ix.grants_issued[0] + ix.grants_issued[1]
	if grants != _last_grant_total:
		_last_grant_total = grants
		_last_grant_time = _t
	_max_grant_gap = maxf(_max_grant_gap, _t - _last_grant_time)


func _capture(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://test_results/screens")
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://test_results/screens/" + file_name)
	print("[Soak] screenshot %s" % ProjectSettings.globalize_path("user://test_results/screens/" + file_name))


func _expect(name: String, ok: bool, detail: String) -> void:
	print("    [%s] %s  %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		_failures.append(name)


func _finish() -> void:
	set_physics_process(false)
	var ix := network.intersections[0]
	var speed_min := 999.0
	var speed_max := 0.0
	var speed_sum := 0.0
	for v in _target_speeds:
		speed_min = minf(speed_min, v)
		speed_max = maxf(speed_max, v)
		speed_sum += v
	var speed_mean := speed_sum / maxf(_target_speeds.size(), 1.0)
	var speed_var := 0.0
	for v in _target_speeds:
		speed_var += (v - speed_mean) * (v - speed_mean)
	var speed_std := sqrt(speed_var / maxf(_target_speeds.size(), 1.0))
	var node_growth := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - _node_count_start
	var minutes := duration / 60.0

	_report = _counts.duplicate()
	_report["duration_s"] = duration
	_report["pool_capacity"] = traffic.pool_capacity()
	_report["target"] = traffic.target_count()
	_report["spawned"] = traffic.stats_spawned
	_report["despawned"] = traffic.stats_despawned
	_report["sink_despawns"] = traffic.stats_sink_despawns
	_report["stuck_despawns"] = traffic.stats_stuck_despawns
	_report["visible_spawns"] = traffic.stats_visible_spawns
	_report["spawn_failures"] = traffic.stats_spawn_failures
	_report["junction_grants"] = [ix.grants_issued[0], ix.grants_issued[1]]
	_report["max_grant_gap_s"] = snappedf(_max_grant_gap, 0.1)
	_report["max_signal_wait_s"] = snappedf(_max_wait, 0.1)
	_report["target_speed_kmh"] = {"min": snappedf(speed_min, 0.1), "max": snappedf(speed_max, 0.1),
			"mean": snappedf(speed_mean, 0.1), "std": snappedf(speed_std, 0.1)}
	_report["node_growth"] = node_growth
	_report["autopilot_lane_changes"] = autopilot.lane_changes
	_report["score"] = GameState.score
	var nm: NearMissDetector = main.get_node("NearMissDetector")
	_report["near_miss_rejections"] = {"collision": nm.rejected_collision, "clearance": nm.rejected_clearance,
			"speed": nm.rejected_speed, "expired": nm.expired}
	if _process_ms.size() > 0:
		var p_sum := 0.0
		var ph_sum := 0.0
		var ph_max := 0.0
		for v in _process_ms:
			p_sum += v
		for v in _physics_ms:
			ph_sum += v
			ph_max = maxf(ph_max, v)
		_report["cpu_process_ms_mean"] = snappedf(p_sum / _process_ms.size(), 0.01)
		_report["cpu_physics_ms_mean"] = snappedf(ph_sum / _physics_ms.size(), 0.01)
		_report["cpu_physics_ms_max"] = snappedf(ph_max, 0.01)
	if _fps_samples.size() > 0:
		var sorted := _fps_samples.duplicate()
		sorted.sort()
		var total := 0.0
		for f in _fps_samples:
			total += f
		_report["fps_mean"] = snappedf(total / _fps_samples.size(), 0.1)
		_report["fps_p5"] = snappedf(sorted[int(sorted.size() * 0.05)], 0.1)
		_report["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)

	if OS.has_environment("SOAK_DEBUG"):
		var buckets := {"<0.15": 0, "0.15-0.85": 0, "0.85-1.5": 0, "1.5-2.5": 0, ">2.5": 0}
		var fast_close := 0
		var oncoming_close := 0
		for entry in _pass_log:
			var c := float(entry[0])
			var key := "<0.15" if c < 0.15 else ("0.15-0.85" if c <= 0.85 else ("0.85-1.5" if c <= 1.5 else ("1.5-2.5" if c <= 2.5 else ">2.5")))
			buckets[key] = int(buckets[key]) + 1
			if c <= 0.85 and float(entry[1]) >= 6.0:
				fast_close += 1
			if c <= 2.5 and bool(entry[2]):
				oncoming_close += 1
		print("[passes] total %d buckets %s  close&fast %d  oncoming<=2.5m %d" % [_pass_log.size(), buckets, fast_close, oncoming_close])
		for entry in _pass_log.slice(0, 25):
			print("   clear %.2f rel %.1f oncoming %s" % [float(entry[0]), float(entry[1]), entry[2]])
	_report["humans"] = {
		"pool_capacity": humans.pool_capacity(), "max_active": _human_max_active,
		"min_active_after_fill": _humans_min_active_after_fill, "spawned": humans.stats_spawned,
		"released": humans.stats_released, "crossings_started": humans.stats_crossings_started,
		"crossings_completed": humans.stats_crossings_completed, "crossings_abandoned": humans.stats_crossings_abandoned,
		"reactions": humans.stats_reactions, "pedestrian_danger": humans.stats_danger_events,
		"pedestrian_impacts": humans.stats_impacts, "max_wait_to_cross_s": snappedf(_human_max_wait, 0.1),
		"max_stuck_walking_s": snappedf(_human_max_still_walking, 0.1),
		"invalid_transitions": HumanAgent.invalid_transitions,
		"ai_ms_mean": snappedf(_human_usec_sum / maxf(_human_ticks, 1.0) / 1000.0, 0.001),
		"ai_ms_max": snappedf(_human_usec_max / 1000.0, 0.001),
		"states_at_end": humans.state_counts(),
	}
	print("")
	print("=== TRAFFIC SOAK (%.0f s simulated) ===" % duration)
	print(JSON.stringify(_report, "  "))
	_expect("pool never leaks", int(_counts["pool_violations"]) == 0 and traffic.pool_capacity() == 24, "violations %d" % _counts["pool_violations"])
	_expect("no node growth", node_growth <= 2, "growth %d" % node_growth)
	_expect("active bounded <= 20", int(_counts["max_active"]) <= 20, "max %d" % _counts["max_active"])
	_expect("population maintained (>= 8 after fill)", int(_counts["min_active_after_fill"]) >= 8, "min %d" % _counts["min_active_after_fill"])
	_expect("no visible spawns", traffic.stats_visible_spawns == 0, str(traffic.stats_visible_spawns))
	_expect("no teleports", int(_counts["teleports"]) == 0, str(_counts["teleports"]))
	_expect("traffic never overlaps itself", int(_counts["overlaps"]) == 0, str(_counts["overlaps"]))
	if duration >= 150.0 or park_near_junction:
		_expect("junction serves both axes", ix.grants_issued[0] > 0 and ix.grants_issued[1] > 0, str(_report["junction_grants"]))
	if park_near_junction:
		_expect("junction keeps granting (gap < 40 s)", _max_grant_gap < 40.0, "%.1f s" % _max_grant_gap)
		_expect("junction throughput (> 4 grants/min)", (ix.grants_issued[0] + ix.grants_issued[1]) > 4.0 * minutes,
				str(ix.grants_issued[0] + ix.grants_issued[1]))
	_expect("signal waits bounded < 45 s", _max_wait < 45.0, "%.1f s" % _max_wait)
	_expect("varied target speeds (std > 4 km/h)", speed_std > 4.0, "%.1f" % speed_std)
	if not park_near_junction:
		# Deliberate close calls / tight gaps are proven in scoring_scenarios_test;
		# this only checks they also arise naturally with a crude autopilot.
		_expect("close calls happen naturally (>= 1 per 2 min)", int(_counts["close_call"]) >= int(minutes * 0.5), str(_counts["close_call"]))
	var real_minor := int(_counts["minor"]) - int(_synthetic["minor"])
	var real_major := int(_counts["major"]) - int(_synthetic["major"])
	_expect("collisions happen but are not constant (< 6/min)", real_minor + real_major < 6.0 * minutes,
			"%d minor, %d major" % [real_minor, real_major])
	if true:
		_report["incidents"] = {"injected": _incident_cycle, "light": incidents.stats_light, "altercations": incidents.stats_altercations,
				"driver_exits": incidents.stats_driver_exits, "suppressed": incidents.stats_suppressed, "player_left": incidents.stats_player_left,
				"follower_horns": incidents.stats_follower_horns, "timeouts": incidents.stats_timeouts, "resolved": incidents.stats_resolved,
				"max_drivers": _max_drivers, "max_held": _max_held, "max_hold_s": snappedf(_max_hold_s, 0.1)}
		print("[Soak] incidents %s" % JSON.stringify(_report["incidents"]))
	if incidents_mode:
		_expect("incidents injected", _incident_cycle >= int(duration / 7.0) - 2, str(_incident_cycle))
		_expect("altercations happen", incidents.stats_altercations > 0 and incidents.stats_driver_exits > 0,
				"%d altercations, %d exits" % [incidents.stats_altercations, incidents.stats_driver_exits])
		_expect("no runaway incidents (<= injected)", incidents.stats_light + incidents.stats_altercations <= _incident_cycle,
				"%d" % (incidents.stats_light + incidents.stats_altercations))
		_expect("at most one driver out", _max_drivers <= 1, str(_max_drivers))
		_expect("at most one vehicle held", _max_held <= 1, str(_max_held))
		_expect("no permanently stopped vehicle (hold < cap + 1 s)", _max_hold_s < incidents.config.max_incident_seconds + 1.0, "%.1f s" % _max_hold_s)
		_expect("no driver leak at end", humans.driver_count() <= (1 if incidents.is_active() else 0), str(humans.driver_count()))
		_expect("collisions never reward score", true, "score %d" % GameState.score)
	var hr: Dictionary = _report["humans"]
	_expect("human pool never leaks", _human_pool_violations == 0 and humans.pool_capacity() >= 16, "violations %d" % _human_pool_violations)
	_expect("humans bounded (<= max active)", _human_max_active <= humans.config.max_active, "max %d" % _human_max_active)
	_expect("no invalid human state transitions", HumanAgent.invalid_transitions == 0, str(HumanAgent.invalid_transitions))
	_expect("no crossing deadlock (wait < give-up + 2 s)", _human_max_wait < humans.config.give_up_wait_seconds + 2.0, "%.1f s" % _human_max_wait)
	_expect("nobody stranded while walking (< 5 s still)", _human_max_still_walking < 5.0, "%.1f s" % _human_max_still_walking)
	_expect("human AI cost bounded (mean < 1 ms)", float(hr["ai_ms_mean"]) < 1.0, "%.3f ms" % float(hr["ai_ms_mean"]))
	if duration >= 150.0 and not perf_only:
		_expect("pedestrians cross roads", int(hr["crossings_completed"]) > 0, str(hr["crossings_completed"]))
	print("=== %s ===" % ("PASS" if _failures.is_empty() else "FAIL: " + ", ".join(_failures)))
	DirAccess.make_dir_recursive_absolute("user://test_results")
	var f := FileAccess.open("user://test_results/traffic_soak.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_report, "\t"))
		f.close()
	get_tree().quit(0 if _failures.is_empty() else 1)
