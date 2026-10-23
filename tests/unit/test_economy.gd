extends "res://tests/test_case.gd"
## v0.04 economy: payouts, reputation, personality-aware bonuses, purchases.

var econ: EconomyConfig = load("res://resources/economy/economy_config.tres")
var ride_cfg: RideConfig = load("res://resources/rides/ride_config.tres")
var careful: PassengerProfile = load("res://resources/passengers/careful.tres")
var thrill: PassengerProfile = load("res://resources/passengers/thrill_seeker.tres")
var rushed: PassengerProfile = load("res://resources/passengers/rushed.tres")


func _ride(profile: PassengerProfile, t: RideTelemetry, outcome := RideResult.Outcome.COMPLETED, route := 600.0) -> RideResult:
	var r := RideResult.new()
	r.outcome = outcome
	r.profile = profile
	r.route_distance_m = route
	r.telemetry = t
	r.satisfaction = PassengerSatisfaction.evaluate(t, profile, route, ride_cfg)
	if outcome == RideResult.Outcome.COMPLETED:
		r.base_fare = RideResult.calculate_base_fare(route, ride_cfg)
		r.adjustment = RideResult.calculate_adjustment(r.base_fare, r.satisfaction.final_score, ride_cfg)
		r.final_fare = maxi(r.base_fare + r.adjustment, 0)
	return r


func _telemetry(seconds: float, close_calls := 0, tight := 0, collisions := 0, ped := 0) -> RideTelemetry:
	var t := RideTelemetry.new()
	t.elapsed = seconds
	t.distance_m = 600.0
	t.close_calls = close_calls
	t.tight_gaps = tight
	t.combo_peak = close_calls + tight
	t.collisions = collisions
	t.pedestrian_danger = ped
	return t


func _line(r: RideResult, key: String) -> int:
	for l: Array in r.payout_lines:
		if l[0] == key:
			return int(l[1])
	return 0


func test_completed_ride_earns_cash_and_reputation() -> void:
	var r := _ride(rushed, _telemetry(60.0))
	RidePayout.apply(r, JobTiers.Tier.STANDARD, 1, econ)
	check(r.cash_earned > 0, "cash earned (Rs. %d)" % r.cash_earned)
	check(r.reputation_earned >= 1 and r.reputation_earned <= 12, "reputation in 1–12 (%d)" % r.reputation_earned)
	var sum := 0
	for l: Array in r.payout_lines:
		sum += int(l[1])
	check_eq(sum, r.cash_earned, "payout lines add up to the total")


func test_failed_ride_earns_nothing() -> void:
	var r := _ride(rushed, _telemetry(60.0), RideResult.Outcome.FAILED)
	RidePayout.apply(r, JobTiers.Tier.PREMIUM, 5, econ)
	check_eq(r.cash_earned, 0, "failed: Rs. 0")
	check_eq(r.reputation_earned, 0, "failed: 0 ★")


func test_reputation_bands() -> void:
	check(RidePayout.stars_for(20.0, econ) >= 1 and RidePayout.stars_for(20.0, econ) <= 2, "poor → 1–2 ★")
	check(RidePayout.stars_for(55.0, econ) >= 3 and RidePayout.stars_for(55.0, econ) <= 5, "average → 3–5 ★")
	check(RidePayout.stars_for(75.0, econ) >= 6 and RidePayout.stars_for(75.0, econ) <= 8, "good → 6–8 ★")
	check(RidePayout.stars_for(95.0, econ) >= 9 and RidePayout.stars_for(95.0, econ) <= 12, "excellent → 9–12 ★")


func test_pedestrian_danger_never_pays() -> void:
	var risky := _ride(thrill, _telemetry(60.0, 4, 2, 0, 1))
	RidePayout.apply(risky, JobTiers.Tier.STANDARD, 1, econ)
	check_eq(_line(risky, "PAY_SKILL"), 0, "no skill bonus once a pedestrian was endangered")
	check_eq(_line(risky, "PAY_CLEAN_RIDE"), 0, "no clean-ride bonus")
	var safe := _ride(thrill, _telemetry(60.0, 4, 2, 0, 0))
	RidePayout.apply(safe, JobTiers.Tier.STANDARD, 1, econ)
	check(safe.cash_earned > risky.cash_earned, "the same ride pays more without pedestrian danger")


func test_personality_aware_skill_bonus() -> void:
	var t := RideTelemetry.new()
	var a := _ride(thrill, _telemetry(60.0, 4, 2))
	var b := _ride(careful, _telemetry(60.0, 4, 2))
	RidePayout.apply(a, JobTiers.Tier.STANDARD, 1, econ)
	RidePayout.apply(b, JobTiers.Tier.STANDARD, 1, econ)
	check(_line(a, "PAY_SKILL") > 0, "Thrill Seeker rewards vehicle-risk skill (Rs. %d)" % _line(a, "PAY_SKILL"))
	check_eq(_line(b, "PAY_SKILL"), 0, "Careful Aunty never rewards close calls")
	var calm := _ride(careful, _telemetry(60.0))
	RidePayout.apply(calm, JobTiers.Tier.STANDARD, 1, econ)
	check(calm.cash_earned > b.cash_earned, "a calm ride earns the Aunty's driver more than a risky one")


func test_collisions_cost_money_not_below_zero() -> void:
	var r := _ride(careful, _telemetry(200.0, 0, 0, 6))
	RidePayout.apply(r, JobTiers.Tier.STANDARD, 1, econ)
	check(_line(r, "PAY_COLLISIONS") < 0, "collision penalty line")
	check(r.cash_earned >= 0, "payout never negative")


