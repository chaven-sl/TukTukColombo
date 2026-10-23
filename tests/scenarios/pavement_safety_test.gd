extends Node
## v0.03A2 pedestrian emergency evasion in the real prototype scene.
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/pavement_safety_test.tscn
##
## The east pavement of the long straight (x 7.15–10.3, 0.15 m high) is the
## stage. People are placed by hand; the tuk is launched with an initial
## velocity and keeps its throttle. All speeds in output are km/h.

const MAIN := preload("res://scenes/prototype/prototype_main.tscn")

var main: Node3D
var player: TukController
var humans: HumanManager
var net: PedestrianNetwork
var road: RoadNetwork
var rides: RideManager
var offers: PassengerOfferManager
var traffic: TrafficManager
var incidents: TrafficIncidentManager
var _failures := 0
var _skill := 0
var _impacts := 0
var _danger := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = MAIN.instantiate()
	var tm: TrafficManager = main.get_node("TrafficManager")
	var tcfg: TrafficConfig = tm.config.duplicate()
	tcfg.gameplay_density_target = 0
	tm.config = tcfg
	var hm: HumanManager = main.get_node("HumanManager")
	var hcfg: PedestrianConfig = hm.config.duplicate()
	hcfg.ambient_target = 0
	hm.config = hcfg
	main.set("human_seed", 51)
	main.set("offer_seed", 52)
	main.set("incident_seed", 53)
	add_child(main)
	player = main.get_node("PlayerTuk")
	player.get_node("PlayerInput").set("enabled", false)
	humans = hm
	traffic = tm
	net = main.get_node("TestTrack/Pedestrians")
	road = main.get_node("TestTrack")
	rides = main.get_node("RideManager")
	offers = main.get_node("PassengerOfferManager")
	incidents = main.get_node("TrafficIncidentManager")
	EventBus.skill_event.connect(func(_e: SkillEvent) -> void: _skill += 1)
	EventBus.pedestrian_impact.connect(func(_e: PedestrianEvent) -> void: _impacts += 1)
	EventBus.pedestrian_danger.connect(func(_e: PedestrianEvent) -> void: _danger += 1)
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _person(at: Vector3) -> HumanAgent:
	var a: HumanAgent = humans._acquire(HumanAgent.Role.SIDEWALK_WALKER, net.nearest_node(at))
	a.behaviour = humans.get("_pedestrian_behaviour")
	a.global_position = at
	a.idle_timer = 30.0  # standing still (chatting / waiting)
	a.set_state(HumanAgent.State.IDLE)
	return a


