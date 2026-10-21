extends "res://tests/test_case.gd"
## Same drive, different passenger: identical RideTelemetry scored for the
## three profiles. Route 500 m for every scenario.

const ROUTE_M := 500.0
const HIGH := 70.0
const GOOD := 60.0
const LOW := 45.0
const POOR := 40.0

var _config: RideConfig = load("res://resources/rides/ride_config.tres")
var _rushed: PassengerProfile = load("res://resources/passengers/rushed.tres")
var _careful: PassengerProfile = load("res://resources/passengers/careful.tres")
var _thrill: PassengerProfile = load("res://resources/passengers/thrill_seeker.tres")


func _score(t: RideTelemetry, p: PassengerProfile) -> float:
	return PassengerSatisfaction.evaluate(t, p, ROUTE_M, _config).final_score


## FAST + RISKY: 38 s (avg ~47 km/h), close calls, tight gaps, two-wheel moments.
func _fast_risky() -> RideTelemetry:
	var t := RideTelemetry.new()
	t.add_time_at(57.0, 25.0)
	t.add_time_at(35.0, 13.0)
	t.close_calls = 5
	t.tight_gaps = 2
	t.combo_peak = 4
	t.two_wheel_events = 2
	t.two_wheel_seconds = 1.2
	t.extreme_roll_seconds = 2.0
	t.hard_brakes = 2
	return t


## SAFE + SMOOTH + MODERATELY FAST: 60 s at ~30 km/h, no incidents.
func _safe_smooth() -> RideTelemetry:
	var t := RideTelemetry.new()
	t.add_time_at(32.0, 45.0)
	t.add_time_at(24.0, 15.0)
	return t


## SLOW + SAFE: 110 s at ~16 km/h.
func _slow_safe() -> RideTelemetry:
	var t := RideTelemetry.new()
	t.add_time_at(16.4, 110.0)
	return t


## COLLISION-HEAVY: 50 s, four collisions (two major).
func _crashy() -> RideTelemetry:
	var t := RideTelemetry.new()
	t.add_time_at(40.0, 50.0)
	t.collisions = 4
	t.major_collisions = 2
	t.hard_brakes = 4
	t.close_calls = 1
	return t


func test_scenario_1_fast_risky() -> void:
	var t := _fast_risky()
	var thrill := _score(t, _thrill)
	var rushed := _score(t, _rushed)
	var careful := _score(t, _careful)
	check(thrill >= HIGH, "thrill seeker high (%.1f)" % thrill)
	check(rushed >= GOOD, "rushed good/high when fast (%.1f)" % rushed)
	check(careful <= LOW, "careful low (%.1f)" % careful)
	check(thrill > careful + 40.0, "strong differentiation thrill vs careful")


func test_scenario_2_safe_smooth() -> void:
	var t := _safe_smooth()
	var careful := _score(t, _careful)
	var rushed := _score(t, _rushed)
	var thrill := _score(t, _thrill)
	check(careful >= HIGH, "careful high (%.1f)" % careful)
	check(rushed >= GOOD, "rushed good when not late (%.1f)" % rushed)
	check(thrill < rushed and thrill < careful and thrill <= 50.0, "thrill seeker bored (%.1f)" % thrill)


func test_scenario_3_slow_safe() -> void:
	var t := _slow_safe()
	var careful := _score(t, _careful)
	var rushed := _score(t, _rushed)
	var thrill := _score(t, _thrill)
	check(careful >= GOOD, "careful acceptable/high (%.1f)" % careful)
	check(rushed <= LOW, "rushed low (%.1f)" % rushed)
	check(thrill <= LOW, "thrill seeker low (%.1f)" % thrill)


func test_scenario_4_collision_heavy() -> void:
	var t := _crashy()
	for p: PassengerProfile in [_rushed, _careful, _thrill]:
		var s := _score(t, p)
		check(s <= POOR, "%s poor after a crash-heavy ride (%.1f)" % [p.id, s])


