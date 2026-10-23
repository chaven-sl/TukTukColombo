extends Node
## v0.03B Fort–Pettah vertical slice: art / presentation / audio checks in the
## real district scene (same gameplay systems as the greybox prototype).
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/fort_pettah_test.tscn
##
## Covers: hero tuk visual + steering hooks, art never touching mass/collision,
## traffic paint variants, human presentation swaps, collider/visual
## separation, no proxy collider on a legal lane or spawn, station/market
## routes + GPS ribbon on the new road, audio buses and hooks.

const SLICE := preload("res://scenes/districts/fort_pettah/fort_pettah_slice.tscn")

var main: Node3D
var player: TukController
var road: RoadNetwork
var net: PedestrianNetwork
var traffic: TrafficManager
var humans: HumanManager
var guidance: RouteGuidance
var dresser: FortPettahDresser
var audio: DistrictAudio
var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = SLICE.instantiate()
	main.set("human_seed", 51)
	main.set("offer_seed", 52)
	add_child(main)
	player = main.get_node("PlayerTuk")
	player.get_node("PlayerInput").set("enabled", false)
	road = main.get_node("TestTrack")
	net = main.get_node("TestTrack/Pedestrians")
	traffic = main.get_node("TrafficManager")
	humans = main.get_node("HumanManager")
	guidance = main.get_node("RouteGuidance")
	dresser = main.get_node("DistrictArt")
	audio = main.get_node("DistrictAudio")
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	print("\n=== v0.03B FORT–PETTAH SLICE ===")
	await _frames(90)
	_district()
	_hero_tuk()
	await _hero_steering()
	_traffic_variants()
	_human_presentation()
	_collider_separation()
	_lanes_and_spawns_clear()
	_routes_and_ribbon()
	await _audio()
	print("\nFORT–PETTAH: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _district() -> void:
	print("\n-- district")
	var total := 0.0
	for seg in road.segments:
		total += seg.length
	_check("route ~700–900 m of district road", total > 650.0 and total < 1100.0, "%.0f m over %d segments" % [total, road.segments.size()])
	_check("dressed: buildings / props / signs", int(dresser.stats["buildings"]) > 100 and int(dresser.stats["props"]) > 50 and int(dresser.stats["signs"]) > 50,
			str(dresser.stats))
	_check("side streets terminated (no open voids)", int(dresser.stats["side_streets"]) >= 6)
	_check("art batched into few meshes", dresser.chunks.mesh_instances < 220, "%d meshes, %d tris" % [dresser.chunks.mesh_instances, dresser.chunks.triangles])
	_check("sign atlas ≤1024² and in use", dresser.atlas.used_fraction() > 0.2 and dresser.atlas.used_fraction() <= 1.0)
	var names: Array[StringName] = []
	for s in net.spots:
		names.append(s.spot_id)
	for key in ["PLACE_FORT_STATION_ENTRANCE", "PLACE_PETTAH_BUS_STAND", "PLACE_MARKET_LANE", "PLACE_OLCOTT_CORNER", "PLACE_STATION_ARCADE"]:
		var found := false
		for s in net.spots:
			if s.display_name_key == key:
				found = true
		_check("place %s exists" % key, found)


func _hero_tuk() -> void:
	print("\n-- hero tuk")
	var hero := player.get_node_or_null("Visual/HeroArt") as HeroTukVisual
	_check("visual tuk exists", hero != null and hero.body_instance != null and hero.body_instance.mesh != null)
	if hero == null:
		return
	_check("hero tuk ≤30k triangles", hero.triangle_count() > 500 and hero.triangle_count() <= 30000, "%d tris" % hero.triangle_count())
	_check("stylised driver seated (DRIVE)", hero.driver != null and hero.driver.mode == CharacterRig.Mode.DRIVE)
	var wheels := 0
	for path in ["Visual/FrontSteer/Spin/HeroWheel", "Visual/RearLeft/Spin/HeroWheel", "Visual/RearRight/Spin/HeroWheel"]:
		if player.get_node_or_null(path) != null:
			wheels += 1
	_check("three hero wheels under the physics wheel hooks", wheels == 3)
	# Art follows physics: no collider, body or mass change anywhere in the art.
	var bodies := _count_collision(hero)
	_check("no collider / body in hero art", bodies == 0)
	_check("mass and CoM unchanged by art", is_equal_approx(player.mass, player.tuning.mass_kg)
			and player.center_of_mass.is_equal_approx(player.tuning.center_of_mass), "%.0f kg" % player.mass)


func _hero_steering() -> void:
	var hero := player.get_node_or_null("Visual/HeroArt") as HeroTukVisual
	if hero == null:
		return
	player.input.steer = 1.0
	await _frames(30)
	var steer := player.get_node("Visual/FrontSteer") as Node3D
	_check("hero front wheel steers", absf(steer.rotation.y) > 0.05, "%.1f°" % rad_to_deg(steer.rotation.y))
	_check("handlebar follows steering", is_equal_approx(hero.handlebar.rotation.y, steer.rotation.y))
	player.input.steer = 0.0
	player.input.brake = 1.0
	await _frames(10)
	player.input.brake = 0.0


func _count_collision(n: Node) -> int:
	var c := 1 if (n is CollisionObject3D or n is CollisionShape3D) else 0
	for k in n.get_children():
		c += _count_collision(k)
	return c


func _traffic_variants() -> void:
	print("\n-- traffic art")
	var meshes := {}
	var kinds := {}
	var ok := true
	for a in traffic.active_agents:
		kinds[a.vehicle_class.kind] = true
		for mi in a.body_meshes:
			meshes[mi.mesh] = true
			ok = ok and mi.mesh != null and _count_collision(mi) == 0
	_check("traffic active with art", traffic.active_agents.size() > 3 and ok, "%d agents" % traffic.active_agents.size())
	_check("paint variants assigned (several meshes)", meshes.size() >= 3, "%d meshes, %d kinds" % [meshes.size(), kinds.size()])
	var bus: TrafficVehicleClass = load("res://resources/traffic/bus.tres")
	var red := TrafficArt.mesh_for(bus, 0)
	var other := TrafficArt.mesh_for(bus, 1)
	_check("bus public + private variants differ", red != other and red.get_faces().size() / 3 <= 10000, "%d tris" % (red.get_faces().size() / 3))
	for path in ["car", "van", "tuk", "motorcycle"]:
		var cls: TrafficVehicleClass = load("res://resources/traffic/%s.tres" % path)
		var tris := TrafficArt.mesh_for(cls, 0).get_faces().size() / 3
		var budget := 8000 if path == "car" or path == "van" else (6000 if path == "tuk" else 4000)
		_check("%s within triangle budget" % path, tris > 50 and tris <= budget, "%d / %d tris" % [tris, budget])


func _human_presentation() -> void:
	print("\n-- humans")
	var agent: HumanAgent = null
	for a in humans.all_agents:
		if a.rig != null:
			agent = a
			break
	_check("human uses stylised rig", agent != null)
	if agent == null:
		return
	var before := agent.rig.mesh_instance.mesh
	var v := agent.rig.variant
	agent.set_appearance((v + 3) % CharacterBuilder.VARIANTS.size())
	_check("presentation swaps", agent.rig.mesh_instance.mesh != before)
	agent.set_appearance(v)
	_check("8–12 character combinations", CharacterBuilder.VARIANTS.size() >= 8 and CharacterBuilder.VARIANTS.size() <= 12)
	var tris := CharacterBuilder.mesh_for(0).get_faces().size() / 3
	_check("character ≤4k triangles", tris <= 4000, "%d tris" % tris)
	_check("rig has no collider", _count_collision(agent.rig) == 0)


func _collider_separation() -> void:
	print("\n-- collision vs visuals")
	var shapes := 0
	var meshes_in_bodies := 0
	for b: StaticBody3D in [dresser.building_body, dresser.prop_body, dresser.forecourt_body]:
		for c in b.get_children():
			if c is CollisionShape3D:
				shapes += 1
			if c is MeshInstance3D:
				meshes_in_bodies += 1
	_check("simple proxy colliders exist", shapes > 100, "%d boxes" % shapes)
	_check("proxy bodies carry no visual meshes", meshes_in_bodies == 0)
	var bodies_in_art := 0
	for c in dresser.get_children():
		if c != dresser.building_body and c != dresser.prop_body and c != dresser.forecourt_body:
			bodies_in_art += _count_collision(c)
	_check("visual chunks carry no colliders", bodies_in_art == 0)
	_check("building proxies tagged BUILDING", WorldSurface.of_body(dresser.building_body) == WorldSurface.Type.BUILDING)


func _proxy_hit(at: Vector3, half: Vector3, basis: Basis) -> Object:
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = half * 2.0
	q.shape = box
	q.transform = Transform3D(basis, at)
	q.collision_mask = 1
	for hit in player.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var col: Object = hit["collider"]
		if col == dresser.building_body or col == dresser.prop_body or col == dresser.forecourt_body:
			return col
	return null


func _lanes_and_spawns_clear() -> void:
	print("\n-- legal lanes / spawns")
	var blocked := 0
	var samples := 0
	var first := ""
	for lane in road.lanes:
		var k := 0.0
		while k < lane.length:
			var i := lane.cumulative.bsearch(k)
			i = clampi(i, 1, lane.points.size() - 1)
			var p := lane.points[i]
			var d := (lane.points[i] - lane.points[i - 1]).normalized()
			var basis := Basis.looking_at(d if d.length_squared() > 0.0 else Vector3.FORWARD, Vector3.UP)
			samples += 1
			if _proxy_hit(p + Vector3.UP * 1.3, Vector3(0.7, 0.9, 1.0), basis) != null:
				blocked += 1
				if first.is_empty():
					first = "%s @ %.0f m %s" % [lane.source_name, k, p]
			k += 4.0
	_check("no collider blocks a legal lane", blocked == 0, "%d / %d samples blocked %s" % [blocked, samples, first])
	var spawn := road.get_node("PlayerSpawn") as Marker3D
	_check("player spawn clear of art", _proxy_hit(spawn.global_position + Vector3.UP * 1.0, Vector3(0.8, 0.7, 1.4), spawn.global_basis) == null)
	var bad := ""
	for s in net.spots:
		var hit := _proxy_hit(s.global_position + Vector3.UP * 1.0, Vector3(0.25, 0.7, 0.25), Basis.IDENTITY)
		if hit != null:
			bad += " %s→%s" % [s.spot_id, (hit as Node).name]
	_check("no pedestrian spot inside art", bad.is_empty(), "%d spots%s" % [net.spots.size(), bad])


func _spot(id: StringName) -> PedestrianSpot:
	for s in net.spots:
		if s.spot_id == id:
			return s
	return null


func _routes_and_ribbon() -> void:
	print("\n-- routes + GPS ribbon")
	var station := _spot(&"pickup_executive")
	var market := _spot(&"dest_market")
	var bus_stand := _spot(&"pickup_aunty")
	_check("station / market / bus stand spots", station != null and market != null and bus_stand != null)
	if station == null or market == null or bus_stand == null:
		return
	var p1 := road.route_path(station.global_position, market.global_position)
	var p2 := road.route_path(market.global_position, station.global_position)
	var p3 := road.route_path(bus_stand.global_position, station.global_position)
	_check("station → market route valid", p1 != null and not p1.is_empty(), "%.0f m" % (p1.length() if p1 != null else 0.0))
	_check("market → station route valid", p2 != null and not p2.is_empty(), "%.0f m" % (p2.length() if p2 != null else 0.0))
	_check("bus stand → station route valid", p3 != null and not p3.is_empty(), "%.0f m" % (p3.length() if p3 != null else 0.0))
	if p1 == null or p1.is_empty():
		return
	var ribbon: RouteRibbon = guidance.get("_ribbon")
	ribbon.show_plan(p1, guidance.config)
	_check("ribbon visible", ribbon.visible and ribbon.mesh != null)
	var space := player.get_world_3d().direct_space_state
	var on_road := 0
	var n := 0
	var along := 5.0
	while along < p1.length():
		var p := p1.position_at(along) + Vector3.UP * guidance.config.ribbon_height
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p - Vector3.UP * 3.0, 1)
		var hit := space.intersect_ray(q)
		n += 1
		if not hit.is_empty() and p.y - (hit["position"] as Vector3).y > 0.0 and p.y - (hit["position"] as Vector3).y < 0.2:
			on_road += 1
		along += 10.0
	_check("ribbon sits just above the new road", n > 5 and on_road == n, "%d / %d samples" % [on_road, n])
	ribbon.clear()