func _launch(start: Vector3, dir: Vector3, kmh: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	player.teleport(Transform3D(MathUtil.basis_from_forward(d), start))
	player.linear_velocity = d * kmh / 3.6


## Drives for `frames` holding roughly `kmh`, recording per-agent evasion
## (first EVADING frame) and minimum distance to the tuk.
func _drive(kmh: float, frames: int, agents: Array, log: Dictionary) -> void:
	for f in frames:
		player.input.handbrake = false
		player.input.brake = 0.0
		player.input.steer = 0.0
		player.input.throttle = 0.6 if player.speed_kmh < kmh else 0.0
		await get_tree().physics_frame
		if OS.has_environment("PS_DEBUG") and f % 15 == 0:
			print("    f%d tuk %s %.1f km/h in(t%.1f b%.1f hb%s)" % [f, player.global_position.snapped(Vector3(0.1, 0.01, 0.1)), player.speed_kmh, player.input.throttle, player.input.brake, player.input.handbrake])
		for a: HumanAgent in agents:
			if not a.is_pooled_active:
				continue
			var e: Dictionary = log.get(a, {"evade_frame": -1, "min_d": INF, "min_frame": -1, "dive": false, "states": {}})
			var d := Vector2(a.global_position.x - player.global_position.x, a.global_position.z - player.global_position.z).length()
			if d < float(e["min_d"]):
				e["min_d"] = d
				e["min_frame"] = f
			if a.state == HumanAgent.State.EVADING and int(e["evade_frame"]) < 0:
				e["evade_frame"] = f
				e["dive"] = a.evade_dive
			(e["states"] as Dictionary)[a.state] = true
			log[a] = e


func _clear_people() -> void:
	for i in range(humans.active.size() - 1, -1, -1):
		var a := humans.active[i]
		if a.role != HumanAgent.Role.PASSENGER:
			humans.release(a)


func _run() -> void:
	await _frames(10)
	var invalid0 := HumanAgent.invalid_transitions
	var score0 := GameState.score
	await _pavement_swerve()
	await _standing_lateral()
	await _waiting_passenger()
	await _arguing_driver()
	print("=== Rules ===")
	_check("people never award CLOSE CALL / TIGHT GAP", _skill == 0, "%d skill events" % _skill)
	_check("no score from pedestrian danger", GameState.score <= score0)
	_check("no invalid human state transitions", HumanAgent.invalid_transitions == invalid0, str(HumanAgent.invalid_transitions - invalid0))
	_check("human pool consistent", humans.free_count() + humans.active.size() == humans.pool_capacity())
	print("")
	print("=== PAVEMENT SAFETY: %s — %d failures ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _pavement_swerve() -> void:
	print("=== Pavement swerve: 35 km/h tuk mounts the pavement, three people ahead ===")
	_clear_people()
	var people := [_person(Vector3(8.7, 0.15, -156.0)), _person(Vector3(9.3, 0.15, -160.0)), _person(Vector3(8.3, 0.15, -164.0))]
	var log := {}
	var impacts0 := _impacts
	var danger0 := _danger
	_launch(Vector3(5.0, 0.4, -138.0), Vector3(0.22, 0, -1), 35.0)
	await _drive(35.0, 150, people, log)
	var early := 0
	var lead_s := PackedStringArray()
	for a: HumanAgent in people:
		var e: Dictionary = log.get(a, {})
		if e.is_empty():
			continue
		var ef := int(e["evade_frame"])
		if ef >= 0 and ef < int(e["min_frame"]):
			early += 1
			lead_s.append("%.2f s%s" % [(int(e["min_frame"]) - ef) / 60.0, " dive" if bool(e["dive"]) else ""])
	_check("threat recognised before the closest approach (all three)", early == 3, "%d/3 evaded early: %s" % [early, ", ".join(lead_s)])
	_check("urgent dives at 35 km/h", humans.stats_dives >= 1, "%d dives, %d evades" % [humans.stats_dives, humans.stats_evasions])
	_check("nobody hit (chaotic but fair)", _impacts == impacts0, "%d impacts" % (_impacts - impacts0))
	_check("pavement danger still registered (negative only)", _danger >= danger0)
	var on_road := 0
	for a: HumanAgent in people:
		if a.is_pooled_active and WorldSurface.is_on_carriageway(road, a.global_position, 0.0):
			on_road += 1
	_check("nobody escaped into a traffic lane", on_road == 0)
	player.input.throttle = 0.0
	player.input.handbrake = true
	await _frames(60 * 4)
	var settled := 0
	for a: HumanAgent in people:
		if a.is_pooled_active and a.state != HumanAgent.State.EVADING and a.current_node >= 0:
			settled += 1
	_check("everyone back to normal on the network", settled == 3)


func _standing_lateral() -> void:
	print("=== 15 km/h: clear lateral evade (not a dive) ===")
	_clear_people()
	var dives0 := humans.stats_dives
	var a := _person(Vector3(8.7, 0.15, -200.0))
	var start := a.global_position
	var log := {}
	_launch(Vector3(8.7, 0.6, -178.0), Vector3(0, 0, -1), 15.0)
	await _drive(15.0, 420, [a], log)  # 22 m at 15 km/h ≈ 5.3 s
	var e: Dictionary = log.get(a, {})
	var lateral := absf(a.global_position.x - start.x)
	_check("standing person evades before contact", not e.is_empty() and int(e["evade_frame"]) >= 0 and int(e["evade_frame"]) < int(e["min_frame"]))
	_check("moved sideways out of the path", lateral > 1.3 or float(e.get("min_d", 0.0)) > 1.6, "lateral %.1f m, closest %.1f m" % [lateral, float(e.get("min_d", 0.0))])
	_check("EVADE, not DIVE, at 15 km/h", humans.stats_dives == dives0)
	player.input.handbrake = true
	await _frames(60 * 3)


func _waiting_passenger() -> void:
	print("=== Waiting hire passenger reacts ===")
	_clear_people()
	var o: PassengerOffer = null
	for x in offers.offers:
		if x.state == PassengerOffer.State.AVAILABLE and x.passenger != null:
			o = x
			break
	if o == null:
		_check("waiting passenger available", false)
		return
	var p := o.passenger
	var home := net.node_pos[p.current_node]
	var lane_p := road.find_reset_transform(p.global_position).origin
	var dir := Vector3(p.global_position.x - lane_p.x, 0.0, p.global_position.z - lane_p.z)
	var side := dir.cross(Vector3.UP).normalized()
	var log := {}
	var impacts0 := _impacts
	_launch(p.global_position - side * 18.0 + Vector3.UP * 0.5, side, 30.0)
	await _drive(30.0, 110, [p], log)
	var e: Dictionary = log.get(p, {})
	_check("passenger jumps aside (not frozen under the tuk)", not e.is_empty() and int(e["evade_frame"]) >= 0, "closest %.1f m" % float(e.get("min_d", -1.0)))
	_check("passenger not hit", _impacts == impacts0)
	_check("ride not accepted by driving through them", rides.state == RideManager.RideState.NO_RIDE)
	player.input.throttle = 0.0
	player.input.handbrake = true
	await _frames(60 * 8)
	_check("passenger returns to the pickup and waits again", p.state == HumanAgent.State.WAITING_FOR_PICKUP and p.global_position.distance_to(home) < 1.0,
			"%s, %.1f m from spot" % [HumanAgent.State.keys()[p.state], p.global_position.distance_to(home)])


func _arguing_driver() -> void:
	print("=== Arguing traffic driver reacts ===")
	_clear_people()
	var cfg: IncidentConfig = incidents.config.duplicate()
	cfg.major_min_exit_chance = 1.0
	incidents.config = cfg
	# Tuk parked in the kerb lane; a car just ahead of it.
	player.teleport(Transform3D(MathUtil.basis_from_forward(Vector3.FORWARD), Vector3(-1.9, 0.4, -100.0)))
	await _frames(20)
	var lane: Lane = null
	for l in road.lanes:
		if not l.is_connector and l.sample_tangent(l.closest_s(player.global_position)).dot(Vector3.FORWARD) > 0.9 \
				and l.sample_position(l.closest_s(player.global_position)).distance_to(player.global_position) < 2.0:
			lane = l
	traffic._activate(traffic.vehicle_classes[0], lane, lane.closest_s(player.global_position) + 7.0)
	var car: TrafficAgent = traffic.active_agents[traffic.active_agents.size() - 1]
	car.speed = 0.0
	var ev := CollisionEvent.new()
	ev.kind = CollisionEvent.Kind.TRAFFIC
	ev.severity = CollisionEvent.Severity.MAJOR
	ev.impact_speed = 40.0 / 3.6
	ev.other_agent_id = car.agent_id
	EventBus.collision_event.emit(ev)
	var t := 0
	while incidents.phase != TrafficIncidentManager.Phase.ARGUING and t < 600:
		player.input.handbrake = true
		await _frames(1)
		t += 1
	var driver := incidents.driver
	_check("driver out and arguing", driver != null and incidents.phase == TrafficIncidentManager.Phase.ARGUING)
	if driver == null:
		return
	# Back off 14 m, then accelerate straight at them.
	var to := driver.global_position - player.global_position
	to.y = 0.0
	var log := {}
	var impacts0 := _impacts
	_launch(driver.global_position - to.normalized() * 14.0 + Vector3.UP * 0.4, to, 20.0)
	await _drive(20.0, 240, [driver], log)  # 14 m at 20 km/h ≈ 2.5 s
	var e: Dictionary = log.get(driver, {})
	_check("arguing driver moves out of the way", not e.is_empty() and int(e["evade_frame"]) >= 0, "closest %.1f m" % float(e.get("min_d", -1.0)))
	_check("driver not hit", _impacts == impacts0)
	player.input.throttle = 0.0
	player.input.handbrake = true
	t = 0
	while incidents.is_active() and t < 1500:
		await _frames(1)
		t += 1
	_check("incident resolves; driver back in the vehicle (pool)", not incidents.is_active() and humans.driver_count() == 0)
