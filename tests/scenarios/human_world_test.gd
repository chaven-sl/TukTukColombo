extends Node
## Deterministic human-world + passenger scenarios in the real prototype scene.
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/human_world_test.tscn
##
## Ambient traffic and ambient people are switched off so each step controls
## exactly who is where; passengers (offers) stay on. The tuk is driven by
## scripted inputs and, where travel itself is not under test, teleported.

const MAIN := preload("res://scenes/prototype/prototype_main.tscn")

var main: Node3D
var player: TukController
var humans: HumanManager
var net: PedestrianNetwork
var rides: RideManager
var offers: PassengerOfferManager
var scoring: ScoringSystem

var _steps: Array[Dictionary] = []
var _step := -1
var _t := 0.0
var _failures := 0
var _skill_events := 0
var _danger_events := 0
var _impact_events := 0
var _results: Array[RideResult] = []
var _ctx: Dictionary = {}
## Scripted driving: target speed (km/h) and heading line x (or NAN = no steer).
var _drive_kmh := 0.0
var _steer_line_x := NAN
var _brake := false


func _ready() -> void:
	main = MAIN.instantiate()
	var tm: TrafficManager = main.get_node("TrafficManager")
	var tcfg: TrafficConfig = tm.config.duplicate()
	tcfg.gameplay_density_target = 0
	tm.config = tcfg
	var hm: HumanManager = main.get_node("HumanManager")
	var hcfg: PedestrianConfig = hm.config.duplicate()
	hcfg.ambient_target = 0
	hm.config = hcfg
	main.set("human_seed", 11)
	main.set("offer_seed", 12)
	add_child(main)
	player = main.get_node("PlayerTuk")
	player.get_node("PlayerInput").set("enabled", false)
	humans = main.get_node("HumanManager")
	net = main.get_node("TestTrack/Pedestrians")
	rides = main.get_node("RideManager")
	offers = main.get_node("PassengerOfferManager")
	scoring = main.get_node("ScoringSystem")
	EventBus.skill_event.connect(func(_e: SkillEvent) -> void: _skill_events += 1)
	EventBus.pedestrian_danger.connect(func(_e: PedestrianEvent) -> void: _danger_events += 1)
	EventBus.pedestrian_impact.connect(func(_e: PedestrianEvent) -> void: _impact_events += 1)
	EventBus.ride_finished.connect(func(r: RideResult) -> void: _results.append(r))
	_define_steps()
	_next()


# --- helpers ---

func _check(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _teleport(pos: Vector3, heading_deg: float = 0.0, kmh: float = 0.0) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(heading_deg))
	player.teleport(Transform3D(b, pos))
	player.linear_velocity = -b.z * kmh / 3.6
	_drive_kmh = kmh
	_brake = false


func _spawn_human(node: int, role: HumanAgent.Role) -> HumanAgent:
	var a: HumanAgent = humans._acquire(role, node)
	a.behaviour = humans._pedestrian_behaviour
	a.idle_timer = 9999.0
	a.set_state(HumanAgent.State.IDLE)
	return a


func _clear_ambient() -> void:
	for a in humans.active.duplicate():
		if a.role != HumanAgent.Role.PASSENGER:
			humans.release(a)


func _drive(delta: float) -> void:
	if _brake:
		player.input.throttle = 0.0
		player.input.brake = 1.0 if player.forward_speed > 0.3 else 0.0
	else:
		var err := _drive_kmh - player.speed_kmh
		player.input.throttle = clampf(err * 0.4 + 0.3, 0.0, 1.0) if err > -1.0 and _drive_kmh > 0.0 else 0.0
		player.input.brake = 0.0
	if not is_nan(_steer_line_x):
		player.input.steer = clampf(-((player.global_position.x - _steer_line_x) * 0.8 + player.linear_velocity.x * 0.5), -1.0, 1.0)
	else:
		player.input.steer = 0.0


func _offer_for(id: StringName) -> PassengerOffer:
	for o in offers.offers:
		if o.profile.id == id:
			return o
	return null


# --- steps: {name, setup: Callable, poll: Callable(t)->bool done, timeout} ---

