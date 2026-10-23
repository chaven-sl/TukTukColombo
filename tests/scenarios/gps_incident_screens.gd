extends Node
## Windowed only: screenshots of the v0.03A1 hire card, GPS ribbon/instruction
## and a traffic altercation, saved to user://test_results/screens/.
##   godot --path . --resolution 1200x540 res://tests/scenarios/gps_incident_screens.tscn [-- --force-touch-controls]

const MAIN := preload("res://scenes/prototype/prototype_main.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var main: Node3D = MAIN.instantiate()
	var tm: TrafficManager = main.get_node("TrafficManager")
	var tcfg: TrafficConfig = tm.config.duplicate()
	tcfg.gameplay_density_target = 4
	tm.config = tcfg
	main.set("offer_seed", 32)
	main.set("incident_seed", 33)
	add_child(main)
	var player: TukController = main.get_node("PlayerTuk")
	var rides: RideManager = main.get_node("RideManager")
	var road: RoadNetwork = main.get_node("TestTrack")
	var offers: PassengerOfferManager = main.get_node("PassengerOfferManager")
	var incidents: TrafficIncidentManager = main.get_node("TrafficIncidentManager")
	player.get_node("PlayerInput").set("enabled", false)
	(main.get_node("TouchInput") as TouchInputSource).enabled = false
	var o: PassengerOffer = offers.offers[0]
	var dir: Vector3 = road.route(o.passenger.global_position, o.passenger.global_position + Vector3.FORWARD)["start_dir"]
	player.teleport(Transform3D(MathUtil.basis_from_forward(dir), road.find_reset_transform(o.passenger.global_position - dir * 70.0).origin))
	player.input.handbrake = true
	await _frames(40)
	await _shot("v003a1_hire_card")
	rides.request_accept()
	await _frames(60)
	await _shot("v003a1_gps_pickup")
	# Altercation: put a car just ahead and report a major collision with it.
	var lane: Lane = null
	var best := INF
	for l in road.lanes:
		if l.is_connector:
			continue
		var s := l.closest_s(player.global_position)
		var d := l.sample_position(s).distance_to(player.global_position)
		if d < best and l.sample_tangent(s).dot(-player.global_transform.basis.z) > 0.7:
			best = d
			lane = l
	tm._activate(tm.vehicle_classes[0], lane, lane.closest_s(player.global_position) + 7.0)
	var car: TrafficAgent = tm.active_agents[tm.active_agents.size() - 1]
	car.speed = 0.0
	var ev := CollisionEvent.new()
	ev.kind = CollisionEvent.Kind.TRAFFIC
	ev.severity = CollisionEvent.Severity.MAJOR
	ev.impact_speed = 40.0 / 3.6
	ev.other_agent_id = car.agent_id
	EventBus.collision_event.emit(ev)
	var t := 0
	while incidents.phase != TrafficIncidentManager.Phase.ARGUING and t < 600:
		await _frames(1)
		t += 1
	await _frames(40)
	await _shot("v003a1_altercation")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
	GameState.set_paused(false)  # an unfocused test window triggers the focus-loss pause


func _shot(name: String) -> void:
	GameState.set_paused(false)
	await _frames(3)
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://test_results/screens")
	var path := "user://test_results/screens/%s.png" % name
	img.save_png(path)
	print("[Screens] %s" % ProjectSettings.globalize_path(path))
