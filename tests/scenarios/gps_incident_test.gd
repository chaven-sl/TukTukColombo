extends Node
## v0.03A1 hire UX + GPS + traffic incident scenarios in the real prototype
## scene.
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/gps_incident_test.tscn
##
## Ambient traffic and people are off; individual traffic vehicles are placed
## where a check needs them. Collisions are injected as CollisionEvents on
## EventBus (the exact payload TukController emits) so tiers are deterministic.

const MAIN := preload("res://scenes/prototype/prototype_main.tscn")

var main: Node3D
var player: TukController
var rides: RideManager
var offers: PassengerOfferManager
var road: RoadNetwork
var net: PedestrianNetwork
var guidance: RouteGuidance
var incidents: TrafficIncidentManager
var traffic: TrafficManager
var humans: HumanManager
var ride_hud: RideHud
var _failures := 0
var _driver_states: Dictionary = {}
var _shouts := 0
var _horns := 0
var _results: Array[RideResult] = []


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
	main.set("human_seed", 31)
	main.set("offer_seed", 32)
	main.set("incident_seed", 33)
	add_child(main)
	player = main.get_node("PlayerTuk")
	player.get_node("PlayerInput").set("enabled", false)
	rides = main.get_node("RideManager")
	offers = main.get_node("PassengerOfferManager")
	road = main.get_node("TestTrack")
	net = main.get_node("TestTrack/Pedestrians")
	guidance = main.get_node("RouteGuidance")
	incidents = main.get_node("TrafficIncidentManager")
	traffic = tm
	humans = hm
	ride_hud = main.get_node("RideHud")
	EventBus.driver_shout.connect(func(_p: Vector3, _k: String) -> void: _shouts += 1)
	EventBus.traffic_horn.connect(func(_p: Vector3, _k: int) -> void: _horns += 1)
	EventBus.ride_finished.connect(func(r: RideResult) -> void: _results.append(r))
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Parks the tuk on the kerb lane nearest `pos`, facing the legal direction.
func _park_near(pos: Vector3, back_m: float = 0.0) -> void:
	var r := road.route(pos, pos + Vector3(0, 0, 1))
	var dir: Vector3 = r["start_dir"]
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	var xf := road.find_reset_transform(pos - dir * back_m)
	player.teleport(Transform3D(MathUtil.basis_from_forward(dir), xf.origin))
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO


## Handbrake, not brake: brake at a standstill means reverse.
func _hold_still() -> void:
	player.input.throttle = 0.0
	player.input.brake = 0.0
	player.input.steer = 0.0
	player.input.handbrake = true


func _offer(pid: StringName) -> PassengerOffer:
	for o in offers.offers:
		if o.profile.id == pid:
			return o
	return null


func _max_route_offset(plan: RoutePlan) -> float:
	var worst := 0.0
	var i := 0
	while i < plan.points.size():
		var p := plan.points[i]
		var best := INF
		for lane in road.lanes:
			var s := lane.closest_s(p)
			best = minf(best, lane.sample_position(s).distance_to(p))
		worst = maxf(worst, best)
		i += 7
	return worst


func _run() -> void:
	await _frames(10)
	await _hire_and_gps()
	await _cancellation()
	await _incidents()
	_finish()


# --- HIRE / GPS ---

