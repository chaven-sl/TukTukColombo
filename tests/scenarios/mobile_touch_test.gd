extends Node
## v0.03A touch + lifecycle scenarios in the real prototype scene.
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/mobile_touch_test.tscn
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/mobile_touch_test.tscn -- --force-touch-controls
##
## Touches are injected as InputEventScreenTouch/Drag through Input, the same
## path an Android device uses. Ambient traffic and people are off so the
## checks are deterministic; passengers stay on.

const MAIN := preload("res://scenes/prototype/prototype_main.tscn")

var main: Node3D
var player: TukController
var rides: RideManager
var offers: PassengerOfferManager
var road: RoadNetwork
var pause: PauseController
var controls: MobileControls
var _failures := 0
var _horns := 0


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
	main.set("human_seed", 21)
	main.set("offer_seed", 22)
	add_child(main)
	player = main.get_node("PlayerTuk")
	rides = main.get_node("RideManager")
	offers = main.get_node("PassengerOfferManager")
	road = main.get_node("TestTrack")
	pause = main.get_node("Pause")
	controls = main.get_node("MobileControls")
	EventBus.horn_sounded.connect(func(_p: Vector3) -> void: _horns += 1)
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	get_viewport().push_input(ev, true)


func _drag(index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	get_viewport().push_input(ev, true)


func _center(c: int) -> Vector2:
	return (controls.rects[c] as Rect2).get_center()


func _tap(c: int) -> void:
	_touch(9, _center(c), true)
	await _frames(2)
	_touch(9, _center(c), false)
	await _frames(2)


func _teleport_on_road(near: Vector3) -> void:
	player.teleport(road.find_reset_transform(near))
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO


func _run() -> void:
	await _frames(5)
	if OS.get_cmdline_user_args().has(InputMode.CLI_FLAG):
		print("=== Forced touch controls ===")
		_check("forced: touch mode on", main.get("touch_mode") == true)
		_check("forced: touch HUD visible", controls.visible)
		_check("forced: keyboard source disabled", not player.get_node("PlayerInput").get("enabled"))
		_finish()
		return

	print("=== Desktop default ===")
	_check("touch HUD hidden on desktop", not controls.visible and main.get("touch_mode") == false)
	_check("keyboard source active", player.get_node("PlayerInput").get("enabled") == true)
	_check("touch source inactive", not (main.get_node("TouchInput") as TouchInputSource).enabled)

	print("=== Touch mode: one human input source ===")
	main.call("set_touch_mode", true)
	await _frames(1)
	_check("touch HUD visible", controls.visible)
	_check("keyboard source disabled", player.get_node("PlayerInput").get("enabled") == false)
	_check("layout has every control", controls.rects.size() == 6)

	print("=== Multitouch: steer + accelerate ===")
	var spawn := player.global_transform
	var yaw0 := player.global_transform.basis.get_euler().y
	var steer_c := _center(TouchControlState.Pad.STEER)
	_touch(0, steer_c, true)
	_touch(1, _center(TouchControlState.Pad.ACCELERATE), true)
	await _frames(2)
	_drag(0, steer_c + Vector2(controls.state.steer_half_width * 0.6, 0))
	await _frames(150)
	_check("steer input positive (right)", player.input.steer > 0.3, "steer %.2f" % player.input.steer)
	_check("throttle held", player.input.throttle == 1.0)
	_check("tuk accelerated", player.speed_kmh > 15.0, "%.1f km/h" % player.speed_kmh)
	var yaw1 := player.global_transform.basis.get_euler().y
	_check("tuk turned right", wrapf(yaw1 - yaw0, -PI, PI) < -0.05, "Δyaw %.2f rad" % wrapf(yaw1 - yaw0, -PI, PI))

	print("=== Quick reversal ===")
	_drag(0, steer_c - Vector2(controls.state.steer_half_width, 0))
	await _frames(2)
	_check("full opposite lock in one drag", player.input.steer == -1.0, "steer %.2f" % player.input.steer)
	_drag(0, steer_c)

	print("=== Brake while steering ===")
	_touch(1, _center(TouchControlState.Pad.ACCELERATE), false)
	var before := player.speed_kmh
	_touch(2, _center(TouchControlState.Pad.BRAKE), true)
	await _frames(60)
	_check("brake held with steering thumb down", player.input.brake == 1.0 and player.input.throttle == 0.0)
	_check("tuk slowed", player.speed_kmh < before - 5.0, "%.1f → %.1f km/h" % [before, player.speed_kmh])
	_touch(2, _center(TouchControlState.Pad.BRAKE), false)
	_touch(0, steer_c, false)
	await _frames(2)
	_check("all released → neutral input", player.input.steer == 0.0 and player.input.throttle == 0.0 and player.input.brake == 0.0)

	print("=== Horn ===")
	var horns := _horns
	await _tap(TouchControlState.Pad.HORN)
	_check("horn tap sounds the horn once", _horns == horns + 1, "%d" % (_horns - horns))

	print("=== Pause button and Android Back ===")
	await _tap(TouchControlState.Pad.PAUSE)
	_check("pause button pauses", get_tree().paused)
	pause.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(2)
	_check("Back on pause screen resumes", not get_tree().paused)
	pause.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(2)
	_check("Back during gameplay pauses (never quits)", get_tree().paused and is_inside_tree())
	_check("quit_on_go_back is off", not get_tree().quit_on_go_back)
	GameState.set_paused(false)
	await _frames(2)

	print("=== Focus loss ===")
	player.teleport(spawn)
	_touch(1, _center(TouchControlState.Pad.ACCELERATE), true)
	await _frames(10)
	var ride_state := rides.state
	pause.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	controls.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(90)
	_check("focus loss pauses", get_tree().paused)
	_check("no auto-resume after 1.5 s", get_tree().paused)
	_check("held throttle cancelled", controls.state.active_touch_count() == 0 and controls.state.throttle() == 0.0)
	_check("ride state untouched", rides.state == ride_state)
	_touch(1, _center(TouchControlState.Pad.ACCELERATE), false)
	GameState.set_paused(false)
	await _frames(5)
	_check("no stuck throttle after resume", player.input.throttle == 0.0)

	print("=== ACCEPT RIDE via touch ===")
	var offer: PassengerOffer = null
	for o in offers.offers:
		if o.state == PassengerOffer.State.AVAILABLE and o.passenger != null:
			offer = o
			break
	_check("an offer is available", offer != null)
	if offer != null:
		_teleport_on_road(offer.passenger.global_position)
		await _frames(30)
		_check("offer nearby", rides.nearby_offer != null)
		_check("ACCEPT button shown", (controls.get("_panels")[TouchControlState.Pad.ACCEPT] as Panel).visible)
		await _tap(TouchControlState.Pad.ACCEPT)
		var accepted := rides.state == RideManager.RideState.EN_ROUTE_TO_PICKUP or rides.state == RideManager.RideState.BOARDING
		_check("touch accept uses RideManager path", accepted, RideManager.RideState.keys()[rides.state])

	print("=== Route direction regression (no U-turn at pickup) ===")
	var drops := (main.get_node("TestTrack/Pedestrians") as PedestrianNetwork).spots_of_kind(PedestrianSpot.Kind.DROPOFF)
	for o in offers.offers:
		for spot in drops:
			var r := road.route(o.pickup.global_position, spot.global_position)
			var straight := o.pickup.global_position.distance_to(spot.global_position)
			var ok := bool(r["restricted"]) and float(r["distance"]) < INF
			# Driving off along the kerb lane, the remaining distance matches the quote.
			var again := road.route(o.pickup.global_position, spot.global_position, r["start_dir"])
			ok = ok and absf(float(again["distance"]) - float(r["distance"])) < 1.0
			_check("%s → %s follows kerb direction" % [o.profile.id, spot.name], ok,
					"%.0f m (straight %.0f m)" % [float(r["distance"]), straight])
	_finish()


func _finish() -> void:
	GameState.set_paused(false)
	print("")
	print("=== MOBILE TOUCH: %s — %d failures ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