func test_scenario_5_pedestrian_danger_never_rewards() -> void:
	for base in [_fast_risky(), _safe_smooth(), _slow_safe()]:
		var with_danger: RideTelemetry = _copy(base)
		with_danger.pedestrian_danger = 2
		for p in [_rushed, _careful, _thrill]:
			var clean := PassengerSatisfaction.evaluate(base, p, ROUTE_M, _config)
			var risky := PassengerSatisfaction.evaluate(with_danger, p, ROUTE_M, _config)
			check(risky.final_score <= clean.final_score, "%s: pedestrian danger never raises satisfaction" % p.id)
			check(is_equal_approx(risky.excitement_score, clean.excitement_score), "%s: pedestrian danger never adds excitement" % p.id)
	var smooth := _safe_smooth()
	var smooth_danger := _copy(smooth)
	smooth_danger.pedestrian_danger = 2
	var careful_drop := _score(smooth, _careful) - _score(smooth_danger, _careful)
	var rushed_drop := _score(smooth, _rushed) - _score(smooth_danger, _rushed)
	var thrill_drop := _score(smooth, _thrill) - _score(smooth_danger, _thrill)
	check(careful_drop >= 40.0, "careful: strong negative (%.1f)" % careful_drop)
	check(rushed_drop > 5.0, "rushed: negative (%.1f)" % rushed_drop)
	check(thrill_drop > 0.0, "thrill seeker: negative, never positive (%.1f)" % thrill_drop)


func test_pedestrian_danger_fuzz_never_positive() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 300:
		var t := RideTelemetry.new()
		t.add_time_at(rng.randf_range(5.0, 70.0), rng.randf_range(10.0, 120.0))
		t.add_time_at(rng.randf_range(5.0, 70.0), rng.randf_range(0.0, 60.0))
		t.close_calls = rng.randi_range(0, 8)
		t.tight_gaps = rng.randi_range(0, 4)
		t.two_wheel_events = rng.randi_range(0, 3)
		t.two_wheel_seconds = t.two_wheel_events * rng.randf_range(0.2, 1.0)
		t.collisions = rng.randi_range(0, 3)
		t.major_collisions = rng.randi_range(0, t.collisions)
		t.combo_peak = rng.randi_range(0, 6)
		var d := _copy(t)
		d.pedestrian_danger = rng.randi_range(1, 4)
		for p in [_rushed, _careful, _thrill]:
			if _score(d, p) > _score(t, p):
				check(false, "fuzz %d: %s gained from pedestrian danger" % [i, p.id])
				return
	check(true, "300 random rides: pedestrian danger never increases satisfaction")


func test_pedestrian_impact_destroys_satisfaction() -> void:
	var t := _safe_smooth()
	t.pedestrian_impacts = 1
	for p in [_rushed, _careful, _thrill]:
		check(_score(t, p) <= 5.0, "%s near zero after a pedestrian impact" % p.id)


func test_time_subscore_shape() -> void:
	check_near(PassengerSatisfaction.time_subscore(0.6, _config), 100.0, 0.01, "well early = 100")
	check_near(PassengerSatisfaction.time_subscore(1.0, _config), 80.0, 0.01, "on time = 80")
	var slightly_late := PassengerSatisfaction.time_subscore(1.1, _config)
	check(slightly_late > 60.0, "slightly late is not destroyed (%.1f)" % slightly_late)
	check(PassengerSatisfaction.time_subscore(2.5, _config) < 15.0, "very late matters")


func test_telemetry_aggregation() -> void:
	var t := RideTelemetry.new()
	var cfg := _config
	for i in 600:  # 10 s at 36 km/h with one two-wheel episode and one hard brake
		var two_wheel := i >= 100 and i < 160
		var braking := -0.8 if (i >= 300 and i < 320) else 0.0
		t.sample(1.0 / 60.0, 36.0, two_wheel, 20.0 if two_wheel else 2.0, braking, cfg)
	t.record_collision(false)
	t.record_collision(true)
	t.record_skill(SkillEvent.Type.CLOSE_CALL, 1)
	t.record_skill(SkillEvent.Type.TIGHT_GAP, 3)
	check_near(t.elapsed, 10.0, 0.01, "elapsed")
	check_near(t.distance_m, 100.0, 0.5, "distance at 36 km/h for 10 s")
	check_near(t.average_speed_kmh(), 36.0, 0.1, "average speed in km/h")
	check_near(t.max_speed_kmh, 36.0, 0.01, "max speed")
	check_eq(t.two_wheel_events, 1, "one two-wheel episode")
	check_near(t.two_wheel_seconds, 1.0, 0.02, "two-wheel time")
	check_eq(t.hard_brakes, 1, "one hard brake")
	check_eq(t.collisions, 2, "collisions")
	check_eq(t.major_collisions, 1, "major collisions")
	check_eq(t.close_calls, 1, "close calls")
	check_eq(t.tight_gaps, 1, "tight gaps")
	check_eq(t.combo_peak, 3, "combo peak")
	check_near(t.seconds_above(30.0), 10.0, 0.01, "speed histogram above 30 km/h")


