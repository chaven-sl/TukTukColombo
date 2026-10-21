extends Node3D
## Reproducible handling scenarios for the player tuk on a flat test pad.
##
## Run headless (deterministic fixed step):
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/vehicle_handling_test.tscn
##
## Each scenario drives the tuk with scripted inputs, records metrics, and
## checks loose acceptance ranges. Results print as a table and are written to
## user://test_results/vehicle_handling.json. Exit code 1 on any failure.

const TUK_SCENE := preload("res://scenes/player/player_tuk.tscn")
const DT := 1.0 / 60.0

var tuk: TukController
var results: Array[Dictionary] = []
var failures := 0

var _scenarios: Array[Callable] = []
var _scenario_index := -1
var _t := 0.0
var _phase := 0
var _m: Dictionary = {}
var _start_pos := Vector3.ZERO
var _yaw_samples := PackedFloat32Array()


func _ready() -> void:
	_build_pad()
	tuk = TUK_SCENE.instantiate()
	add_child(tuk)
	tuk.get_node("PlayerInput").set("enabled", false)
	_scenarios = [
		_sc_settle, _sc_acceleration, _sc_braking, _sc_reverse, _sc_low_speed_turn,
		_sc_moderate_turn_30, _sc_full_lock_30, _sc_half_lock_60, _sc_full_lock_65,
		_sc_flick_60, _sc_slalom_recovery, _sc_kerb_strike, _sc_reset_after_tip,
	]
	_next_scenario()


func _build_pad() -> void:
	var ground := StaticBody3D.new()
	ground.set_meta(&"is_ground", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6000, 2, 6000)
	shape.shape = box
	shape.position = Vector3(0, -1, 0)
	ground.add_child(shape)
	add_child(ground)
	# Kerb strip for the kerb scenario: 0.15 m high, chamfered like the road kerbs.
	var kerb := StaticBody3D.new()
	var kerb_shape := CollisionShape3D.new()
	var poly := ConvexPolygonShape3D.new()
	poly.points = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0.1, 0.15, 0), Vector3(0.35, 0.15, 0), Vector3(0.35, 0, 0),
		Vector3(0, 0, -200), Vector3(0.1, 0.15, -200), Vector3(0.35, 0.15, -200), Vector3(0.35, 0, -200),
	])
	kerb_shape.shape = poly
	kerb.add_child(kerb_shape)
	kerb.position = Vector3(-500, 0, 0)
	add_child(kerb)


func _start(name: String, pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0))) -> void:
	_m = {"name": name}
	_t = 0.0
	_phase = 0
	_yaw_samples.clear()
	tuk.teleport(pose)
	_start_pos = pose.origin


func _next_scenario() -> void:
	_scenario_index += 1
	if _scenario_index >= _scenarios.size():
		_finish()
		return
	_t = 0.0
	_phase = -1


func _physics_process(_delta: float) -> void:
	if _scenario_index < 0 or _scenario_index >= _scenarios.size():
		return
	var done: bool = _scenarios[_scenario_index].call()
	_t += DT
	if done:
		results.append(_m)
		_next_scenario()


# --- Helpers ---

func _hold_speed(target_kmh: float) -> void:
	var err := target_kmh - tuk.speed_kmh
	tuk.input.throttle = clampf(err * 0.4 + 0.3, 0.0, 1.0) if err > -1.0 else 0.0
	tuk.input.brake = clampf(-err * 0.15, 0.0, 1.0) if err < -3.0 else 0.0


func _track_extremes() -> void:
	_m["max_roll_deg"] = maxf(float(_m.get("max_roll_deg", 0.0)), absf(tuk.roll_deg))
	_m["max_pitch_deg"] = maxf(float(_m.get("max_pitch_deg", 0.0)), absf(tuk.pitch_deg))
	_m["min_grounded"] = mini(int(_m.get("min_grounded", 3)), tuk.grounded_wheels)
	if tuk.is_tipped:
		_m["tipped"] = true


func _check(key: String, ok: bool, detail: String) -> void:
	var checks: Array = _m.get("checks", [])
	checks.append({"check": key, "ok": ok, "detail": detail})
	_m["checks"] = checks
	if not ok:
		failures += 1


# --- Scenarios (return true when finished) ---