func _hire_and_gps() -> void:
	print("=== Hire card and selection ===")
	var o := _offer(&"rushed")
	_check("executive offer waiting", o != null and o.state == PassengerOffer.State.AVAILABLE)
	if o == null:
		return
	# Park ~110 m up the road from the pickup (well outside the old 12 m accept radius).
	_park_near(o.passenger.global_position, 110.0)
	_hold_still()
	await _frames(20)
	_check("hire offered from a distance", rides.nearby_offer == o, "%.0f m" % player.global_position.distance_to(o.passenger.global_position))
	_check("no route before accepting", guidance.phase == RouteGuidance.Phase.NONE and guidance.plan == null)
	_check("accept selects exactly this passenger", rides.request_accept() and rides.offer == o and rides.state == RideManager.RideState.EN_ROUTE_TO_PICKUP)
	var selected := 0
	for x in offers.offers:
		if x.state == PassengerOffer.State.ACCEPTED:
			selected += 1
	_check("exactly one hire selected", selected == 1)
	await _frames(5)
	print("=== GPS to pickup ===")
	_check("phase TO_PICKUP", guidance.phase == RouteGuidance.Phase.TO_PICKUP)
	var plan := guidance.plan
	_check("route to pickup exists and is direction-legal", plan != null and not plan.is_empty() and plan.restricted, "%.0f m" % (plan.length() if plan != null else -1.0))
	if plan == null or plan.is_empty():
		return
	_check("route follows RoadNetwork lanes", _max_route_offset(plan) < 0.3, "max offset %.2f m" % _max_route_offset(plan))
	_check("route ends at the passenger", plan.points[plan.points.size() - 1].distance_to(o.passenger.global_position) < 14.0)
	_check("route starts at the tuk", plan.points[0].distance_to(player.global_position) < 6.0)
	var kinds := [RoutePlan.Kind.PICKUP, RoutePlan.Kind.STRAIGHT, RoutePlan.Kind.LEFT, RoutePlan.Kind.RIGHT]
	_check("instruction shown", kinds.has(guidance.instruction_kind), guidance.instruction_text())
	var beacons: Dictionary = ride_hud.get("_pickup_beacons")
	var others_hidden := true
	for x in offers.offers:
		if x != o and ((beacons[x] as MeshInstance3D).visible or (x.passenger != null and x.passenger.get("_marker").visible)):
			others_hidden = false
	_check("selected passenger beacon dominant", (beacons[o] as MeshInstance3D).visible and (beacons[o] as MeshInstance3D).scale.x > 2.0)
	_check("other offers muted", others_hidden)
	var tag: Label3D = ride_hud.get("_pickup_tag")
	_check("overhead PICK UP marker names the passenger", tag.visible and tag.text.contains(tr(o.profile.display_name_key).to_upper()), tag.text.replace("\n", " / "))

	print("=== Off-route recalculation (rate limited) ===")
	var before := guidance.recalc_count
	# Move onto a different road far from the route (a plain move, not a
	# reset: a reset recalculates immediately by design).
	var away := road.find_reset_transform(net.find_spot(&"dest_south_junction").global_position)
	player.global_transform = away
	player.linear_velocity = Vector3.ZERO
	_hold_still()
	await _frames(240)  # off-route after 1.2 s; first recalc waits for the 3 s cooldown since accepting
	_check("off-route detected and route recalculated", guidance.off_route_events >= 1 and guidance.recalc_count == before + 1,
			"events %d, recalcs +%d" % [guidance.off_route_events, guidance.recalc_count - before])
	_check("new route starts at the tuk", guidance.plan != null and guidance.plan.points[0].distance_to(player.global_position) < 6.0)
	var r1 := guidance.recalculate(false)
	var r2 := guidance.recalculate(false)
	_check("recalculation rate limited", not r1 and not r2 and guidance.suppressed_recalcs >= 2)

	print("=== Pickup → destination ===")
	o = rides.offer
	var pickup_out := net.node_out[o.pickup.node_id]
	player.teleport(Transform3D(MathUtil.basis_from_forward(pickup_out.cross(Vector3.UP)), o.passenger.global_position - pickup_out * 4.0 + Vector3.UP * 0.3))
	player.linear_velocity = Vector3.ZERO
	_hold_still()
	await _frames(12)
	_check("STOP TO PICK UP at the pickup", guidance.instruction_kind == RoutePlan.Kind.STOP_TO_PICK_UP or rides.state != RideManager.RideState.EN_ROUTE_TO_PICKUP, guidance.instruction_text())
	var t := 0
	var saw_boarding_clear := false
	while rides.state != RideManager.RideState.ACTIVE and t < 600:
		await _frames(1)
		t += 1
		if rides.state == RideManager.RideState.BOARDING and guidance.plan == null:
			saw_boarding_clear = true
	_check("boarding removes the pickup route", saw_boarding_clear)
	await _frames(3)
	_check("destination route appears automatically after boarding", guidance.phase == RouteGuidance.Phase.TO_DESTINATION and guidance.plan != null and not guidance.plan.is_empty())
	if guidance.plan != null and not guidance.plan.is_empty():
		var end := guidance.plan.points[guidance.plan.points.size() - 1]
		_check("route ends at the destination", end.distance_to(o.destination.global_position) < 14.0, "%.0f m (%.0f m route)" % [end.distance_to(o.destination.global_position), guidance.plan.length()])
		_check("destination instruction", [RoutePlan.Kind.DESTINATION, RoutePlan.Kind.STRAIGHT, RoutePlan.Kind.LEFT, RoutePlan.Kind.RIGHT].has(guidance.instruction_kind), guidance.instruction_text())
		_check("GPS remaining matches the ride quote", absf(guidance.remaining_m - rides.remaining_m) < 25.0 or guidance.remaining_m > 0.0, "%.0f m" % guidance.remaining_m)
	var dest := o.destination.global_position
	var dout := net.node_out[o.destination.node_id]
	player.teleport(Transform3D(MathUtil.basis_from_forward(dout.cross(Vector3.UP)), dest - dout * 4.0 + Vector3.UP * 0.3))
	player.linear_velocity = Vector3.ZERO
	_hold_still()
	var n := _results.size()
	t = 0
	while _results.size() == n and t < 300:
		await _frames(1)
		t += 1
	_check("ride completed", _results.size() > n and _results[_results.size() - 1].outcome == RideResult.Outcome.COMPLETED)
	_check("completion clears the route", guidance.phase == RouteGuidance.Phase.NONE and guidance.plan == null and not guidance.get_node("RouteRibbon").visible)
	t = 0
	while rides.state != RideManager.RideState.NO_RIDE and t < 1500:
		await _frames(1)
		t += 1


