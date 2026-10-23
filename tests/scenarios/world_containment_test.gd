extends Node
## v0.03A2 world containment, crash damage, recovery and impact props in the
## real prototype scene (no ambient traffic or people).
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/world_containment_test.tscn
##
## The tuk is launched at targets with an initial velocity (same physics as
## driving there); all speeds in output are km/h.

const MAIN := preload("res://scenes/prototype/prototype_main.tscn")

var main: Node3D
var player: TukController
var road: RoadNetwork
var net: PedestrianNetwork
var rides: RideManager
var offers: PassengerOfferManager
var guidance: RouteGuidance
var damage: VehicleDamageManager
var recovery: WorldRecoveryManager
var props: ImpactPropManager
var camera: Camera3D
var _failures := 0
var _events: Array[CollisionEvent] = []
var _results: Array[RideResult] = []
var _reactions := 0
var _damage_states: Array[int] = []


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
	main.set("human_seed", 41)
	main.set("offer_seed", 42)
	add_child(main)
	player = main.get_node("PlayerTuk")
	player.get_node("PlayerInput").set("enabled", false)
	road = main.get_node("TestTrack")
	net = main.get_node("TestTrack/Pedestrians")
	rides = main.get_node("RideManager")
	offers = main.get_node("PassengerOfferManager")
	guidance = main.get_node("RouteGuidance")
	damage = main.get_node("VehicleDamage")
	recovery = main.get_node("WorldRecovery")
	props = main.get_node("ImpactProps")
	camera = main.get_node("ChaseCamera")
	EventBus.collision_event.connect(func(e: CollisionEvent) -> void: _events.append(e))
	EventBus.ride_finished.connect(func(r: RideResult) -> void: _results.append(r))
	EventBus.passenger_reaction.connect(func(_k: String, _id: StringName) -> void: _reactions += 1)
	EventBus.vehicle_damage_changed.connect(func(s: int) -> void: _damage_states.append(s))
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _hold() -> void:
	player.input.throttle = 0.0
	player.input.brake = 0.0
	player.input.steer = 0.0
	player.input.handbrake = true


## Places the tuk `dist` m before `target` (horizontal), facing it, moving at `kmh`.
func _launch(target: Vector3, from_dir: Vector3, dist: float, kmh: float, y: float = 0.4) -> void:
	var dir := Vector3(from_dir.x, 0.0, from_dir.z).normalized()
	var start := Vector3(target.x, y, target.z) - dir * dist
	player.teleport(Transform3D(MathUtil.basis_from_forward(dir), start))
	player.linear_velocity = dir * kmh / 3.6
	damage.state.grace_left = 0.0
	_events.clear()


func _world_hit(types: Array) -> CollisionEvent:
	for e in _events:
		if e.kind == CollisionEvent.Kind.WORLD and types.has(WorldSurface.of_body(e.other_body)):
			return e
	return null


func _shape_of(body_path: String, index: int) -> CollisionShape3D:
	var body := road.get_node_or_null(body_path)
	if body == null or body.get_child_count() <= index:
		return null
	return body.get_child(index) as CollisionShape3D


func _run() -> void:
	await _frames(10)
	await _containment()
	await _structures()
	await _kerb()
	await _failsafe()
	await _damage_tiers()
	await _ride_fails_on_disable()
	await _props()
	_finish()


# --- containment ---

func _containment() -> void:
	print("=== World containment ===")
	var rect := road.district_rect
	var centre := Vector3(rect.get_center().x, 0.4, -150.0)
	var worst_out := 0.0
	for dir in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		player.teleport(Transform3D(MathUtil.basis_from_forward(dir), centre))
		damage.state.grace_left = 0.0
		for i in 60 * 25:
			player.input.handbrake = false
			player.input.brake = 0.0
			player.input.throttle = 1.0
			player.input.steer = 0.0
			await get_tree().physics_frame
			var p := player.global_position
			var outside := maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), maxf(rect.position.y - p.z, p.z - rect.end.y))
			worst_out = maxf(worst_out, outside)
	_hold()
	_check("full throttle in 4 directions never leaves the district", worst_out <= 0.0, "max %.1f m beyond the edge" % maxf(worst_out, 0.0))
	_check("no failsafe needed (physical containment)", recovery.stats_failsafe == 0, str(recovery.stats_failsafe))