func _sc_settle() -> bool:
	if _phase == -1:
		_start("settle_at_rest")
		_phase = 0
	tuk.input.clear()
	if _t >= 2.0:
		_m["compression_front"] = snappedf(tuk.wheel_compression[0], 0.001)
		_m["compression_rear"] = snappedf(tuk.wheel_compression[1], 0.001)
		_m["drift_m"] = snappedf(tuk.global_position.distance_to(_start_pos) - 0.3, 0.01)
		_check("grounded", tuk.grounded_wheels == 3, "%d wheels" % tuk.grounded_wheels)
		_check("static sag in travel", tuk.wheel_compression[0] > 0.03 and tuk.wheel_compression[0] < 0.18, str(_m["compression_front"]))
		return true
	return false


func _sc_acceleration() -> bool:
	if _phase == -1:
		_start("acceleration_full_throttle")
		_phase = 0
	tuk.input.clear()
	tuk.input.throttle = 1.0
	_track_extremes()
	if not _m.has("t_0_40") and tuk.speed_kmh >= 40.0:
		_m["t_0_40"] = snappedf(_t, 0.01)
	if not _m.has("t_0_60") and tuk.speed_kmh >= 60.0:
		_m["t_0_60"] = snappedf(_t, 0.01)
	if _t >= 5.0 and not _m.has("speed_5s"):
		_m["speed_5s"] = snappedf(tuk.speed_kmh, 0.1)
	if _t >= 40.0:
		_m["top_speed_kmh"] = snappedf(tuk.speed_kmh, 0.1)
		var t040 := float(_m.get("t_0_40", 99.0))
		_check("0-40 km/h in 5.0-7.5 s", t040 >= 5.0 and t040 <= 7.5, "%.2f s" % t040)
		_check("top speed 64-74 km/h", tuk.speed_kmh >= 64.0 and tuk.speed_kmh <= 74.0, "%.1f" % tuk.speed_kmh)
		return true
	return false


func _sc_braking() -> bool:
	if _phase == -1:
		_start("braking_from_50")
		_phase = 0
	tuk.input.clear()
	if _phase == 0:
		tuk.input.throttle = 1.0
		if tuk.speed_kmh >= 50.0:
			_phase = 1
			_m["brake_start_kmh"] = snappedf(tuk.speed_kmh, 0.1)
			_m["_brake_pos"] = tuk.global_position
			_m["_brake_t"] = _t
		return false
	tuk.input.brake = 1.0
	_track_extremes()
	if tuk.speed_kmh < 0.5:
		var start: Vector3 = _m["_brake_pos"]
		var dist := Vector2(tuk.global_position.x - start.x, tuk.global_position.z - start.z).length()
		_m["stop_distance_m"] = snappedf(dist, 0.1)
		_m["stop_time_s"] = snappedf(_t - float(_m["_brake_t"]), 0.01)
		_m.erase("_brake_pos")
		_m.erase("_brake_t")
		_check("stops within 22 m", dist < 22.0, "%.1f m" % dist)
		_check("visible nose dive", float(_m.get("max_pitch_deg", 0.0)) > 0.8, "%.2f deg" % float(_m.get("max_pitch_deg", 0.0)))
		_check("stays upright", not _m.has("tipped"), "")
		return true
	if _t > 30.0:
		_check("stops", false, "timeout")
		return true
	return false


func _sc_reverse() -> bool:
	if _phase == -1:
		_start("reverse")
		_phase = 0
	tuk.input.clear()
	tuk.input.brake = 1.0
	_m["min_forward_speed_kmh"] = minf(float(_m.get("min_forward_speed_kmh", 0.0)), tuk.forward_speed * 3.6)
	if _t >= 5.0:
		var v := float(_m["min_forward_speed_kmh"])
		_m["min_forward_speed_kmh"] = snappedf(v, 0.1)
		_check("reverses to 8-15 km/h", v <= -8.0 and v >= -15.0, "%.1f km/h" % v)
		return true
	return false