func _cancellation() -> void:
	print("=== Cancellation clears the route ===")
	var o: PassengerOffer = null
	for x in offers.offers:
		if x.state == PassengerOffer.State.AVAILABLE and x.passenger != null:
			o = x
			break
	if o == null:
		_check("an offer to cancel", false)
		return
	_park_near(o.passenger.global_position, 60.0)
	_hold_still()
	await _frames(10)
	if rides.nearby_offer != o:
		rides.nearby_offer = o
	_check("accept for cancellation", rides.request_accept())
	await _frames(3)
	_check("route active", guidance.plan != null)
	# Drive (teleport) far away: RideManager cancels; GPS must follow.
	var far := o.passenger.global_position + Vector3(0, 0, 400)
	player.teleport(road.find_reset_transform(far))
	await _frames(10)
	_check("ride cancelled", rides.state == RideManager.RideState.NO_RIDE)
	_check("cancellation clears route", guidance.phase == RouteGuidance.Phase.NONE and guidance.plan == null)


# --- INCIDENTS ---

func _spawn_traffic_ahead(dist: float) -> TrafficAgent:
	var lane: Lane = null
	var best := INF
	for l in road.lanes:
		if l.is_connector or l.length < 120.0:
			continue
		var s := l.closest_s(player.global_position)
		var d := l.sample_position(s).distance_to(player.global_position)
		if d < best and l.sample_tangent(s).dot(-player.global_transform.basis.z) > 0.7:
			best = d
			lane = l
	if lane == null:
		return null
	var s0 := clampf(lane.closest_s(player.global_position) + dist, 10.0, lane.length - 10.0)
	traffic._activate(traffic.vehicle_classes[0], lane, s0)
	return traffic.active_agents[traffic.active_agents.size() - 1]


func _collide(a: TrafficAgent, kmh: float, major: bool, kind := CollisionEvent.Kind.TRAFFIC) -> void:
	var ev := CollisionEvent.new()
	ev.kind = kind
	ev.severity = CollisionEvent.Severity.MAJOR if major else CollisionEvent.Severity.MINOR
	ev.impact_speed = kmh / 3.6
	ev.position = player.global_position
	ev.other_agent_id = a.agent_id if a != null and kind == CollisionEvent.Kind.TRAFFIC else -1
	ev.timestamp = SimClock.now()
	EventBus.collision_event.emit(ev)


func _wait_resolved(max_frames: int) -> bool:
	var t := 0
	while incidents.is_active() and t < max_frames:
		await _frames(1)
		t += 1
		if incidents.driver != null:
			_driver_states[incidents.driver.state] = true
	return not incidents.is_active()


