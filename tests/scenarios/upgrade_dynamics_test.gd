extends Node
## v0.04 upgrades on the real TukController physics (flat ground): you can
## FEEL them, they stay modest, and a fully upgraded tuk is still a tuk —
## it still lifts a wheel when thrown into a hard turn.
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/upgrade_dynamics_test.tscn

const TUK_SCENE := preload("res://scenes/player/player_tuk.tscn")

var tuk: TukController
var base: VehicleTuning
var _failures := 0


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
	base = tuk.tuning
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _reset(kmh: float) -> void:
	tuk.input.throttle = 0.0
	tuk.input.brake = 0.0
	tuk.input.steer = 0.0
	tuk.input.handbrake = false
	tuk.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0)))
	await _frames(20)
	tuk.linear_velocity = Vector3.FORWARD * kmh / 3.6
	await _frames(2)


func _measure(levels: Dictionary) -> Dictionary:
	tuk.tuning = EffectiveVehicleConfig.build(base, levels)
	var out := {}
	# 0 → 50 km/h and top speed after 25 s of full throttle.
	await _reset(0.0)
	tuk.input.throttle = 1.0
	var t := 0.0
	var t50 := -1.0
	while t < 25.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t50 < 0.0 and tuk.speed_kmh >= 50.0:
			t50 = t
	out["t50"] = t50
	out["top"] = tuk.speed_kmh
	# Stopping distance from 50 km/h (full brake, straight).
	await _reset(50.0)
	var start := tuk.global_position
	tuk.input.brake = 1.0
	for i in 600:
		await get_tree().physics_frame
		if tuk.speed_kmh < 1.0:
			break
	out["stop_m"] = Vector2(tuk.global_position.x - start.x, tuk.global_position.z - start.z).length()
	# Hard turn at 62 km/h: high consequence must survive the upgrades.
	await _reset(62.0)
	tuk.input.throttle = 0.6
	tuk.input.steer = 1.0
	var worst := TukController.RollState.STABLE
	for i in 150:
		await get_tree().physics_frame
		worst = maxi(worst, tuk.roll_state) as TukController.RollState
	out["roll"] = worst
	tuk.input.steer = 0.0
	return out


func _run() -> void:
	print("\n=== v0.04 UPGRADES ON THE REAL TUK ===")
	var all5 := {"engine": 5, "brakes": 5, "handling": 5, "suspension": 5}
	var l0 := await _measure({})
	var l5 := await _measure(all5)
	print("  level 0: 0–50 %.2f s, top %.1f km/h, 50→0 in %.1f m, hard turn %s" % [l0["t50"], l0["top"], l0["stop_m"], TukController.RollState.keys()[l0["roll"]]])
	print("  level 5: 0–50 %.2f s, top %.1f km/h, 50→0 in %.1f m, hard turn %s" % [l5["t50"], l5["top"], l5["stop_m"], TukController.RollState.keys()[l5["roll"]]])
	_check("engine: quicker to 50 km/h", float(l5["t50"]) > 0.0 and float(l5["t50"]) < float(l0["t50"]) * 0.95, "%.2f → %.2f s" % [l0["t50"], l5["t50"]])
	_check("engine: top speed ~70 → ~80–85 km/h", float(l0["top"]) > 66.0 and float(l0["top"]) < 73.0 and float(l5["top"]) > 77.0 and float(l5["top"]) <= 86.0,
			"%.1f → %.1f km/h" % [l0["top"], l5["top"]])
	var gain := 1.0 - float(l5["stop_m"]) / float(l0["stop_m"])
	_check("brakes: modestly shorter stops (5–35 %)", gain >= 0.05 and gain <= 0.35, "%.1f → %.1f m (−%.0f %%)" % [l0["stop_m"], l5["stop_m"], gain * 100.0])
	_check("still a tuk: level 5 lifts a wheel in a hard 62 km/h turn", int(l5["roll"]) >= TukController.RollState.TWO_WHEEL,
			TukController.RollState.keys()[l5["roll"]])
	_check("base tuning resource untouched", is_equal_approx(base.top_speed_kmh, 70.0), "%.1f km/h" % base.top_speed_kmh)
	print("\nUPGRADE DYNAMICS: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