func test_fare_calculation() -> void:
	var base := RideResult.calculate_base_fare(500.0, _config)
	check_eq(base, 150, "Rs 100 pickup + Rs 90/km × 0.5 km = 145 → rounds to 150")
	check_eq(RideResult.calculate_adjustment(base, 87.0, _config), 20, "87% → +13.5% → +Rs 20")
	check_eq(RideResult.calculate_adjustment(base, 60.0, _config), 0, "neutral 60% → no adjustment")
	check(RideResult.calculate_adjustment(base, 10.0, _config) < 0, "poor rating reduces fare")
	check_eq(RideResult.calculate_adjustment(400, 0.0, _config), -120, "penalty capped by curve (−30%)")
	check_eq(RideResult.calculate_adjustment(400, 100.0, _config), 80, "bonus +20% at 100%")


func test_profiles_extended_schema() -> void:
	for p in [_rushed, _careful, _thrill]:
		check(p.validate().is_empty(), "%s valid: %s" % [p.id, p.validate()])
		var w: Vector4 = p.normalised_weights()
		check_near(w.x + w.y + w.z + w.w, 1.0, 0.0001, "%s weights normalise" % p.id)
		check(p.pedestrian_danger_sensitivity > 0.0, "%s never rewards pedestrian danger" % p.id)
	check(_thrill.excitement_weight > _rushed.excitement_weight and _careful.excitement_weight == 0.0, "excitement weighting")
	var legacy := PassengerProfile.new()
	legacy.id = &"legacy"
	legacy.display_name_key = "X"
	check(legacy.validate().is_empty(), "v0.01-style profile (no excitement fields) still valid")
	check_near(legacy.normalised_weights().w, 0.0, 0.0001, "legacy profile has zero excitement weight")


func test_reactions_follow_preferences_with_cooldown() -> void:
	var thrill := PassengerReactionSystem.new(_thrill, _config)
	var careful := PassengerReactionSystem.new(_careful, _config)
	thrill.on_skill(SkillEvent.Type.CLOSE_CALL)
	careful.on_skill(SkillEvent.Type.CLOSE_CALL)
	check_eq(thrill.tick(0.016, 50.0, 10.0), "REACT_CLOSE_CALL_POS", "thrill seeker enjoys a close call")
	check_eq(careful.tick(0.016, 50.0, 10.0), "REACT_CLOSE_CALL_NEG", "careful passenger objects")
	thrill.on_skill(SkillEvent.Type.CLOSE_CALL)
	check_eq(thrill.tick(0.016, 50.0, 10.0), "", "global cooldown prevents spam")
	thrill.on_pedestrian_danger()
	for i in 300:
		var k := thrill.tick(0.016, 50.0, 10.0)
		if not k.is_empty():
			check_eq(k, "REACT_PEDESTRIAN_DANGER", "thrill seeker reacts NEGATIVELY to pedestrian danger")
			break
	var rushed := PassengerReactionSystem.new(_rushed, _config)
	var said := ""
	for i in 900:
		var k := rushed.tick(1.0 / 60.0, 12.0, 5.0 + i / 60.0)
		if not k.is_empty():
			said = k
			break
	check_eq(said, "REACT_HURRY_UP", "late executive complains when crawling")


func _copy(t: RideTelemetry) -> RideTelemetry:
	var c := RideTelemetry.new()
	c.elapsed = t.elapsed
	c.distance_m = t.distance_m
	c.max_speed_kmh = t.max_speed_kmh
	c.speed_histogram = t.speed_histogram.duplicate()
	c.collisions = t.collisions
	c.major_collisions = t.major_collisions
	c.close_calls = t.close_calls
	c.tight_gaps = t.tight_gaps
	c.combo_peak = t.combo_peak
	c.two_wheel_events = t.two_wheel_events
	c.two_wheel_seconds = t.two_wheel_seconds
	c.extreme_roll_seconds = t.extreme_roll_seconds
	c.rollovers = t.rollovers
	c.hard_brakes = t.hard_brakes
	c.pedestrian_danger = t.pedestrian_danger
	c.pedestrian_impacts = t.pedestrian_impacts
	return c