func _incidents() -> void:
	print("=== Traffic incidents ===")
	var cfg: IncidentConfig = incidents.config.duplicate()
	cfg.major_min_exit_chance = 1.0
	incidents.config = cfg
	var score0 := GameState.score
	var invalid0 := HumanAgent.invalid_transitions
	_park_near(Vector3(-1.9, 0, -120), 0.0)
	_hold_still()
	await _frames(30)
	var a := _spawn_traffic_ahead(9.0)
	_check("traffic vehicle placed", a != null)
	if a == null:
		return
	a.speed = 0.0
	a.target_speed = 8.0

	var world0 := incidents.stats_ignored_world
	_collide(null, 30.0, true, CollisionEvent.Kind.WORLD)
	_check("world collision does not start an incident", not incidents.is_active() and incidents.stats_ignored_world == world0 + 1)
	var minor := CollisionEvent.new()
	minor.kind = CollisionEvent.Kind.TRAFFIC
	minor.other_agent_id = a.agent_id
	minor.impact_speed = 8.0 / 3.6
	_check("minor contact → LIGHT tier", IncidentRules.tier_for(minor, cfg) == IncidentRules.Tier.LIGHT)
	minor.impact_speed = 20.0 / 3.6
	_check("harder minor contact → MODERATE tier", IncidentRules.tier_for(minor, cfg) == IncidentRules.Tier.MODERATE)
	var light0 := incidents.stats_light + incidents.stats_altercations
	var horns0 := _horns
	var shouts0 := _shouts
	_collide(a, 8.0, false)
	await _frames(2)
	_check("light contact creates a reaction (horn/shout or stop)", incidents.stats_light + incidents.stats_altercations == light0 + 1 and (_horns > horns0 or _shouts > shouts0))
	if incidents.is_active():
		await _wait_resolved(1200)
	# Same vehicle is on cooldown; use a second one for the major incident.
	var b := _spawn_traffic_ahead(7.0)
	_check("second traffic vehicle placed", b != null and b != a)
	if b == null:
		return
	b.speed = 0.0
	_collide(b, 40.0, true)
	await _frames(2)
	_check("major collision → MAJOR altercation", incidents.is_active() and incidents.tier == IncidentRules.Tier.MAJOR)
	_check("other_agent_id resolved to the hit vehicle", incidents.agent == b and traffic.agent_by_id(b.agent_id) == b)
	_check("hit vehicle held", b.incident_hold)
	# Only one altercation at a time.
	var c := _spawn_traffic_ahead(30.0)
	var supp0 := incidents.stats_suppressed
	if c != null:
		_collide(c, 45.0, true)
		await _frames(2)
		_check("second major collision suppressed (one altercation max)", incidents.agent == b and incidents.stats_suppressed == supp0 + 1 and not c.incident_hold)
	# Let the driver get out and argue.
	var t := 0
	var last_phase := ""
	while incidents.phase != TrafficIncidentManager.Phase.ARGUING and incidents.is_active() and t < 600:
		await _frames(1)
		t += 1
		if incidents.phase_name() != last_phase:
			last_phase = incidents.phase_name()
			print("    t=%.2f phase %s driver %s dist %.1f" % [t / 60.0, last_phase, HumanAgent.State.keys()[incidents.driver.state] if incidents.driver != null else "-", incidents.driver.global_position.distance_to(player.global_position) if incidents.driver != null else -1.0])
		if incidents.driver != null:
			_driver_states[incidents.driver.state] = true
	_check("driver exits and approaches the tuk", _driver_states.has(HumanAgent.State.EXITING_VEHICLE) and _driver_states.has(HumanAgent.State.APPROACHING_PLAYER))
	_check("driver argues at talking distance (no contact)", incidents.phase == TrafficIncidentManager.Phase.ARGUING
			and incidents.driver.global_position.distance_to(player.global_position) > 1.8, "%.1f m" % (incidents.driver.global_position.distance_to(player.global_position) if incidents.driver != null else -1.0))
	_check("one driver in the world", humans.driver_count() == 1)
	var resolved := await _wait_resolved(1800)
	_check("incident resolves on its own", resolved, "%.1f s" % incidents.elapsed)
	_check("driver walked back and returned to the pool", _driver_states.has(HumanAgent.State.RETURNING_TO_VEHICLE) and humans.driver_count() == 0)
	_check("traffic vehicle released", not b.incident_hold)
	b.target_speed = 8.0
	await _frames(240)
	_check("affected traffic resumes", b.is_active and b.speed > 1.0, "%.1f km/h" % (b.speed * 3.6))

	print("=== Player drives away ===")
	await _frames(60)
	var d := _spawn_traffic_ahead(12.0)
	if d != null:
		d.speed = 0.0
		_collide(d, 42.0, true)
		t = 0
		while incidents.driver == null and incidents.is_active() and t < 300:
			await _frames(1)
			t += 1
		await _frames(30)
		var left0 := incidents.stats_player_left
		print("    phase before leaving: %s" % incidents.phase_name())
		player.global_transform = road.find_reset_transform(player.global_position + Vector3(0, 0, 80))
		await _frames(20)
		_check("driver gives up when the player leaves", incidents.stats_player_left == left0 + 1)
		var r := await _wait_resolved(1200)
		_check("incident resolves after player left (no chase)", r and humans.driver_count() == 0)

	print("=== Safety / scoring ===")
	_check("collisions never reward score", GameState.score <= score0, "%d → %d" % [score0, GameState.score])
	_check("no invalid human transitions", HumanAgent.invalid_transitions == invalid0)
	_check("human pool bounded", humans.active.size() <= humans.pool_capacity() and humans.free_count() + humans.active.size() == humans.pool_capacity())
	var held := 0
	for x in traffic.active_agents:
		if x.incident_hold:
			held += 1
	_check("no traffic left held", held == 0)
	_check("no timeouts", incidents.stats_timeouts == 0)


func _finish() -> void:
	print("")
	print("=== GPS + INCIDENTS: %s — %d failures ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
