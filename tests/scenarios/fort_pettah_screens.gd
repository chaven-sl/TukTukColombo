extends Node
## Windowed only: Fort–Pettah quality-gate screenshots (v0.03B).
##   godot --path . --resolution 1280x720 res://tests/scenarios/fort_pettah_screens.tscn [-- --gates]
## Saves to user://test_results/screens/v003b_*.png. With --gates: the four
## v0.03B quality gates (A hero road, B market chaos, C active hire,
## D incident) with traffic staged around the tuk.

const SLICE := preload("res://scenes/districts/fort_pettah/fort_pettah_slice.tscn")

var main: Node3D
var player: TukController
var road: RoadNetwork
var traffic: TrafficManager
var humans: HumanManager
var rides: RideManager
var offers: PassengerOfferManager
var incidents: TrafficIncidentManager
var _staged_people: Array[HumanAgent] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = SLICE.instantiate()
	main.set("human_seed", 3)
	main.set("offer_seed", 3)
	main.get_node("TrafficManager").set("rng_seed", 5)
	add_child(main)
	player = main.get_node("PlayerTuk")
	road = main.get_node("TestTrack")
	traffic = main.get_node("TrafficManager")
	humans = main.get_node("HumanManager")
	rides = main.get_node("RideManager")
	offers = main.get_node("PassengerOfferManager")
	incidents = main.get_node("TrafficIncidentManager")
	player.get_node("PlayerInput").set("enabled", false)
	(main.get_node("TouchInput") as TouchInputSource).enabled = false
	await _frames(30)
	if "--gates" in OS.get_cmdline_user_args():
		await _gates()
		get_tree().quit()
		return
	print("[Screens] traffic %d, humans %d" % [(main.get_node("TrafficManager") as TrafficManager).active_agents.size(), (main.get_node("HumanManager") as HumanManager).active.size()])
	await _shot_at("StationFrontage", 40.0, 0.0, "v003b_look_station")
	await _shot_at("OlcottCorridor", 20.0, 0.0, "v003b_look_olcott")
	await _shot_at("MarketApproach", 30.0, 0.0, "v003b_look_market")
	await _shot_at("JunctionApproach", 5.0, 0.0, "v003b_look_junction")
	await _shot_at("ServiceConnector", 10.0, 0.0, "v003b_look_service")
	get_tree().quit()


func _seg(n: String) -> RoadSegment:
	for s in road.segments:
		if s.name == n:
			return s
	return null


