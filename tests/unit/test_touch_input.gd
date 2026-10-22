extends "res://tests/test_case.gd"
## v0.03A touch steering mapping and multitouch bookkeeping (pure logic).


var _cfg: TouchControlsConfig = load("res://resources/input/touch_controls.tres")


func _state() -> TouchControlState:
	var s := TouchControlState.new(_cfg)
	s.rects = MobileLayout.compute(Vector2(1280, 720), Rect2(0, 0, 1280, 720), _cfg)
	var steer: Rect2 = s.rects[TouchControlState.Pad.STEER]
	s.steer_center_x = steer.get_center().x
	s.steer_half_width = steer.size.x * 0.5
	return s


func _center(s: TouchControlState, c: int) -> Vector2:
	return (s.rects[c] as Rect2).get_center()


func test_mapper_dead_zone_and_centre() -> void:
	check_eq(TouchSteeringMapper.map(0.0, 150.0, _cfg), 0.0, "centre = 0")
	var inside := 150.0 * _cfg.full_lock_fraction * _cfg.steer_dead_zone * 0.9
	check_eq(TouchSteeringMapper.map(inside, 150.0, _cfg), 0.0, "inside dead zone = 0")
	check_eq(TouchSteeringMapper.map(-inside, 150.0, _cfg), 0.0, "inside dead zone (left) = 0")
	var just_out := 150.0 * _cfg.full_lock_fraction * (_cfg.steer_dead_zone + 0.02)
	var v := TouchSteeringMapper.map(just_out, 150.0, _cfg)
	check(v > 0.0 and v < 0.05, "just outside dead zone is a small positive value (%.3f)" % v)


func test_mapper_clamps_to_full_lock() -> void:
	check_near(TouchSteeringMapper.map(150.0 * _cfg.full_lock_fraction, 150.0, _cfg), 1.0, 0.001, "full lock at full_lock_fraction")
	check_eq(TouchSteeringMapper.map(1000.0, 150.0, _cfg), 1.0, "beyond the pad clamps to +1")
	check_eq(TouchSteeringMapper.map(-1000.0, 150.0, _cfg), -1.0, "beyond the pad clamps to -1")


func test_mapper_is_symmetric_monotonic_and_mostly_linear() -> void:
	var prev := -2.0
	for i in range(-20, 21):
		var x := float(i) / 20.0 * 150.0
		var v := TouchSteeringMapper.map(x, 150.0, _cfg)
		check(v >= prev, "monotonic at %.0f" % x)
		check_near(v, -TouchSteeringMapper.map(-x, 150.0, _cfg), 0.0001, "symmetric at %.0f" % x)
		prev = v
	# Mild centre softening only: half travel gives close to half output.
	var half := TouchSteeringMapper.map(150.0 * _cfg.full_lock_fraction * 0.5, 150.0, _cfg)
	check(half > 0.38 and half < 0.5, "half travel ≈ half lock (%.3f)" % half)


func test_quick_reversal_has_no_hysteresis() -> void:
	var s := _state()
	var c := _center(s, TouchControlState.Pad.STEER)
	s.press(0, c + Vector2(s.steer_half_width, 0))
	check_eq(s.steer, 1.0, "full right")
	s.drag(0, c - Vector2(s.steer_half_width, 0))
	check_eq(s.steer, -1.0, "one drag event later: full left")
	s.release(0)
	check_eq(s.steer, 0.0, "release returns input to 0 (vehicle steering rate smooths the wheel)")


func test_multitouch_steer_with_throttle_and_brake() -> void:
	var s := _state()
	var steer_c := _center(s, TouchControlState.Pad.STEER)
	check_eq(s.press(0, steer_c + Vector2(40, 0)), TouchControlState.Pad.STEER, "finger 0 steers")
	check_eq(s.press(1, _center(s, TouchControlState.Pad.ACCELERATE)), TouchControlState.Pad.ACCELERATE, "finger 1 accelerates")
	check(s.steer > 0.0 and s.throttle() == 1.0, "steer + throttle together")
	check_eq(s.active_touch_count(), 2, "two touches tracked")
	s.release(1)
	check_eq(s.press(2, _center(s, TouchControlState.Pad.BRAKE)), TouchControlState.Pad.BRAKE, "finger 2 brakes")
	check(s.steer > 0.0 and s.brake() == 1.0 and s.throttle() == 0.0, "steer + brake together")
	s.drag(0, steer_c - Vector2(60, 0))
	check(s.steer < 0.0, "steering still follows finger 0 while braking")
	check_eq(s.brake(), 1.0, "brake still held")


func test_steering_finger_keeps_steering_when_sliding_off_pad() -> void:
	var s := _state()
	s.press(0, _center(s, TouchControlState.Pad.STEER))
	s.drag(0, _center(s, TouchControlState.Pad.BRAKE))
	check_eq(s.brake(), 0.0, "sliding the steering thumb onto BRAKE does not brake")
	check_eq(s.steer, 1.0, "it just steers fully right")
	check_eq(s.press(1, _center(s, TouchControlState.Pad.STEER)), TouchControlState.Pad.NONE, "a second finger cannot steal the steering")


func test_taps_are_reported_once() -> void:
	var s := _state()
	s.press(0, _center(s, TouchControlState.Pad.HORN))
	s.release(0)
	s.press(1, _center(s, TouchControlState.Pad.PAUSE))
	var taps := s.take_pending()
	check(taps.has(TouchControlState.Pad.HORN) and taps.has(TouchControlState.Pad.PAUSE), "horn and pause taps queued")
	check(s.take_pending().is_empty(), "taps are consumed")


func test_accept_only_when_available() -> void:
	var s := _state()
	var p := _center(s, TouchControlState.Pad.ACCEPT)
	s.accept_available = false
	check(s.control_at(p) != TouchControlState.Pad.ACCEPT, "hidden ACCEPT cannot be pressed")
	s.accept_available = true
	check_eq(s.press(0, p), TouchControlState.Pad.ACCEPT, "visible ACCEPT can be pressed")
	check(s.take_pending().has(TouchControlState.Pad.ACCEPT), "accept tap queued")


func test_cancel_all_releases_everything() -> void:
	var s := _state()
	s.press(0, _center(s, TouchControlState.Pad.STEER) + Vector2(50, 0))
	s.press(1, _center(s, TouchControlState.Pad.ACCELERATE))
	s.press(2, _center(s, TouchControlState.Pad.HORN))
	s.cancel_all()
	check_eq(s.steer, 0.0, "steer released")
	check_eq(s.throttle(), 0.0, "throttle released")
	check_eq(s.active_touch_count(), 0, "no touches held")
	check(s.take_pending().is_empty(), "pending taps dropped")


func test_touches_outside_controls_are_ignored() -> void:
	var s := _state()
	check_eq(s.press(0, Vector2(640, 200)), TouchControlState.Pad.NONE, "screen centre is not a control")
	check_eq(s.active_touch_count(), 0, "nothing held")