func _turn_scenario(name: String, speed_kmh: float, steer: float, hold_time: float, expect_upright: bool) -> bool:
	if _phase == -1:
		_start(name)
		_phase = 0
	tuk.input.clear()
	if _phase == 0:
		_hold_speed(speed_kmh)
		if absf(tuk.speed_kmh - speed_kmh) < 1.0 and _t > 3.0:
			_phase = 1
			_m["_turn_t"] = _t
			_m["entry_kmh"] = snappedf(tuk.speed_kmh, 0.1)
		if _t > 30.0:
			_check("reached entry speed", false, "%.1f" % tuk.speed_kmh)
			return true
		return false
	var elapsed := _t - float(_m["_turn_t"])
	tuk.input.steer = steer
	tuk.input.throttle = clampf((speed_kmh - tuk.speed_kmh) * 0.4 + 0.3, 0.0, 1.0)
	_track_extremes()
	if elapsed > hold_time * 0.5 and not tuk.is_tipped:
		var yaw_rate := absf(tuk.angular_velocity.y)
		if yaw_rate > 0.05:
			_yaw_samples.append(absf(tuk.forward_speed) / yaw_rate)
		_m["max_lat_g"] = maxf(float(_m.get("max_lat_g", 0.0)), absf(tuk.lateral_accel) / 9.81)
	if elapsed >= hold_time:
		_m.erase("_turn_t")
		if _yaw_samples.size() > 0:
			var total := 0.0
			for r in _yaw_samples:
				total += r
			_m["turn_radius_m"] = snappedf(total / _yaw_samples.size(), 0.1)
		_m["max_roll_deg"] = snappedf(float(_m.get("max_roll_deg", 0.0)), 0.1)
		_m["max_lat_g"] = snappedf(float(_m.get("max_lat_g", 0.0)), 0.01)
		_m["exit_kmh"] = snappedf(tuk.speed_kmh, 0.1)
		if expect_upright:
			_check("stays upright", not _m.has("tipped"), "max roll %.1f" % float(_m["max_roll_deg"]))
		_check("visible body roll >= 2 deg", float(_m["max_roll_deg"]) >= 2.0, "%.1f" % float(_m["max_roll_deg"]))
		return true
	return false


func _sc_low_speed_turn() -> bool:
	var done := _turn_scenario("low_speed_full_lock_12kmh", 12.0, 1.0, 6.0, true)
	if done and _m.has("turn_radius_m"):
		_check("tight turning circle < 5 m radius", float(_m["turn_radius_m"]) < 5.0, str(_m["turn_radius_m"]))
	return done


func _sc_moderate_turn_30() -> bool:
	return _turn_scenario("moderate_turn_half_lock_30kmh", 30.0, 0.5, 5.0, true)


func _sc_full_lock_30() -> bool:
	return _turn_scenario("full_lock_30kmh", 30.0, 1.0, 4.0, false)


func _sc_half_lock_60() -> bool:
	return _turn_scenario("half_lock_60kmh", 60.0, 0.5, 4.0, false)


func _sc_full_lock_65() -> bool:
	return _turn_scenario("full_lock_65kmh_extreme", 65.0, 1.0, 3.0, false)


## Aggressive full-lock flick left->right at 60 km/h: documents tipping risk.
func _sc_flick_60() -> bool:
	if _phase == -1:
		_start("flick_full_lock_60kmh")
		_phase = 0
	tuk.input.clear()
	if _phase == 0:
		_hold_speed(60.0)
		if absf(tuk.speed_kmh - 60.0) < 1.5 and _t > 3.0:
			_phase = 1
			_m["_t0"] = _t
		return false
	var elapsed := _t - float(_m["_t0"])
	tuk.input.throttle = 0.6
	tuk.input.steer = -1.0 if elapsed < 0.8 else (1.0 if elapsed < 1.8 else 0.0)
	_track_extremes()
	if elapsed >= 5.0:
		_m.erase("_t0")
		_m["max_roll_deg"] = snappedf(float(_m.get("max_roll_deg", 0.0)), 0.1)
		_m["tipped"] = _m.get("tipped", false)
		_check("high-speed flick is risky (roll > 18 deg or tip)", float(_m["max_roll_deg"]) > 18.0 or bool(_m["tipped"]),
				"roll %.1f tipped %s" % [float(_m["max_roll_deg"]), _m["tipped"]])
		return true
	return false


