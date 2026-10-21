extends Node3D
## v0.01a high-speed agility and rollover scenarios (flat asphalt pad).
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/vehicle_dynamics_test.tscn
##
## Every scenario starts the tuk already rolling straight at the entry speed,
## lets it settle, then applies a scripted steering programme. Speeds are
## reported in km/h. Results: user://test_results/vehicle_dynamics.json.
## Exit code 1 if an acceptance check fails.

const TUK_SCENE := preload("res://scenes/player/player_tuk.tscn")
const SETTLE := 1.5

var tuk: TukController
var results: Array[Dictionary] = []
var failures := 0

var _queue: Array[Dictionary] = []
var _sc: Dictionary = {}
var _t := 0.0
var _phase_t := 0.0
var _running := false
var _start_x := 0.0
var _m: Dictionary = {}
var _ratio_sum := 0.0
var _ratio_n := 0
## --screenshots (windowed): chase camera + frames during two-wheel / rollover.
var _shots := false
var _shot_taken: Dictionary = {}


func _ready() -> void:
	var ground := StaticBody3D.new()
	ground.set_meta(&"is_ground", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	shape.shape = box
	shape.position = Vector3(0, -1, -1500)
	ground.add_child(shape)
	add_child(ground)
	tuk = TUK_SCENE.instantiate()
	add_child(tuk)
	tuk.get_node("PlayerInput").set("enabled", false)
	tuk.reset_pose_provider = func(_p: Vector3) -> Transform3D: return Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0))
	_shots = OS.get_cmdline_user_args().has("--screenshots")
	if _shots:
		_setup_view()

	# --- Acceptance scenarios (A–E + town stability) ---
	_add("A urban swerve 50", 50.0, [[1.0, 0.45], [-1.0, 0.45], [0.0, 3.0]],
			{"no_tip": true, "min_lateral_m": 2.0, "settles": true})
	_add("B emergency swerve 60", 60.0, [[1.0, 0.55], [-1.0, 0.55], [0.0, 3.0]],
			{"no_tip": true, "min_lateral_m": 2.0, "min_roll": 12.0, "settles": true})
	_add("C top-speed brief swerve 68", 68.0, [[1.0, 0.5], [-0.6, 0.5], [0.0, 3.0]],
			{"no_tip": true, "min_roll": 15.0, "settles": true})
	_add("D top-speed sustained full lock 68", 68.0, [[1.0, 6.0]], {"must_tip": true})
	_add("E two-wheel recovery 66", 66.0, [["until_two_wheel", 1.0, 3.0], [-0.4, 0.6], [0.0, 3.0]],
			{"no_tip": true, "reached_two_wheel": true, "settles": true})
	_add("town lane change 25", 25.0, [[0.6, 0.6], [-0.6, 0.6], [0.0, 2.0]], {"no_two_wheel": true, "no_tip": true})
	_add("town lane change 35", 35.0, [[0.6, 0.6], [-0.6, 0.6], [0.0, 2.0]], {"no_tip": true, "settles": true})
	_add("town sustained half lock 30", 30.0, [[0.5, 5.0], [0.0, 2.0]], {"no_tip": true, "settles": true})

	# --- Report matrices (measured, mostly not asserted) ---
	for kmh in [40.0, 50.0, 60.0, 70.0]:
		_add("rollover sustained full lock %d" % kmh, kmh - (2.0 if kmh >= 70.0 else 0.0), [[1.0, 5.0]],
				{"tip_expected": kmh >= 60.0, "no_tip_expected": kmh <= 40.0}, true)
		_add("rollover lock-then-release %d" % kmh, kmh - (2.0 if kmh >= 70.0 else 0.0),
				[["until_two_wheel", 1.0, 2.5], [0.0, 3.0]], {}, true)
	for kmh in [50.0, 60.0, 70.0]:
		_add("lane change 0.6 %d" % kmh, kmh - (2.0 if kmh >= 70.0 else 0.0),
				[[0.6, 0.6], [-0.6, 0.6], [0.0, 3.0]], {"no_tip": kmh < 70.0, "min_lateral_m": 2.0}, true)
	_next()


func _setup_view() -> void:
	var mats := RoadMaterials.create()
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	plane.mesh = pm
	plane.position = Vector3(0, 0.0, -1500)
	plane.material_override = mats["ground"]
	add_child(plane)
	# Lane-like stripes for motion reference.
	for i in 200:
		for x in [-3.4, 0.0, 3.4]:
			var stripe := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.15, 0.02, 3.0)
			stripe.mesh = bm
			stripe.position = Vector3(x, 0.01, -i * 8.0)
			stripe.material_override = mats["concrete"]
			add_child(stripe)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.64, 0.75, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.66, 0.72)
	add_child(env)
	var cam := ChaseCamera.new()
	cam.config = load("res://resources/vehicles/chase_camera.tres")
	add_child(cam)
	cam.set_target(tuk)
	cam.make_current()
	tuk.was_reset.connect(cam.snap_to_target)