func _structures() -> void:
	print("=== Buildings / walls / shopfronts are solid ===")
	# Boundary wall.
	var wall := _shape_of("DistrictBoundary/BoundaryWalls", 0)
	if wall != null:
		var outward := -wall.global_transform.basis.z
		var wp := wall.global_position
		_launch(wp, outward, 14.0, 25.0)
		await _frames(150)
		var hit := _world_hit([WorldSurface.Type.WALL])
		_check("wall collision reported as WALL", hit != null, "%.0f km/h" % (hit.impact_speed_kmh() if hit != null else 0.0))
		_check("tuk did not pass the wall", (player.global_position - wp).dot(outward) < 0.0)
	# Boundary building.
	var bld := _shape_of("DistrictBoundary/BoundaryBuildings", 3)
	if bld != null:
		var outward2 := -bld.global_transform.basis.z
		var bp := bld.global_position
		_launch(bp, outward2, 20.0, 30.0)
		await _frames(150)
		_check("building collision reported as BUILDING", _world_hit([WorldSurface.Type.BUILDING]) != null)
		_check("tuk did not enter the building", (player.global_position - bp).dot(outward2) < -4.0)
	# Shopfront (spot dressing) block.
	var shop: CollisionShape3D = null
	for c in net.get_children():
		if c.name.begins_with("Dressing_"):
			var body := c.get_node_or_null("DressingCollision")
			if body != null and WorldSurface.of_body(body) == WorldSurface.Type.BUILDING:
				shop = body.get_child(0) as CollisionShape3D
	_check("shopfront has collision", shop != null)
	if shop != null:
		var sp := shop.global_position
		var lane_p := road.find_reset_transform(sp).origin
		var toward := Vector3(sp.x - lane_p.x, 0.0, sp.z - lane_p.z)
		_launch(sp, toward, 10.0, 20.0, 0.5)
		await _frames(150)
		_check("shopfront blocks the tuk", _world_hit([WorldSurface.Type.BUILDING]) != null
				and Vector2(player.global_position.x - sp.x, player.global_position.z - sp.z).length() > 1.4)
	_hold()
	await _frames(200)


func _kerb() -> void:
	print("=== Pavement is accessible (no invisible wall) ===")
	# Long straight: east pavement (kerb at x≈7, pavement 7.15–10.3 m, 0.15 m high).
	var max_y := 0.0
	var trace := PackedStringArray()
	player.teleport(Transform3D(MathUtil.basis_from_forward(Vector3(0.42, 0, -1).normalized()), Vector3(4.5, 0.4, -160.0)))  # away from the crossings (s 130 / 215: dropped kerbs)
	player.linear_velocity = Vector3(0.42, 0, -1).normalized() * 25.0 / 3.6
	damage.state.grace_left = 0.0
	_events.clear()
	var resets := recovery.stats_recoveries
	for i in 120:
		player.input.throttle = 0.4
		player.input.handbrake = false
		await get_tree().physics_frame
		if i > 30:
			max_y = maxf(max_y, player.global_position.y)
		if i % 15 == 0:
			trace.append("%s %.0fkm/h" % [player.global_position.snapped(Vector3(0.01, 0.01, 0.1)), player.speed_kmh])
	print("    kerb trace: " + " | ".join(trace))
	_check("tuk climbs the kerb onto the pavement at 25 km/h", max_y > 0.1, "max y %.2f m (pavement 0.15 m)" % max_y)
	_check("pavement surface classified SIDEWALK", WorldSurface.classify_point(road, Vector3(9.0, 0.16, -170.0)) == WorldSurface.Type.SIDEWALK)
	_check("kerb contact never damages", damage.state.state == VehicleDamageState.State.HEALTHY)
	_check("no teleport for touching the pavement", recovery.stats_recoveries == resets)
	_hold()
	await _frames(60)


