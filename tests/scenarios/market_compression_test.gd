extends Node
## v0.03B1.1 Pettah compression: the narrowed market road in the real slice.
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/market_compression_test.tscn
##
## Two legal opposing lanes of valid width through the market core; lane
## reduction only at the signalised Market Gate (merges are junction-
## arbitrated); every pickup → destination routes; resets land on a legal
## market lane; spots and the pedestrian network stay intact; live traffic
## passes both ways through the core without deadlock, stalls or overlaps.

const SLICE := preload("res://scenes/districts/fort_pettah/fort_pettah_slice.tscn")
const CORE := ["MarketCoreA", "MarketBayIn", "MarketBay", "MarketBayOut", "MarketCoreB"]

var main: Node3D
var player: TukController
var road: RoadNetwork
var net: PedestrianNetwork
var traffic: TrafficManager
var recovery: WorldRecoveryManager
var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = SLICE.instantiate()
	main.set("human_seed", 61)
	main.set("offer_seed", 62)
	main.get_node("TrafficManager").set("rng_seed", 63)
	add_child(main)
	player = main.get_node("PlayerTuk")
	player.get_node("PlayerInput").set("enabled", false)
	road = main.get_node("TestTrack")
	net = main.get_node("TestTrack/Pedestrians")
	traffic = main.get_node("TrafficManager")
	recovery = main.get_node("WorldRecovery")
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seg(n: String) -> RoadSegment:
	for s in road.segments:
		if s.name == n:
			return s
	return null