func _define_steps() -> void:
	var long_straight := func(z: float) -> int: return net.nearest_node(Vector3(9.2, 0.15, z))
	var zone_long: CrossingZone = net.crossings[0]  # LongStraight s=130, designated

	_steps.append({"name": "1 sidewalk path completion", "timeout": 40.0,
		"setup": func() -> void:
			_clear_ambient()
			_teleport(Vector3(-5.3, 0.4, -20.0))
			var start: int = long_straight.call(-20.0)
			var goal: int = long_straight.call(-56.0)
			var a := _spawn_human(start, HumanAgent.Role.SIDEWALK_WALKER)
			a.path = net.path_between(start, goal)
			a.path_index = 1
			a.set_state(HumanAgent.State.WALKING)
			_ctx = {"agent": a, "goal": goal},
		"poll": func(_t: float) -> bool:
			var a: HumanAgent = _ctx["agent"]
			if a.state == HumanAgent.State.IDLE and a.current_node == int(_ctx["goal"]):
				_check("walker reached its sidewalk destination", true, "%.1f km/h" % a.walk_speed_kmh())
				var kmh := a.walk_speed_kmh()
				_check("walking speed is human (3–6.5 km/h)", kmh >= 3.0 and kmh <= 6.5, "%.1f km/h" % kmh)
				return true
			return false,
		"on_timeout": func() -> void: _check("walker reached its sidewalk destination", false)})

	_steps.append({"name": "2 crossing waits while the tuk approaches, then proceeds", "timeout": 40.0,
		"setup": func() -> void:
			_clear_ambient()
			# Tuk 60 m south of the crossing (z = -130), coming north at 50 km/h on the kerb lane.
			_teleport(Vector3(-5.3, 0.4, -70.0), 0.0, 50.0)
			_steer_line_x = -5.3
			var a := _spawn_human(zone_long.node_b, HumanAgent.Role.CROSSING_PEDESTRIAN)
			a.crossing_margin = 2.0
			a.path = PackedInt32Array([zone_long.node_b, zone_long.node_a])
			a.path_index = 1
			a.current_node = zone_long.node_b
			a.crossing = zone_long
			a.crossing_from = net.node_pos[zone_long.node_b]
			a.crossing_to = net.node_pos[zone_long.node_a]
			zone_long.waiting_count += 1
			a.set_state(HumanAgent.State.WALKING)
			a.set_state(HumanAgent.State.WAITING_TO_CROSS)
			_ctx = {"agent": a, "stepped_out_early": false, "crossed": false},
		"poll": func(_t: float) -> bool:
			var a: HumanAgent = _ctx["agent"]
			var tuk_z := player.global_position.z
			if tuk_z > -128.0 and a.state == HumanAgent.State.CROSSING:
				_ctx["stepped_out_early"] = true
			if tuk_z < -150.0:
				_brake = true
			if a.state == HumanAgent.State.WALKING and a.current_node == zone_long.node_a:
				_check("pedestrian waited while the tuk approached", not bool(_ctx["stepped_out_early"]))
				_check("pedestrian crossed once safe", true)
				_check("crossing occupancy released", zone_long.occupied_count == 0, str(zone_long.occupied_count))
				return true
			return false,
		"on_timeout": func() -> void:
			var a: HumanAgent = _ctx["agent"]
			_check("pedestrian crossed once safe", false, HumanAgent.State.keys()[a.state])})

	_steps.append({"name": "3 pedestrian reacts to a fast tuk approaching", "timeout": 8.0,
		"setup": func() -> void:
			humans.config.emergency_evasion = true
			_clear_ambient()
			_steer_line_x = NAN
			var node: int = long_straight.call(-90.0)
			var a := _spawn_human(node, HumanAgent.Role.SIDEWALK_WALKER)
			_ctx = {"agent": a, "reacted": false}
			# Tuk on the sidewalk side lane heading at them (east side, southbound), 40 km/h.
			var p := net.node_pos[node]
			_teleport(Vector3(p.x - 1.4, 0.4, p.z - 25.0), 180.0, 40.0),
		"poll": func(_t: float) -> bool:
			var a: HumanAgent = _ctx["agent"]
			if a.reaction != HumanAgent.Reaction.NONE or a.state == HumanAgent.State.REACTING:
				_ctx["reacted"] = true
			if player.global_position.z > net.node_pos[a.current_node].z + 6.0 or not a.is_pooled_active:
				_check("pedestrian reacted (step back / freeze)", bool(_ctx["reacted"]))
				_brake = true
				return true
			return false,
		"on_timeout": func() -> void: _check("pedestrian reacted (step back / freeze)", bool(_ctx["reacted"]))})

	_steps.append({"name": "4 humans can never score CLOSE CALL or TIGHT GAP", "timeout": 10.0,
		"setup": func() -> void:
			# v0.03A2: forced contact/near pass to verify the v0.02 rules; evasion is tested in pavement_safety_test.
			humans.config.emergency_evasion = false
			_clear_ambient()
			# Two people standing in the carriageway either side of the tuk's line.
			var x := -5.3
			var gap := 0.65 + 0.28 + 0.6
			var left := _spawn_human(long_straight.call(-150.0), HumanAgent.Role.SIDEWALK_WALKER)
			var right := _spawn_human(long_straight.call(-152.0), HumanAgent.Role.SIDEWALK_WALKER)
			left.global_position = Vector3(x - gap, 0.0, -150.0)
			right.global_position = Vector3(x + gap, 0.0, -151.0)
			_ctx = {"skill_before": _skill_events, "score_before": GameState.score, "danger_before": _danger_events,
					"impacts_before": _impact_events}
			_teleport(Vector3(x, 0.4, -110.0), 0.0, 50.0)
			_steer_line_x = x,
		"poll": func(_t: float) -> bool:
			if player.global_position.z < -175.0:
				_check("no CLOSE CALL / TIGHT GAP from people", _skill_events == int(_ctx["skill_before"]),
						"%d skill events" % (_skill_events - int(_ctx["skill_before"])))
				_check("no score from people", GameState.score == int(_ctx["score_before"]))
				_check("PEDESTRIAN_DANGER registered instead", _danger_events > int(_ctx["danger_before"]),
						"%d danger events" % (_danger_events - int(_ctx["danger_before"])))
				_check("no contact in this pass", _impact_events == int(_ctx["impacts_before"]))
				_brake = true
				return true
			return false,
		"on_timeout": func() -> void: _check("tuk passed the people", false)})

	_steps.append({"name": "5 pedestrian impact: event, combo reset, person removed", "timeout": 8.0,
		"setup": func() -> void:
			# v0.03A2: forced contact/near pass to verify the v0.02 rules; evasion is tested in pavement_safety_test.
			humans.config.emergency_evasion = false
			_clear_ambient()
			_steer_line_x = -5.3
			scoring.combo.register_event(25)
			scoring.combo.register_event(25)
			var a := _spawn_human(long_straight.call(-200.0), HumanAgent.Role.SIDEWALK_WALKER)
			a.global_position = Vector3(-5.3, 0.0, -200.0)
			_ctx = {"agent": a, "impacts_before": _impact_events, "free_before": humans.free_count()}
			_teleport(Vector3(-5.3, 0.4, -175.0), 0.0, 30.0),
		"poll": func(_t: float) -> bool:
			if _impact_events > int(_ctx["impacts_before"]):
				var a: HumanAgent = _ctx["agent"]
				_check("PEDESTRIAN_IMPACT emitted", true)
				_check("combo reset", scoring.combo.chain == 0, str(scoring.combo.chain))
				_check("person removed and returned to pool", not a.is_pooled_active and humans.free_count() == int(_ctx["free_before"]) + 1)
				_brake = true
				return true
			return false,
		"on_timeout": func() -> void: _check("PEDESTRIAN_IMPACT emitted", false)})

	for pid in [&"rushed", &"careful", &"thrill_seeker"]:
		_add_ride_steps(pid)

	_steps.append({"name": "9 pickup refuses a fast drive-by", "timeout": 6.0,
		"setup": func() -> void:
			var o := _offer_for(&"rushed")
			_ctx = {"offer": o, "boarded": false, "accepted": false}
			var p := o.pickup.global_position
			_teleport(Vector3(-5.3, 0.4, p.z + 14.0), 0.0, 30.0)
			_steer_line_x = -5.3,
		"poll": func(_t: float) -> bool:
			var o: PassengerOffer = _ctx["offer"]
			if not bool(_ctx["accepted"]) and o.state == PassengerOffer.State.AVAILABLE and rides.nearby_offer == o:
				_ctx["accepted"] = rides.request_accept()
			if rides.state == RideManager.RideState.BOARDING:
				_ctx["boarded"] = true
			if player.global_position.z < o.pickup.global_position.z - 14.0:
				_check("accepted while driving past", bool(_ctx["accepted"]))
				_check("no boarding at 30 km/h", not bool(_ctx["boarded"]))
				_brake = true
				return true
			return false,
		"on_timeout": func() -> void: _check("drive-by completed", false)})

	_steps.append({"name": "10 pedestrian impact fails an active ride", "timeout": 30.0,
		"setup": func() -> void:
			# v0.03A2: forced contact/near pass to verify the v0.02 rules; evasion is tested in pavement_safety_test.
			humans.config.emergency_evasion = false
			var o := _offer_for(&"rushed")
			var p := o.pickup.global_position
			_teleport(Vector3(-5.3, 0.4, p.z + 1.0))
			_steer_line_x = NAN
			_ctx = {"offer": o, "phase": 0, "results_before": _results.size()},
		"poll": func(_t: float) -> bool:
			var o: PassengerOffer = _ctx["offer"]
			match int(_ctx["phase"]):
				0:
					if rides.state == RideManager.RideState.ACTIVE:
						# Already at 30 km/h, 4 m from someone in the lane: no time to dodge.
						_teleport(Vector3(-5.3, 0.4, -90.0), 0.0, 30.0)
						var a := _spawn_human(long_straight.call(-110.0), HumanAgent.Role.SIDEWALK_WALKER)
						a.global_position = Vector3(-5.3, 0.0, -96.5)
						_ctx["victim"] = a
						_drive_kmh = 30.0
						_steer_line_x = -5.3
						_ctx["phase"] = 1
				1:
					if OS.has_environment("HW_DEBUG") and Engine.get_physics_frames() % 30 == 0:
						var h: HumanAgent = _ctx.get("victim")
						print("    tuk %s %.1f km/h | human %s %s active %s" % [player.global_position.snapped(Vector3(0.1,0.1,0.1)), player.speed_kmh,
							h.global_position.snapped(Vector3(0.1,0.1,0.1)), HumanAgent.State.keys()[h.state], h.is_pooled_active])
					if _results.size() > int(_ctx["results_before"]):
						var r: RideResult = _results[_results.size() - 1]
						_check("ride FAILED", r.outcome == RideResult.Outcome.FAILED)
						_check("fail reason PEDESTRIAN_IMPACT", r.fail_reason == RideResult.FailReason.PEDESTRIAN_IMPACT)
						_check("no fare paid", r.final_fare == 0)
						_check("satisfaction collapses", r.satisfaction.final_score <= 5.0, "%.1f" % r.satisfaction.final_score)
						_brake = true
						_ctx["phase"] = 2
				2:
					if rides.state == RideManager.RideState.NO_RIDE:
						_check("passenger exits and ride resets", o.state == PassengerOffer.State.FINISHED or o.state == PassengerOffer.State.AVAILABLE)
						return true
			return false,
		"on_timeout": func() -> void: _check("ride failed on pedestrian impact", false, RideManager.RideState.keys()[rides.state])})