func _failsafe() -> void:
	print("=== Last-resort failsafe ===")
	var rect := road.district_rect
	var before := recovery.stats_failsafe
	player.teleport(Transform3D(Basis.IDENTITY, Vector3(rect.position.x - 60.0, 0.4, rect.get_center().y)))
	await _frames(30)
	_check("outside the district → recovered", recovery.stats_failsafe == before + 1 and road.district_rect.has_point(Vector2(player.global_position.x, player.global_position.z)))
	_check("recovered onto a road lane", WorldSurface.is_on_carriageway(road, player.global_position, 0.5))
	_check("recovered upright", player.global_transform.basis.y.dot(Vector3.UP) > 0.95)
	player.teleport(Transform3D(Basis.IDENTITY, Vector3(rect.get_center().x, -20.0, -150.0)))
	await _frames(30)
	_check("below the world → recovered", recovery.stats_failsafe == before + 2 and player.global_position.y > -1.0)
	await _frames(60)
	_check("no repeated failsafe once inside", recovery.stats_failsafe == before + 2)


# --- damage ---

func _building_target() -> CollisionShape3D:
	return _shape_of("DistrictBoundary/BoundaryBuildings", 5)


func _crash(kmh: float) -> void:
	var b := _building_target()
	var outward := -b.global_transform.basis.z
	_launch(b.global_position, outward, 16.0, kmh)
	for i in 90:
		player.input.throttle = 0.6  # keep driving into it
		player.input.handbrake = false
		await get_tree().physics_frame


func _damage_tiers() -> void:
	print("=== Damage tiers (km/h of impact) ===")
	await _crash(10.0)
	var e := _world_hit([WorldSurface.Type.BUILDING])
	_check("10 km/h scrape: LIGHT, stays HEALTHY", damage.state.state == VehicleDamageState.State.HEALTHY,
			"%.1f km/h" % (e.impact_speed_kmh() if e != null else 0.0))
	_hold()
	await _frames(60)
	await _crash(25.0)
	e = _world_hit([WorldSurface.Type.BUILDING])
	_check("25 km/h crash: DAMAGED (driveable)", damage.state.state == VehicleDamageState.State.DAMAGED,
			"%s, %.1f km/h" % [damage.state_name(), e.impact_speed_kmh() if e != null else 0.0])
	_check("engine cut / limp applied to throttle", damage.state.throttle_scale() < 1.0, "%.2f" % damage.state.throttle_scale())
	_hold()
	await _frames(int(60 * (damage.config.limp_seconds + 0.5)))
	_check("DAMAGED clears to HEALTHY", damage.state.state == VehicleDamageState.State.HEALTHY)
	var resets := damage.stats_resets
	var recov := recovery.stats_recoveries
	_damage_states.clear()
	await _crash(45.0)
	e = _world_hit([WorldSurface.Type.BUILDING])
	_check("45 km/h crash: DISABLED", _damage_states.has(VehicleDamageState.State.DISABLED), "%.1f km/h" % (e.impact_speed_kmh() if e != null else 0.0))
	var t := 0
	while damage.stats_resets == resets and t < 400:
		await _frames(1)
		t += 1
	var secs := (90 + t) / 60.0
	await _frames(2)
	_check("recovery after a short presentation (1.5–3.5 s)", damage.stats_resets == resets + 1 and recovery.stats_recoveries == recov + 1 and secs > 1.5 and secs < 3.5, "%.1f s" % secs)
	await _frames(5)
	_check("reset onto a road lane", WorldSurface.is_on_carriageway(road, player.global_position, 0.5))
	_check("reset upright and at rest", player.global_transform.basis.y.dot(Vector3.UP) > 0.95 and player.speed_kmh < 3.0)
	_check("reset spot clear", recovery.is_clear(player.global_position))
	_check("camera recovered near the tuk", camera.global_position.distance_to(player.global_position) < 15.0,
			"%.1f m" % camera.global_position.distance_to(player.global_position))
	_check("damage cleared after reset", damage.state.state == VehicleDamageState.State.HEALTHY)
	_check("GPS coherent (no ride → no route)", guidance.phase == RouteGuidance.Phase.NONE and guidance.plan == null)
	_hold()
	await _frames(240)
	_check("no reset loop", damage.stats_resets == resets + 1 and recovery.stats_recoveries == recov + 1)