func _run() -> void:
	print("\n=== v0.03B1.1 PETTAH COMPRESSION ===")
	await _frames(30)
	_lanes()
	_gate()
	_routing()
	_pedestrians()
	await _traffic()
	await _market_laps()
	print("\nMARKET COMPRESSION: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _lanes() -> void:
	print("\n-- market core lanes")
	for n in CORE:
		var seg := _seg(n)
		if seg == null:
			_check("segment %s exists" % n, false)
			continue
		var fwd := 0
		var rev := 0
		for l in road.lanes:
			if l.source_name == n:
				if l.is_forward:
					fwd += 1
				else:
					rev += 1
		_check("%s: one legal lane each direction" % n, fwd == 1 and rev == 1, "%d / %d" % [fwd, rev])
		_check("%s: lane width 2.8–2.9 m" % n, seg.lane_width >= 2.8 and seg.lane_width <= 2.9, "%.2f m" % seg.lane_width)
		_check("%s: buses excluded" % n, seg.bus_spawn_scale <= 0.01)
	var olcott := _seg("OlcottCorridor")
	_check("Olcott stays a broad arterial (2 lanes each way)", olcott != null and olcott.lanes_per_direction == 2)
	var station := _seg("StationFrontage")
	_check("Fort frontage stays broad (2 lanes each way)", station != null and station.lanes_per_direction == 2)
	var core := _seg("MarketCoreA")
	var before := olcott.carriageway_half(olcott.length * 0.5) * 2.0
	var after := core.carriageway_half(core.length * 0.5) * 2.0
	_check("market carriageway roughly half the corridor's", after < before * 0.6, "%.1f m → %.1f m" % [before, after])


func _gate() -> void:
	print("\n-- Market Gate (lane reduction is junction-arbitrated)")
	var gate: IntersectionController = null
	for ix in road.intersections:
		if ix.name == "MarketGate":
			gate = ix
	_check("Market Gate junction exists", gate != null)
	if gate == null:
		return
	var into_market := 0
	var merged := true
	for c in gate.connectors:
		var out: Lane = c.successors[0]
		if out.source_name == "MarketCoreA" and c.movement == IntersectionController.Movement.STRAIGHT:
			into_market += 1
	_check("both corridor lanes feed the single market lane", into_market == 2, "%d straight connectors" % into_market)
	for c in gate.connectors:
		for other in gate.connectors:
			if c != other and c.successors[0] == other.successors[0] and not c.conflicts.has(other):
				merged = false
	_check("merging connectors conflict (granted one at a time)", merged)
	var out_of_market := 0
	for c in gate.connectors:
		if (c.predecessors[0] as Lane).source_name == "MarketCoreA":
			out_of_market += 1
	_check("market exits the gate (straight + side street)", out_of_market >= 2, "%d" % out_of_market)


func _routing() -> void:
	print("\n-- routing")
	var pickups := net.spots_of_kind(PedestrianSpot.Kind.PICKUP)
	var dests := net.spots_of_kind(PedestrianSpot.Kind.DROPOFF)
	var bad := ""
	var n := 0
	for p in pickups:
		for d in dests:
			var plan := road.route_path(p.global_position, d.global_position)
			n += 1
			if plan == null or plan.is_empty():
				bad += " %s→%s" % [p.spot_id, d.spot_id]
	_check("every pickup routes to every destination", bad.is_empty(), "%d routes%s" % [n, bad])
	var station := Vector3(-10.5, 0, -86)
	var market := Vector3(193.1, 0, -94)
	var a := road.route_path(station, market)
	var b := road.route_path(market, station)
	_check("Fort → Market routes", a != null and not a.is_empty(), "%.0f m" % (a.length() if a != null else 0.0))
	_check("Market → Fort routes", b != null and not b.is_empty(), "%.0f m" % (b.length() if b != null else 0.0))
	# Resets inside the market land on a legal market lane, facing its traffic.
	var resets_ok := 0
	var samples := 0
	for n2 in ["MarketCoreA", "MarketBay", "MarketCoreB"]:
		var seg := _seg(n2)
		for k in 3:
			var p := seg.global_transform * seg.local_center(seg.length * (0.25 + k * 0.25))
			var xf := recovery.safe_reset_pose(p + Vector3(1.0, 0, 0))
			samples += 1
			var best := INF
			var aligned := false
			for l in road.lanes:
				if l.is_connector:
					continue
				for i in range(1, l.points.size()):
					var d := l.points[i].distance_to(Vector3(xf.origin.x, 0, xf.origin.z))
					if d < best:
						best = d
						aligned = (l.points[i] - l.points[i - 1]).normalized().dot(-xf.basis.z) > 0.9
			if best < 2.0 and aligned:
				resets_ok += 1
	_check("market resets land on a legal lane, facing its traffic", resets_ok == samples, "%d / %d" % [resets_ok, samples])


func _pedestrians() -> void:
	print("\n-- pedestrians")
	var unmapped := ""
	for s in net.spots:
		if s.node_id < 0 or net.node_pos[s.node_id].distance_to(s.global_position) > 2.5:
			unmapped += " " + String(s.spot_id)
	_check("every spot sits on the pedestrian network", unmapped.is_empty(), unmapped)
	var core := _seg("MarketCoreB")
	var east := 0
	var west := 0
	var c := core.global_transform * core.local_center(core.length * 0.5)
	for i in net.node_pos.size():
		var p := net.node_pos[i]
		if absf(p.z - c.z) < 18.0:
			if p.x > c.x + 3.4 and p.x < c.x + 7.0:
				east += 1
			elif p.x < c.x - 3.4 and p.x > c.x - 7.0:
				west += 1
	_check("market pavements on both sides", east > 4 and west > 4, "east %d / west %d nodes" % [east, west])
	var crossings := 0
	for cz in net.crossings:
		if CORE.has(String(cz.segment.name)):
			crossings += 1
	_check("crossings across the market core", crossings >= 2, "%d" % crossings)
	# Reachability from the market pickup across the network.
	var start: int = -1
	for s in net.spots:
		if s.spot_id == &"pickup_thrill":
			start = s.node_id
	var seen := {start: true}
	var stack: Array[int] = [start]
	while not stack.is_empty() and start >= 0:
		var i: int = stack.pop_back()
		for j in net.node_links[i]:
			if not seen.has(j):
				seen[j] = true
				stack.append(j)
	_check("market pedestrian network connected (crossings join both sides)", seen.size() > 60, "%d nodes reachable" % seen.size())


func _traffic() -> void:
	print("\n-- live traffic through the core (150 s)")
	# Park the tuk on the bay pavement so traffic is generated around the market.
	var bay := _seg("MarketBay")
	var pos := bay.global_transform * (bay.local_center(11.0) + bay.local_right(11.0) * -(bay.half_width(11.0) + 1.6))
	player.teleport(Transform3D(Basis.IDENTITY, pos + Vector3.UP * 0.4))
	player.input.handbrake = true
	var entered := {true: 0, false: 0}
	var last_lane := {}
	var stuck := {}
	var max_stuck := 0.0
	var overlaps := 0
	var t := 0.0
	var gate: IntersectionController = null
	for ix in road.intersections:
		if ix.name == "MarketGate":
			gate = ix
	var grants0 := gate.grants_issued.duplicate()
	while t < 150.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		for a in traffic.active_agents:
			if a.lane == null:
				continue
			var lane_name := a.lane.source_name
			var in_core := CORE.has(lane_name)
			if in_core and last_lane.get(a.agent_id, "") != lane_name and lane_name == ("MarketCoreA" if a.lane.is_forward else "MarketCoreB"):
				entered[a.lane.is_forward] = int(entered[a.lane.is_forward]) + 1
			last_lane[a.agent_id] = lane_name
			if in_core and a.speed < 0.3 and not a.incident_hold:
				stuck[a.agent_id] = float(stuck.get(a.agent_id, 0.0)) + 1.0 / 60.0
				max_stuck = maxf(max_stuck, float(stuck[a.agent_id]))
			else:
				stuck.erase(a.agent_id)
		if int(t * 60.0) % 30 == 0:
			for i in traffic.active_agents.size():
				for j in range(i + 1, traffic.active_agents.size()):
					var p: TrafficAgent = traffic.active_agents[i]
					var q: TrafficAgent = traffic.active_agents[j]
					if p.global_position.distance_to(q.global_position) > 8.0:
						continue
					var d := OrientedRect.distance(Vector2(p.global_position.x, p.global_position.z), Vector2(p.forward_vec.x, p.forward_vec.z), p.half_width, p.half_length,
							Vector2(q.global_position.x, q.global_position.z), Vector2(q.forward_vec.x, q.forward_vec.z), q.half_width, q.half_length)
					if d < -0.05:
						overlaps += 1
	_check("traffic enters the market core inbound", int(entered[true]) >= 3, "%d" % entered[true])
	_check("traffic enters the market core outbound", int(entered[false]) >= 3, "%d" % entered[false])
	_check("no vehicle stalls in the core (> 25 s stopped)", max_stuck < 25.0, "max %.1f s" % max_stuck)
	_check("no traffic overlaps (no head-on collisions)", overlaps == 0, "%d" % overlaps)
	_check("Market Gate serves both phase groups", gate.grants_issued[0] > grants0[0] and gate.grants_issued[1] >= grants0[1],
			"grants %s" % str(gate.grants_issued))
	var buses := 0
	for a in traffic.active_agents:
		if a.vehicle_class.is_heavy and a.lane != null and CORE.has(a.lane.source_name):
			buses += 1
	_check("no buses in the market core at the end", buses == 0, str(buses))


## Skill opportunities: the test autopilot (cruise 38 km/h — the market's
## natural 20–45 km/h band) drives the market core repeatedly for 120 s.
## Close calls / tight gaps must arise from real vehicle interactions only;
## pedestrian danger never scores.
func _market_laps() -> void:
	print("\n-- market laps: skill opportunities (120 s)")
	var skills := {"close_call": 0, "tight_gap": 0}
	var counts := {"awards": 0, "ped": 0, "laps": 0}  # lambdas capture ints by value
	var speeds := PackedFloat32Array()
	var on_skill := func(e: SkillEvent) -> void:
		skills["tight_gap" if e.type == SkillEvent.Type.TIGHT_GAP else "close_call"] = int(skills["tight_gap" if e.type == SkillEvent.Type.TIGHT_GAP else "close_call"]) + 1
	var on_award := func(_t: int, _p: int, _m: int, _total: int) -> void: counts["awards"] = int(counts["awards"]) + 1
	var on_ped := func(_e: PedestrianEvent) -> void: counts["ped"] = int(counts["ped"]) + 1
	EventBus.skill_event.connect(on_skill)
	EventBus.score_awarded.connect(on_award)
	EventBus.pedestrian_danger.connect(on_ped)
	var ap := AutopilotDriver.new()
	add_child(ap)
	ap.setup(player, road, traffic, 64)
	ap.cruise_kmh = 38.0
	player.input.handbrake = false
	var core_a := _seg("MarketCoreA")
	var core_b := _seg("MarketCoreB")
	var start := core_a.global_transform * core_a.local_center(1.0)
	var start_lane := _lane_named("MarketCoreA", true)
	var end_pos := core_b.global_transform * core_b.local_center(core_b.length)
	var t := 0.0
	var restart := func() -> void:
		var d := (start_lane.points[1] - start_lane.points[0]).normalized()
		player.teleport(Transform3D(MathUtil.basis_from_forward(d), start_lane.points[0] + d * 1.0 + Vector3.UP * 0.4))
		player.linear_velocity = d * 25.0 / 3.6
		counts["laps"] = int(counts["laps"]) + 1
	restart.call()
	while t < 120.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if int(t * 60.0) % 30 == 0:
			speeds.append(player.speed_kmh)
		var p := player.global_position
		if Vector2(p.x - end_pos.x, p.z - end_pos.z).length() < 6.0 or Vector2(p.x - start.x, p.z - start.z).length() > 160.0:
			restart.call()
	ap.queue_free()
	EventBus.skill_event.disconnect(on_skill)
	EventBus.score_awarded.disconnect(on_award)
	EventBus.pedestrian_danger.disconnect(on_ped)
	var mean := 0.0
	for v in speeds:
		mean += v
	mean /= maxf(speeds.size(), 1.0)
	var total := int(skills["close_call"]) + int(skills["tight_gap"])
	var awards: int = counts["awards"]
	print("  market laps %d, mean speed %.0f km/h, close calls %d, tight gaps %d, pedestrian danger %d, score awards %d" % [counts["laps"], mean, skills["close_call"], skills["tight_gap"], counts["ped"], awards])
	_check("skill opportunities arise in the market (vehicle interactions)", total >= 3, "%d in 2 min" % total)
	_check("only vehicle skill events score (pedestrian danger never rewards)", awards <= total, "%d awards / %d skill events" % [awards, total])


func _lane_named(n: String, forward: bool) -> Lane:
	for l in road.lanes:
		if l.source_name == n and l.is_forward == forward:
			return l
	return null