## Puts the tuk in the left (kerb-side) forward lane of segment `n` at `s`.
func _shot_at(n: String, s: float, lateral: float, name: String) -> void:
	var seg := _seg(n)
	var xf := seg.global_transform
	var lane_off := -(seg.median_at(s) * 0.5 + seg.lane_width_at(s) * 1.5) + lateral
	var p := xf * (seg.local_center(s) + seg.local_right(s) * lane_off)
	var fwd := xf.basis * seg.local_tangent(s)
	player.teleport(Transform3D(MathUtil.basis_from_forward(fwd), p + Vector3.UP * 0.4))
	player.input.handbrake = true
	await _frames(45)
	await _shot(name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		GameState.set_paused(false)


func _shot(name: String) -> void:
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://test_results/screens")
	img.save_png("user://test_results/screens/%s.png" % name)
	print("[Screens] %s" % name)


# --- v0.03B quality gates ---

func _cls(kind: TrafficVehicleClass.Kind) -> TrafficVehicleClass:
	for c in traffic.vehicle_classes:
		if c.kind == kind:
			return c
	return null


func _lane(seg_name: String, index: int) -> Lane:
	for l in road.lanes:
		if l.source_name == seg_name and l.is_forward and l.lane_index == index:
			return l
	return null


## Puts a vehicle of `kind` (paint `color`) on `lane` at `s`, re-using an
## active agent of that kind or taking one from the pool.
func _stage(kind: TrafficVehicleClass.Kind, color: int, lane: Lane, s: float, kmh: float) -> TrafficAgent:
	var cls := _cls(kind)
	if cls == null or lane == null:
		return null
	var agent := traffic.pool.acquire(cls)
	if agent != null:
		traffic.active_agents.append(agent)
	else:
		for a in traffic.active_agents:
			if a.vehicle_class == cls and not a.get_meta("staged", false):
				agent = a
				agent.deactivate()
				break
	if agent == null:
		return null
	agent.set_meta("staged", true)
	agent.set_visual_variant(color)
	agent.activate(lane, s, kmh / 3.6, kmh / 3.6, traffic.choose_next_lane(lane))
	return agent


func _clear_staged() -> void:
	for a in traffic.active_agents:
		a.remove_meta("staged")


func _place_player(seg_name: String, s: float, lane_index: int) -> void:
	var lane := _lane(seg_name, lane_index)
	var i := clampi(lane.cumulative.bsearch(s), 1, lane.points.size() - 1)
	var fwd := (lane.points[i] - lane.points[i - 1]).normalized()
	player.teleport(Transform3D(MathUtil.basis_from_forward(fwd), lane.points[i] + Vector3.UP * 0.4))
	player.input.handbrake = true


func _gates() -> void:
	# A. Hero road: tuk, red public bus, another tuk, motorcycle, people, signs.
	# lane_index 0 runs beside the centre line; 1 is the kerb lane.
	var inner := _lane("OlcottCorridor", 0)
	var kerb := _lane("OlcottCorridor", 1)
	_place_player("OlcottCorridor", 14.0, 1)
	_stage(TrafficVehicleClass.Kind.BUS, 0, kerb, 34.0, 10.0)
	_stage(TrafficVehicleClass.Kind.TUK, 1, inner, 24.0, 14.0)
	_stage(TrafficVehicleClass.Kind.MOTORCYCLE, 0, inner, 19.0, 16.0)
	_stage(TrafficVehicleClass.Kind.TUK, 4, inner, 46.0, 14.0)
	_people(8, 8.0, 45.0)
	await _frames(12)
	await _shot("v003b_gate_a_hero_road")
	_clear_staged()
	_release_people()
	# B. Market chaos: dense stalls, umbrellas, people, tuks, a van, bikes.
	var m0 := _lane("MarketApproach", 0)
	var m1 := _lane("MarketApproach", 1)
	_place_player("MarketApproach", 30.0, 1 if m1 != null else 0)
	_stage(TrafficVehicleClass.Kind.TUK, 2, m0, 40.0, 8.0)
	_stage(TrafficVehicleClass.Kind.VAN, 0, m1 if m1 != null else m0, 52.0, 6.0)
	_stage(TrafficVehicleClass.Kind.MOTORCYCLE, 1, m0, 46.0, 10.0)
	_stage(TrafficVehicleClass.Kind.TUK, 3, m0, 64.0, 8.0)
	_people(18, 4.0, 34.0)
	await _frames(12)
	await _shot("v003b_gate_b_market_chaos")
	_clear_staged()
	_release_people()
	# C. Active hire: passenger seated in the tuk, GPS ribbon, ride HUD.
	var offer := _offer_with_route()
	if offer == null:
		print("[Screens] no offer for gate C")
		return
	var out := humans.network.node_out[offer.pickup.node_id]
	player.teleport(Transform3D(MathUtil.basis_from_forward(out.cross(Vector3.UP)), offer.pickup.global_position - out * 4.0 + Vector3.UP * 0.3))
	player.input.handbrake = true
	player.input.brake = 1.0
	var t := 0
	while t < 900 and rides.state != RideManager.RideState.ACTIVE:
		if rides.nearby_offer == offer and rides.state == RideManager.RideState.NO_RIDE:
			rides.request_accept()
		await _frames(1)
		t += 1
	print("[Screens] hire state %s after %d frames" % [RideManager.RideState.keys()[rides.state], t])
	player.input.handbrake = false
	player.input.brake = 0.0
	var ap := AutopilotDriver.new()
	add_child(ap)
	ap.setup(player, road, traffic, 3)
	await _frames(200)
	ap.set_physics_process(false)
	player.input.throttle = 0.0
	player.input.brake = 0.4
	await _frames(30)
	await _shot("v003b_gate_c_active_hire")
	# D. Incident: driver out and arguing, passenger still in the tuk.
	var best: TrafficAgent = null
	var best_d := 40.0
	for a in traffic.active_agents:
		var d := a.global_position.distance_to(player.global_position)
		if d < best_d and a.vehicle_class.kind != TrafficVehicleClass.Kind.MOTORCYCLE:
			best_d = d
			best = a
	if best == null:
		var l := _nearest_lane_ahead()
		best = _stage(TrafficVehicleClass.Kind.CAR, 1, l, 0.0, 0.0)
	for attempt in 4:
		if best == null or humans.driver_count() > 0:
			break
		while incidents.phase != TrafficIncidentManager.Phase.NONE:
			await _frames(1)
		# Park the other vehicle just ahead of the tuk in its lane, then report
		# the same CollisionEvent TukController emits for a moderate bump.
		var l2 := _nearest_lane_ahead()
		if l2 != null:
			best.deactivate()
			best.activate(l2, _s_on(l2, player.global_position) + 6.5, 0.0, 0.0, traffic.choose_next_lane(l2))
		var ev := CollisionEvent.new()
		ev.kind = CollisionEvent.Kind.TRAFFIC
		ev.severity = CollisionEvent.Severity.MAJOR
		ev.impact_speed = 38.0 / 3.6  # MAJOR tier: the driver usually gets out
		ev.position = player.global_position
		ev.other_agent_id = best.agent_id
		ev.timestamp = SimClock.now()
		EventBus.collision_event.emit(ev)
		player.input.brake = 1.0
		player.input.handbrake = true
		for w in 240:
			if humans.driver_count() > 0:
				break
			await _frames(1)
		print("[Screens] incident attempt %d: altercations %d, drivers %d" % [attempt, incidents.stats_altercations, humans.driver_count()])
		if humans.driver_count() == 0:
			while incidents.phase != TrafficIncidentManager.Phase.NONE:
				await _frames(1)
			var idx := traffic.active_agents.find(best)
			if idx >= 0:
				traffic._despawn_at(idx)  # the honk-only car leaves the shot
			best = _stage(TrafficVehicleClass.Kind.CAR, attempt + 1, _nearest_lane_ahead(), 0.0, 0.0)
	player.input.brake = 1.0
	player.input.handbrake = true
	var f := 0
	while f < 400 and humans.driver_count() == 0:
		await _frames(1)
		f += 1
	await _frames(150)
	var drv: HumanAgent = null
	for h in humans.active:
		if h.role == HumanAgent.Role.TRAFFIC_DRIVER:
			drv = h
	var car_pos: Vector3 = incidents.agent.global_position if incidents.agent != null else player.global_position
	print("[Screens] incident drivers %d, ride %s, tuk %s car %s driver %s" % [humans.driver_count(), RideManager.RideState.keys()[rides.state],
			player.global_position, car_pos, drv.global_position if drv != null else Vector3.ZERO])
	# The chase camera sits behind the tuk and hides a driver in front of it
	# (known debt), so frame the gate from the road side, ahead of the car,
	# looking back at the driver (who exits on the vehicle's right).
	var fwd := -player.global_transform.basis.z
	var right := fwd.cross(Vector3.UP)
	var focus := (player.global_position + car_pos) * 0.5 + Vector3.UP * 1.0
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.global_position = focus + right * 6.5 + fwd * 5.5 + Vector3.UP * 2.4
	cam.look_at(focus, Vector3.UP)
	cam.make_current()
	await _frames(4)
	await _shot("v003b_gate_d_incident")


## Ambient people on the pavement nodes `near`–`far` m ahead of the tuk.
func _people(count: int, near: float, far: float) -> void:
	var fwd := -player.global_transform.basis.z
	var net := humans.network
	var placed := 0
	var i := 0
	while placed < count and i < net.node_pos.size():
		var p := net.node_pos[(i * 37) % net.node_pos.size()]
		i += 1
		var d := (p - player.global_position).dot(fwd)
		var lat := absf((p - player.global_position).dot(fwd.cross(Vector3.UP)))
		if d < near or d > far or lat > 16.0:
			continue
		var a := humans._acquire(HumanAgent.Role.SIDEWALK_WALKER, net.nearest_node(p))
		if a == null:
			return
		a.behaviour = humans.get("_pedestrian_behaviour")
		a.idle_timer = 8.0
		a.set_state(HumanAgent.State.IDLE)
		a.face(fwd.rotated(Vector3.UP, float(placed) * 1.7))
		_staged_people.append(a)
		placed += 1


func _release_people() -> void:
	for a in _staged_people:
		if a.is_pooled_active:
			humans.release(a)
	_staged_people.clear()


func _offer_with_route() -> PassengerOffer:
	for id in [&"pickup_executive", &"pickup_thrill", &"pickup_aunty"]:
		for o in offers.offers:
			if o.pickup.spot_id == id and o.state == PassengerOffer.State.AVAILABLE and o.passenger != null:
				return o
	for o in offers.offers:
		if o.state == PassengerOffer.State.AVAILABLE and o.passenger != null:
			return o
	return null


func _s_on(lane: Lane, p: Vector3) -> float:
	var best := 0
	var bd := INF
	for i in lane.points.size():
		var d := lane.points[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return lane.cumulative[best]


func _nearest_lane_ahead() -> Lane:
	var fwd := -player.global_transform.basis.z
	var best: Lane = null
	var bd := 9.0
	for l in road.lanes:
		if l.is_connector:
			continue
		var s := _s_on(l, player.global_position)
		var i := clampi(l.cumulative.bsearch(s), 1, l.points.size() - 1)
		var d := l.points[i].distance_squared_to(player.global_position)
		if d < bd and (l.points[i] - l.points[i - 1]).dot(fwd) > 0.0:
			bd = d
			best = l
	return best
