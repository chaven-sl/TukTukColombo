extends "res://tests/test_case.gd"


func test_steering_curve_matches_design_targets() -> void:
	# v0.01a targets (human playtest: keep high-speed steering useful).
	var t := load("res://resources/vehicles/tuk_player_tuning.tres") as VehicleTuning
	check(t != null, "player tuning resource loads")
	var at10 := t.steer_limit_deg(10.0)
	check(at10 >= 35.0 and at10 <= 36.0, "<=15 km/h: 35-36 deg (%.1f)" % at10)
	var at30 := t.steer_limit_deg(30.0)
	check(at30 >= 28.0 and at30 <= 30.0, "30 km/h: 28-30 deg (%.1f)" % at30)
	var at50 := t.steer_limit_deg(50.0)
	check(at50 >= 20.0 and at50 <= 22.0, "50 km/h: 20-22 deg (%.1f)" % at50)
	var at60 := t.steer_limit_deg(60.0)
	check(at60 >= 18.0 and at60 <= 20.0, "60 km/h: 18-20 deg (%.1f)" % at60)
	var at70 := t.steer_limit_deg(70.0)
	check(at70 >= 15.0 and at70 <= 17.0, "70 km/h: 15-17 deg (%.1f)" % at70)


func test_steering_blend_is_smooth_and_monotonic() -> void:
	var t := VehicleTuning.new()
	var previous := t.steer_limit_deg(0.0)
	var max_step := 0.0
	for kmh in range(1, 81):
		var angle := t.steer_limit_deg(float(kmh))
		check(angle <= previous + 0.0001, "monotonic at %d km/h" % kmh)
		max_step = maxf(max_step, previous - angle)
		previous = angle
	check(max_step < 2.0, "no abrupt clamp step (largest 1 km/h change %.2f deg)" % max_step)


func test_drive_curve_governs_top_speed() -> void:
	var t := VehicleTuning.new()
	check_near(t.drive_curve(0.0), 1.0, 0.0001, "full traction-limited force from rest")
	check(t.drive_curve(15.0) < 1.0, "power-limited at speed")
	check_near(t.drive_curve(t.top_speed_kmh / 3.6), 0.0, 0.0001, "no drive at governed top speed")


func test_roll_assist_fades_with_speed() -> void:
	var t := VehicleTuning.new()
	check(t.roll_assist_at(10.0) > t.roll_assist_at(40.0), "weaker at 40 than at 10")
	check(t.roll_assist_at(40.0) > t.roll_assist_at(70.0), "weakest at high speed")
	check_near(t.roll_assist_at(80.0), t.roll_assist_high_speed, 0.001, "clamped above fade end")