func _capture(tag: String) -> void:
	if not _shots or _shot_taken.has(tag):
		return
	_shot_taken[tag] = true
	DirAccess.make_dir_recursive_absolute("user://test_results/screens")
	var path := "user://test_results/screens/dyn_%s.png" % tag
	get_viewport().get_texture().get_image().save_png(path)
	print("[shot] %s" % ProjectSettings.globalize_path(path))


func _add(label: String, kmh: float, programme: Array, expect: Dictionary, report_only := false) -> void:
	_queue.append({"name": label, "kmh": kmh, "programme": programme, "expect": expect, "report": report_only})


func _next() -> void:
	if _queue.is_empty():
		_finish()
		return
	_sc = _queue.pop_front()
	_t = 0.0
	_phase_t = 0.0
	_running = false
	_ratio_sum = 0.0
	_ratio_n = 0
	_m = {"name": _sc["name"], "entry_kmh": _sc["kmh"], "max_roll_deg": 0.0, "max_lat_g": 0.0,
			"peak_yaw_rate_dps": 0.0, "two_wheel_s": 0.0, "light_s": 0.0, "tipped": false,
			"reached_two_wheel": false}
	tuk.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)))
	tuk.linear_velocity = Vector3(0, 0, -float(_sc["kmh"]) / 3.6)
	_sc["step"] = 0


func _hold(kmh: float) -> void:
	var err := kmh - tuk.speed_kmh
	tuk.input.throttle = clampf(err * 0.4 + 0.3, 0.0, 1.0) if err > -1.0 else 0.0
	tuk.input.brake = 0.0


func _physics_process(delta: float) -> void:
	if _sc.is_empty():
		return
	_t += delta
	tuk.input.handbrake = false
	if not _running:
		_hold(float(_sc["kmh"]))
		tuk.input.steer = 0.0
		if _t >= SETTLE:
			_running = true
			_start_x = tuk.global_position.x
			_m["speed_at_start_kmh"] = snappedf(tuk.speed_kmh, 0.1)
		return
	# Throttle holds entry speed during the manoeuvre (a player keeps it pinned).
	_hold(float(_sc["kmh"]))
	var programme: Array = _sc["programme"]
	var step := int(_sc["step"])
	if step >= programme.size():
		_complete()
		return
	var entry: Array = programme[step]
	_phase_t += delta
	var done_step := false
	if entry[0] is String:
		# ["until_two_wheel", steer, timeout]
		tuk.input.steer = float(entry[1])
		if tuk.roll_state == TukController.RollState.TWO_WHEEL or _phase_t >= float(entry[2]):
			done_step = true
	else:
		tuk.input.steer = float(entry[0])
		if _phase_t >= float(entry[1]):
			done_step = true
	_measure(delta)
	if done_step:
		_sc["step"] = step + 1
		_phase_t = 0.0
		if step == programme.size() - 2 or (programme.size() == 1):
			_m["lateral_m"] = snappedf(absf(tuk.global_position.x - _start_x), 0.01)


func _measure(delta: float) -> void:
	if OS.has_environment("DYN_DEBUG") and String(_sc["name"]).begins_with(OS.get_environment("DYN_DEBUG")) and Engine.get_physics_frames() % 6 == 0:
		print("  t=%.2f roll=%.1f grounded=%d comp F%.3f L%.3f R%.3f load F%.0f L%.0f R%.0f lat=%.2fg v=%.1fkm/h steer=%.1f contactR=%s" % [_phase_t, tuk.roll_deg, tuk.grounded_wheels,
			tuk.wheel_compression[0], tuk.wheel_compression[1], tuk.wheel_compression[2], tuk.wheel_load[0], tuk.wheel_load[1], tuk.wheel_load[2],
			tuk.lateral_accel / 9.81, tuk.speed_kmh, tuk.steer_angle_deg, (tuk.global_transform.affine_inverse() * tuk.wheel_contact[2]).snapped(Vector3(0.01,0.01,0.01))])
	_m["max_roll_deg"] = maxf(float(_m["max_roll_deg"]), absf(tuk.roll_deg))
	_m["max_lat_g"] = maxf(float(_m["max_lat_g"]), absf(tuk.lateral_accel) / 9.81)
	_m["peak_yaw_rate_dps"] = maxf(float(_m["peak_yaw_rate_dps"]), absf(rad_to_deg(tuk.angular_velocity.y)))
	if absf(tuk.roll_deg) > 16.0 and not tuk.is_tipped:
		_capture(String(_sc["name"]).left(1) + "_two_wheel")
	if absf(tuk.roll_deg) > 60.0:
		_capture(String(_sc["name"]).left(1) + "_rolling")
	match tuk.roll_state:
		TukController.RollState.TWO_WHEEL:
			_m["two_wheel_s"] = float(_m["two_wheel_s"]) + delta
			_m["reached_two_wheel"] = true
		TukController.RollState.INSIDE_WHEEL_LIGHT:
			_m["light_s"] = float(_m["light_s"]) + delta
		TukController.RollState.ROLLOVER:
			_m["tipped"] = true
	if tuk.is_tipped:
		_m["tipped"] = true
	# Understeer ratio: actual yaw rate / kinematic (no-slip) yaw rate.
	var delta_rad := absf(deg_to_rad(tuk.steer_angle_deg))
	if delta_rad > deg_to_rad(3.0) and not tuk.is_tipped:
		var kinematic := absf(tuk.forward_speed) * tan(delta_rad) / tuk.tuning.wheelbase
		if kinematic > 0.05:
			_ratio_sum += absf(tuk.angular_velocity.y) / kinematic
			_ratio_n += 1