func test_job_tiers_pay_more() -> void:
	var s := _ride(rushed, _telemetry(60.0))
	var e := _ride(rushed, _telemetry(60.0))
	var p := _ride(rushed, _telemetry(60.0))
	RidePayout.apply(s, JobTiers.Tier.STANDARD, 3, econ)
	RidePayout.apply(e, JobTiers.Tier.EXPRESS, 3, econ)
	RidePayout.apply(p, JobTiers.Tier.PREMIUM, 3, econ)
	check(e.cash_earned > s.cash_earned and p.cash_earned > e.cash_earned, "EXPRESS > STANDARD, PREMIUM > EXPRESS (%d/%d/%d)" % [s.cash_earned, e.cash_earned, p.cash_earned])
	check(p.reputation_earned >= s.reputation_earned, "PREMIUM earns at least as much ★")


func test_tier_availability_by_career_level() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for i in 300:
		seen[JobTiers.roll(1, rng, econ)] = true
	check(seen.keys() == [JobTiers.Tier.STANDARD], "level 1: STANDARD only")
	seen.clear()
	for i in 300:
		seen[JobTiers.roll(3, rng, econ)] = true
	check(seen.has(JobTiers.Tier.EXPRESS) and seen.has(JobTiers.Tier.PREMIUM), "level 3: EXPRESS and PREMIUM appear")


func test_tier_profiles_do_not_edit_shared_resources() -> void:
	var before := rushed.expected_speed_kmh
	var p := JobTiers.profile_for(rushed, JobTiers.Tier.EXPRESS, econ)
	check(p != rushed and p.expected_speed_kmh > before, "EXPRESS copy expects faster progress")
	check_eq(rushed.expected_speed_kmh, before, "shared profile untouched")


func test_career_levels_from_reputation() -> void:
	check_eq(CareerProfile.level_for(0, econ), 1, "0 ★ → level 1")
	check_eq(CareerProfile.level_for(49, econ), 1, "49 ★ → level 1")
	check_eq(CareerProfile.level_for(50, econ), 2, "50 ★ → level 2")
	check_eq(CareerProfile.level_for(150, econ), 3, "150 ★ → level 3")
	check_eq(CareerProfile.level_for(700, econ), 5, "700 ★ → level 5")
	check_eq(CareerProfile.level_for(5000, econ), 5, "capped at 5")


func test_purchase_success_and_insufficient_funds() -> void:
	var c := CareerProfile.new({}, econ)
	check_eq(c.cash(), econ.starting_cash, "starts with Rs. %d" % econ.starting_cash)
	var cost := c.next_cost(&"engine")
	check_eq(c.purchase(&"engine", 0), CareerProfile.Purchase.INSUFFICIENT_FUNDS if cost > c.cash() else CareerProfile.Purchase.OK, "first purchase follows the cost curve")
	c.data["cash"] = cost + 5
	var level_before := c.level_of(&"engine")
	check_eq(c.purchase(&"engine", level_before), CareerProfile.Purchase.OK, "purchase succeeds with enough cash")
	check_eq(c.cash(), 5, "exact cost deducted")
	check_eq(c.level_of(&"engine"), level_before + 1, "level advanced")
	check_eq(c.purchase(&"brakes", 0), CareerProfile.Purchase.INSUFFICIENT_FUNDS, "insufficient funds refused")
	check_eq(c.level_of(&"brakes"), 0, "no level gained when refused")
	check_eq(c.cash(), 5, "no cash taken when refused")


func test_no_double_purchase_from_rapid_taps() -> void:
	var c := CareerProfile.new({}, econ)
	c.data["cash"] = 1000000
	check_eq(c.purchase(&"brakes", 0), CareerProfile.Purchase.OK, "first tap buys level 1")
	check_eq(c.purchase(&"brakes", 0), CareerProfile.Purchase.STALE_REQUEST, "second tap with the same expected level is rejected")
	check_eq(c.level_of(&"brakes"), 1, "only one level bought")


func test_max_level_and_never_negative_cash() -> void:
	var c := CareerProfile.new({}, econ)
	c.data["cash"] = 1000000
	for i in 5:
		c.purchase(&"handling", i)
	check_eq(c.level_of(&"handling"), 5, "level 5 reached")
	check_eq(c.purchase(&"handling", 5), CareerProfile.Purchase.MAX_LEVEL, "max level refused")
	check_eq(c.next_cost(&"handling"), -1, "no next cost at max")
	var poor := CareerProfile.new({}, econ)
	poor.data["cash"] = 0
	for id in UpgradeCatalog.IDS:
		poor.purchase(id, 0)
	check(poor.cash() >= 0, "cash never negative")


func test_apply_ride_updates_career() -> void:
	var c := CareerProfile.new({}, econ)
	var r := _ride(rushed, _telemetry(60.0))
	RidePayout.apply(r, JobTiers.Tier.STANDARD, 1, econ)
	var cash := c.cash()
	c.apply_ride(r)
	check_eq(c.cash(), cash + r.cash_earned, "cash credited")
	check_eq(c.reputation(), r.reputation_earned, "reputation credited")
	check_eq(int(c.data["successful_rides"]), 1, "successful ride counted")
	var f := _ride(rushed, _telemetry(60.0), RideResult.Outcome.FAILED)
	RidePayout.apply(f, JobTiers.Tier.STANDARD, 1, econ)
	c.apply_ride(f)
	check_eq(int(c.data["failed_rides"]), 1, "failed ride counted")
	check_eq(c.reputation(), r.reputation_earned, "reputation never deducted")