func _sc_slalom_recovery() -> bool:
	if _phase == -1:
		_start("slalom_45kmh_recovery")
		_phase = 0
	tuk.input.clear()
	if _phase == 0:
		_hold_speed(45.0)
		if absf(tuk.speed_kmh - 45.0) < 1.0 and _t > 3.0:
			_phase = 1
			_m["_t0"] = _t
		return false
	var elapsed := _t - float(_m["_t0"])
	tuk.input.throttle = clampf((45.0 - tuk.speed_kmh) * 0.4 + 0.3, 0.0, 1.0)
	if elapsed < 6.0:
		tuk.input.steer = 0.7 if fmod(elapsed, 2.0) < 1.0 else -0.7
		_track_extremes()
	else:
		tuk.input.steer = 0.0
	if elapsed >= 9.0:
		_m.erase("_t0")
		_m["max_roll_deg"] = snappedf(float(_m.get("max_roll_deg", 0.0)), 0.1)
		_m["final_roll_deg"] = snappedf(tuk.roll_deg, 0.1)
		_m["final_yaw_rate"] = snappedf(tuk.angular_velocity.y, 0.01)
		_check("recovers upright", not _m.has("tipped") and absf(tuk.roll_deg) < 3.0, "roll %.1f" % tuk.roll_deg)
		_check("yaw settles", absf(tuk.angular_velocity.y) < 0.15, "%.2f rad/s" % tuk.angular_velocity.y)
		return true
	return false


func _sc_kerb_strike() -> bool:
	if _phase == -1:
		# Approach the kerb strip at 20 degrees from the road side.
		var heading := Basis(Vector3.UP, deg_to_rad(-20.0))
		_start("kerb_strike_25kmh", Transform3D(heading, Vector3(-500 - 25.0, 0.3, -20.0)))
		_phase = 0
	tuk.input.clear()
	if tuk.global_position.x < -501.0:
		_hold_speed(25.0)
	else:
		tuk.input.throttle = 0.3
	_track_extremes()
	_m["max_compression"] = maxf(float(_m.get("max_compression", 0.0)), maxf(tuk.wheel_compression[1], tuk.wheel_compression[2]))
	if tuk.global_position.x > -498.0 or _t > 20.0:
		_m["max_roll_deg"] = snappedf(float(_m.get("max_roll_deg", 0.0)), 0.1)
		_m["max_pitch_deg"] = snappedf(float(_m.get("max_pitch_deg", 0.0)), 0.1)
		_m["max_compression"] = snappedf(float(_m["max_compression"]), 0.001)
		_m["speed_after_kmh"] = snappedf(tuk.speed_kmh, 0.1)
		_check("crossed kerb", tuk.global_position.x > -498.0, "x %.1f" % tuk.global_position.x)
		_check("noticeable disturbance", float(_m["max_roll_deg"]) > 2.0 or float(_m["max_pitch_deg"]) > 1.5,
				"roll %.1f pitch %.1f" % [float(_m["max_roll_deg"]), float(_m["max_pitch_deg"])])
		_check("recoverable (no tip)", not _m.has("tipped"), "")
		return true
	return false


func _sc_reset_after_tip() -> bool:
	if _phase == -1:
		# Start on its side, then press reset.
		_start("reset_from_side", Transform3D(Basis(Vector3.BACK, deg_to_rad(85.0)), Vector3(0, 1.0, 0)))
		_phase = 0
	tuk.input.clear()
	if _phase == 0 and _t > 1.0:
		_m["was_tipped"] = tuk.is_tipped
		tuk.reset_pose_provider = func(_p: Vector3) -> Transform3D: return Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0))
		tuk.request_reset()
		_phase = 1
		_m["_t0"] = _t
	if _phase == 1 and _t - float(_m["_t0"]) > 1.5:
		_m.erase("_t0")
		var upright := tuk.global_transform.basis.y.dot(Vector3.UP) > 0.98
		_check("was on its side", bool(_m["was_tipped"]), "")
		_check("upright after reset", upright and tuk.grounded_wheels == 3, "up.y %.3f" % tuk.global_transform.basis.y.y)
		return true
	return false


func _finish() -> void:
	print("")
	print("=== VEHICLE HANDLING (PROTOTYPE BASELINE) ===")
	for r in results:
		var parts := PackedStringArray()
		for key in r.keys():
			if key == "name" or key == "checks":
				continue
			parts.append("%s=%s" % [key, r[key]])
		print("%-32s %s" % [r["name"], ", ".join(parts)])
		for c in r.get("checks", []):
			print("    [%s] %s %s" % ["PASS" if c["ok"] else "FAIL", c["check"], c["detail"]])
	print("=== %s (%d failed checks) ===" % ["PASS" if failures == 0 else "FAIL", failures])
	DirAccess.make_dir_recursive_absolute("user://test_results")
	var f := FileAccess.open("user://test_results/vehicle_handling.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(results, "\t"))
		f.close()
	get_tree().quit(1 if failures > 0 else 0)