func _add_ride_steps(pid: StringName) -> void:
	_steps.append({"name": "ride loop: %s" % pid, "timeout": 60.0,
		"setup": func() -> void:
			_clear_ambient()
			var o := _offer_for(pid)
			_ctx = {"offer": o, "phase": 0, "results_before": _results.size(), "seen": {}}
			if o == null or o.state != PassengerOffer.State.AVAILABLE:
				return
			var pickup := o.pickup.global_position
			var out := net.node_out[o.pickup.node_id]
			var heading := rad_to_deg(atan2(-out.z, out.x))
			# Stop on the road 4 m from the passenger, parallel to the kerb.
			var road_dir := out.cross(Vector3.UP)
			player.teleport(Transform3D(MathUtil.basis_from_forward(road_dir), pickup - out * 4.0 + Vector3.UP * 0.3))
			_drive_kmh = 0.0
			_steer_line_x = NAN
			_brake = true,
		"poll": func(_t: float) -> bool:
			var o: PassengerOffer = _ctx["offer"]
			if o == null:
				_check("offer exists for %s" % pid, false)
				return true
			var seen: Dictionary = _ctx["seen"]
			seen[rides.state] = true
			if o.passenger != null:
				seen["h_%d" % o.passenger.state] = true
			match int(_ctx["phase"]):
				0:
					if rides.state == RideManager.RideState.NO_RIDE and rides.nearby_offer == o:
						_check("offer card available (%s, %s, %.0f m)" % [pid, o.destination.spot_id, o.route_m], o.route_m > 100.0)
						_check("accept", rides.request_accept())
						_check("offer marked accepted", o.state == PassengerOffer.State.ACCEPTED)
						_ctx["phase"] = 1
				1:
					if rides.state == RideManager.RideState.ACTIVE:
						_check("boarded: approached → boarding → riding", seen.has("h_%d" % HumanAgent.State.APPROACHING_TUK)
								and seen.has("h_%d" % HumanAgent.State.BOARDING) and o.passenger.state == HumanAgent.State.RIDING)
						# v0.03B: the passenger stays visible, seated on SeatMarker.
						_check("passenger visible and attached to SeatMarker", o.passenger.visible and o.passenger.presentation_attached_to != null
								and o.passenger.presentation_attached_to.name == "SeatMarker" and o.passenger.visual.get_parent() == o.passenger.presentation_attached_to)
						_check("passenger rig SEATED", o.passenger.rig != null and o.passenger.rig.mode == CharacterRig.Mode.SEATED)
						_check("ride ACTIVE with telemetry", rides.telemetry != null)
						# Drive a little to accumulate telemetry, then hop to the destination.
						_brake = false
						_drive_kmh = 25.0
						_ctx["phase"] = 2
						_ctx["t0"] = _t
				2:
					if _t - float(_ctx["t0"]) > 4.0:
						_check("telemetry aggregates distance", rides.telemetry.distance_m > 10.0, "%.0f m" % rides.telemetry.distance_m)
						var dest := o.destination.global_position
						var out := net.node_out[o.destination.node_id]
						var road_dir := out.cross(Vector3.UP)
						player.teleport(Transform3D(MathUtil.basis_from_forward(road_dir), dest - out * 4.0 + Vector3.UP * 0.3))
						_drive_kmh = 0.0
						_brake = true
						_ctx["phase"] = 3
				3:
					if _results.size() > int(_ctx["results_before"]):
						var r: RideResult = _results[_results.size() - 1]
						_check("ride COMPLETED", r.outcome == RideResult.Outcome.COMPLETED)
						_check("fare computed (base %d %+d = %d)" % [r.base_fare, r.adjustment, r.final_fare], r.base_fare > 0 and r.final_fare == r.base_fare + r.adjustment)
						_check("passenger EXITING and visible", o.passenger != null and o.passenger.state == HumanAgent.State.EXITING and o.passenger.visible)
						_check("passenger detached from SeatMarker on exit", o.passenger != null and o.passenger.presentation_attached_to == null and o.passenger.visual.get_parent() == o.passenger)
						_ctx["phase"] = 4
				4:
					if rides.state == RideManager.RideState.NO_RIDE:
						_check("passenger returned to pool, ride idle", o.passenger == null and o.state == PassengerOffer.State.FINISHED)
						_ctx["phase"] = 5
						_ctx["t1"] = _t
				5:
					if o.state == PassengerOffer.State.AVAILABLE:
						_check("offer respawned with a new passenger", o.passenger != null and o.passenger.state == HumanAgent.State.WAITING_FOR_PICKUP)
						return true
			return false,
		"on_timeout": func() -> void:
			_check("ride loop %s finished" % pid, false, "ride %s phase %d" % [RideManager.RideState.keys()[rides.state], int(_ctx.get("phase", -1))])})


func _next() -> void:
	_step += 1
	_drive_kmh = 0.0
	_steer_line_x = NAN
	_brake = false
	if _step >= _steps.size():
		_finish()
		return
	_t = 0.0
	print("STEP %s" % _steps[_step]["name"])
	(_steps[_step]["setup"] as Callable).call()


func _physics_process(delta: float) -> void:
	if _step < 0 or _step >= _steps.size():
		return
	_t += delta
	_drive(delta)
	var step: Dictionary = _steps[_step]
	if (step["poll"] as Callable).call(_t):
		_next()
	elif _t > float(step["timeout"]):
		(step["on_timeout"] as Callable).call()
		_next()


func _finish() -> void:
	_check("no invalid human state transitions", HumanAgent.invalid_transitions == 0, str(HumanAgent.invalid_transitions))
	_check("no invalid ride transitions", rides.invalid_transitions == 0, str(rides.invalid_transitions))
	_check("human pool intact", humans.free_count() + humans.active.size() == humans.pool_capacity())
	print("=== HUMAN WORLD: %s (%d failed) ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