func _audio() -> void:
	print("\n-- audio")
	for bus_name in ["Vehicle", "Traffic", "Ambience", "UI"]:
		_check("audio bus %s" % bus_name, AudioServer.get_bus_index(bus_name) >= 0)
	_check("audio layer set up", audio.player == player and audio.get_child_count() >= 14, "%d players" % audio.get_child_count())
	var idle := AudioLibrary.get_stream("tuk_engine_idle") as AudioStreamWAV
	_check("engine loop marked", idle != null and idle.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	var horns := int(audio.stats["horns"])
	EventBus.horn_sounded.emit(player.global_position)
	var impacts := int(audio.stats["impacts"])
	var e := CollisionEvent.new()
	e.kind = CollisionEvent.Kind.WORLD
	e.severity = CollisionEvent.Severity.MAJOR
	EventBus.collision_event.emit(e)
	await _frames(2)
	_check("horn hook plays", int(audio.stats["horns"]) > horns)
	_check("collision hook plays", int(audio.stats["impacts"]) > impacts)
	player.input.throttle = 1.0
	await _frames(120)
	player.input.throttle = 0.0
	var load_player := audio.get("_load") as AudioStreamPlayer
	_check("engine load rises with throttle/speed", load_player.volume_db > -20.0 and load_player.pitch_scale > 0.8,
			"%.1f dB, pitch %.2f at %.0f km/h" % [load_player.volume_db, load_player.pitch_scale, player.speed_kmh])
