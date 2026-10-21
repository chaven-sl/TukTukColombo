extends "res://tests/test_case.gd"


func _budget() -> AdaptiveTrafficBudget:
	var cfg := TrafficBudgetConfig.new()
	cfg.min_ceiling = 8
	cfg.max_ceiling = 20
	cfg.initial_ceiling = 14
	cfg.low_fps_threshold = 27.0
	cfg.high_fps_threshold = 50.0
	cfg.low_sustain_seconds = 3.0
	cfg.high_sustain_seconds = 10.0
	cfg.step_down = 2
	cfg.step_up = 1
	cfg.change_cooldown = 4.0
	cfg.sample_window = 0.5
	return AdaptiveTrafficBudget.new(cfg, 14)


func _run(budget: AdaptiveTrafficBudget, fps: float, seconds: float) -> void:
	var frames := int(fps * seconds)
	for i in frames:
		budget.push_frame(1.0 / fps)


func test_actual_target_is_min_of_density_and_ceiling() -> void:
	var b := _budget()
	check_eq(b.get_actual_target(), 14, "starts at density target")
	b.set_density_target(10)
	check_eq(b.get_actual_target(), 10, "density below ceiling wins")


func test_brief_dip_does_not_reduce() -> void:
	var b := _budget()
	_run(b, 60.0, 5.0)
	_run(b, 20.0, 2.0)
	_run(b, 60.0, 2.0)
	check_eq(b.performance_ceiling, 14, "2 s dip below 27 FPS ignored")


func test_sustained_low_fps_steps_down_gradually() -> void:
	var b := _budget()
	_run(b, 20.0, 3.6)
	check_eq(b.performance_ceiling, 12, "one step down after ~3 s")
	_run(b, 20.0, 2.0)
	check_eq(b.performance_ceiling, 12, "cooldown prevents an immediate second step")
	_run(b, 20.0, 30.0)
	check_eq(b.performance_ceiling, 8, "never below min ceiling")
	check_eq(b.get_actual_target(), 8, "target follows ceiling")


func test_recovery_is_slower_than_reduction() -> void:
	var b := _budget()
	_run(b, 20.0, 12.0)
	_run(b, 60.0, 0.6)  # flush the partially filled low-FPS window
	var reduced := b.performance_ceiling
	check(reduced < 14, "reduced first")
	_run(b, 60.0, 5.4)
	check_eq(b.performance_ceiling, reduced, "6 s of good FPS is not enough to recover")
	_run(b, 60.0, 5.0)
	check_eq(b.performance_ceiling, reduced + 1, "recovers one step after 10 s")


func test_hysteresis_band_holds_steady() -> void:
	var b := _budget()
	_run(b, 20.0, 3.6)
	var after_drop := b.performance_ceiling
	_run(b, 40.0, 60.0)
	check_eq(b.performance_ceiling, after_drop, "FPS between thresholds neither drops nor recovers")


func test_oscillating_fps_does_not_thrash() -> void:
	var b := _budget()
	var changes := [0]
	b.changed.connect(func(_c: int, _t: int) -> void: changes[0] += 1)
	for i in 30:
		_run(b, 22.0, 1.5)
		_run(b, 58.0, 1.5)
	check_eq(changes[0], 0, "alternating 1.5 s good/bad windows cause no changes")


func test_ceiling_capped_at_max() -> void:
	var b := _budget()
	_run(b, 60.0, 400.0)
	check_eq(b.performance_ceiling, 20, "ceiling recovers no higher than max")
	check_eq(b.get_actual_target(), 14, "actual stays at density target")