func _complete() -> void:
	if not _m.has("lateral_m"):
		_m["lateral_m"] = snappedf(absf(tuk.global_position.x - _start_x), 0.01)
	_m["max_roll_deg"] = snappedf(float(_m["max_roll_deg"]), 0.1)
	_m["max_lat_g"] = snappedf(float(_m["max_lat_g"]), 0.01)
	_m["peak_yaw_rate_dps"] = snappedf(float(_m["peak_yaw_rate_dps"]), 0.1)
	_m["two_wheel_s"] = snappedf(float(_m["two_wheel_s"]), 0.01)
	_m["light_s"] = snappedf(float(_m["light_s"]), 0.01)
	_m["understeer_ratio"] = snappedf(_ratio_sum / maxf(_ratio_n, 1.0), 0.01)
	_m["final_roll_deg"] = snappedf(tuk.roll_deg, 0.1)
	_m["final_wheels"] = tuk.grounded_wheels
	_m["exit_kmh"] = snappedf(tuk.speed_kmh, 0.1)
	var settled: bool = not bool(_m["tipped"]) and absf(tuk.roll_deg) < 3.0 and tuk.grounded_wheels == 3
	_m["settled_on_three"] = settled
	var expect: Dictionary = _sc["expect"]
	var checks: Array = []
	var add_check := func(label: String, ok: bool) -> void:
		checks.append({"check": label, "ok": ok})
		if not ok:
			failures += 1
	if expect.get("no_tip", false):
		add_check.call("no rollover", not bool(_m["tipped"]))
	if expect.get("must_tip", false):
		add_check.call("rolls over", bool(_m["tipped"]))
	if expect.has("min_lateral_m"):
		add_check.call("lateral response >= %.1f m" % float(expect["min_lateral_m"]), float(_m["lateral_m"]) >= float(expect["min_lateral_m"]))
	if expect.has("min_roll"):
		add_check.call("roll >= %.0f deg" % float(expect["min_roll"]), float(_m["max_roll_deg"]) >= float(expect["min_roll"]))
	if expect.get("settles", false):
		add_check.call("settles back on three wheels", settled)
	if expect.get("reached_two_wheel", false):
		add_check.call("entered two-wheel state", bool(_m["reached_two_wheel"]))
	if expect.get("no_two_wheel", false):
		add_check.call("never on two wheels", not bool(_m["reached_two_wheel"]))
	if expect.get("tip_expected", false):
		add_check.call("sustained lock rolls at this speed", bool(_m["tipped"]))
	if expect.get("no_tip_expected", false):
		add_check.call("sustained lock does not roll at this speed", not bool(_m["tipped"]))
	_m["checks"] = checks
	results.append(_m)
	_next()


func _finish() -> void:
	print("")
	print("=== VEHICLE DYNAMICS v0.01a (speeds in km/h) ===")
	for r in results:
		print("%-38s entry %3.0f km/h | roll max %5.1f° | lat %.2f g | yaw %5.1f°/s | lateral %5.2f m | 2-wheel %.2f s | light %.2f s | understeer %.2f | tipped %-5s | settled %-5s | exit %4.1f km/h" % [
			r["name"], r["entry_kmh"], r["max_roll_deg"], r["max_lat_g"], r["peak_yaw_rate_dps"], r["lateral_m"],
			r["two_wheel_s"], r["light_s"], r["understeer_ratio"], r["tipped"], r["settled_on_three"], r["exit_kmh"]])
		for c in r["checks"]:
			print("      [%s] %s" % ["PASS" if c["ok"] else "FAIL", c["check"]])
	print("=== %s (%d failed checks) ===" % ["PASS" if failures == 0 else "FAIL", failures])
	DirAccess.make_dir_recursive_absolute("user://test_results")
	var f := FileAccess.open("user://test_results/vehicle_dynamics.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(results, "\t"))
		f.close()
	get_tree().quit(1 if failures > 0 else 0)