func _ride_fails_on_disable() -> void:
	print("=== Disabling crash fails the active ride ===")
	var o: PassengerOffer = null
	for x in offers.offers:
		if x.state == PassengerOffer.State.AVAILABLE and x.passenger != null:
			o = x
			break
	if o == null:
		_check("offer available", false)
		return
	var out := net.node_out[o.pickup.node_id]
	player.teleport(Transform3D(MathUtil.basis_from_forward(out.cross(Vector3.UP)), o.passenger.global_position - out * 4.0 + Vector3.UP * 0.3))
	_hold()
	await _frames(10)
	rides.nearby_offer = o
	rides.request_accept()
	var t := 0
	while rides.state != RideManager.RideState.ACTIVE and t < 600:
		await _frames(1)
		t += 1
	_check("ride ACTIVE", rides.state == RideManager.RideState.ACTIVE)
	var n := _results.size()
	var reactions := _reactions
	await _crash(45.0)
	t = 0
	while _results.size() == n and t < 200:
		await _frames(1)
		t += 1
	var r: RideResult = _results[_results.size() - 1] if _results.size() > n else null
	_check("ride FAILED", r != null and r.outcome == RideResult.Outcome.FAILED)
	_check("fail reason VEHICLE_DISABLED", r != null and r.fail_reason == RideResult.FailReason.VEHICLE_DISABLED)
	_check("no fare", r != null and r.final_fare == 0)
	_check("passenger reacted", _reactions > reactions)
	await _frames(240)
	_check("GPS cleared after failed ride + reset", guidance.plan == null)
	_check("tuk healthy and on the road", damage.state.state == VehicleDamageState.State.HEALTHY and WorldSurface.is_on_carriageway(road, player.global_position, 0.5))
	t = 0
	while rides.state != RideManager.RideState.NO_RIDE and t < 1200:
		await _frames(1)
		t += 1


func _props() -> void:
	print("=== Impact props ===")
	_check("props placed along pavements", props.nodes.size() >= 6, str(props.nodes.size()))
	var i := 0
	var pp := props.nodes[i].global_position
	var lane_t := road.find_reset_transform(pp)
	var along := -lane_t.basis.z
	_launch(pp, along, 12.0, 25.0, 0.5)
	for k in 90:
		player.input.throttle = 0.4
		player.input.handbrake = false
		await get_tree().physics_frame
	var knocked := props.states[i] != ImpactPropManager.PropState.STANDING
	_check("prop knocked by a 25 km/h tuk", knocked and props.stats_knocked >= 1, ImpactPropManager.PropState.keys()[props.states[i]])
	_check("prop never stops the tuk (not a wall)", _world_hit([WorldSurface.Type.PROP]) == null)
	_check("debris bounded", props.active_debris() <= ImpactPropManager.DEBRIS_POOL)
	_hold()
	await _frames(60 * 6)
	_check("knocked prop settled and cleared", props.states[i] == ImpactPropManager.PropState.GONE, ImpactPropManager.PropState.keys()[props.states[i]])
	_check("debris cleared", props.active_debris() == 0)


func _finish() -> void:
	print("")
	print("=== WORLD + DAMAGE: %s — %d failures ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
