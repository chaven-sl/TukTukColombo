class_name RidePayout
extends RefCounted
## Explains what a ride earned (v0.04). Starts from the existing fare
## (base fare + satisfaction adjustment, unchanged) and adds a few readable,
## personality-aware lines, then the job-tier and career multipliers.
##
## Rules:
## - Pedestrian danger or impact NEVER earns: it cancels every skill/clean
##   bonus (and satisfaction already falls).
## - Vehicle-risk skill (close calls, tight gaps, combo) pays only in
##   proportion to the passenger's POSITIVE close_call_preference — a Thrill
##   Seeker rewards it, a Careful Aunty never does.
## - Failed rides earn Rs. 0 and 0 ★. Reputation is never deducted.

## Fills result.payout_lines / cash_earned / reputation_earned.
static func apply(result: RideResult, tier: JobTiers.Tier, career_level: int, c: EconomyConfig) -> void:
	result.job_tier = tier
	result.payout_lines = []
	if result.outcome != RideResult.Outcome.COMPLETED:
		result.cash_earned = 0
		result.reputation_earned = 0
		return
	var t := result.telemetry
	var p := result.profile
	var lines: Array = []
	lines.append(["PAY_BASE_FARE", result.base_fare])
	if result.adjustment != 0:
		lines.append(["PAY_PASSENGER_RATING", result.adjustment])
	var unsafe := t.pedestrian_danger > 0 or t.pedestrian_impacts > 0
	var clean := t.collisions == 0 and t.rollovers == 0 and not unsafe
	if clean:
		# Matters most to safety-minded passengers (Aunty), least to thrill seekers.
		lines.append(["PAY_CLEAN_RIDE", roundi(c.clean_ride_bonus * (0.5 + p.safety_weight) / 10.0) * 10])
	if not unsafe and t.hard_brakes == 0 and t.collisions == 0:
		lines.append(["PAY_SMOOTH_STOP", roundi(c.smooth_stop_bonus * (0.5 + p.comfort_weight) / 10.0) * 10])
	if result.satisfaction != null and result.satisfaction.time_score >= 85.0:
		lines.append(["PAY_FAST_FARE", roundi(c.fast_fare_bonus * (0.5 + p.time_weight) / 10.0) * 10])
	var appetite := maxf(p.close_call_preference, 0.0)
	if not unsafe and appetite > 0.0:
		var skill := (t.close_calls * c.close_call_bonus + t.tight_gaps * c.tight_gap_bonus
				+ maxi(t.combo_peak - 1, 0) * c.combo_bonus_per_chain) * appetite
		skill = minf(skill, c.skill_bonus_cap)
		if skill >= 1.0:
			lines.append(["PAY_SKILL", roundi(skill)])
	var minor := t.collisions - t.major_collisions
	if minor > 0:
		lines.append(["PAY_COLLISIONS", -minor * c.minor_collision_penalty])
	if t.major_collisions > 0:
		lines.append(["PAY_MAJOR_COLLISIONS", -t.major_collisions * c.major_collision_penalty])
	var subtotal := 0
	for l: Array in lines:
		subtotal += int(l[1])
	var mult := JobTiers.cash_multiplier(tier, c) * (1.0 + c.career_fare_bonus_per_level * (career_level - 1))
	var total := maxi(roundi(subtotal * mult / 10.0) * 10, 0)
	if total != subtotal:
		lines.append(["PAY_JOB_BONUS", total - subtotal])
	result.payout_lines = lines
	result.cash_earned = total
	result.reputation_earned = stars_for(result.satisfaction.final_score if result.satisfaction != null else 0.0, c) \
			+ JobTiers.reputation_bonus(tier, c)
	result.reputation_earned = clampi(result.reputation_earned, 0, c.max_ride_reputation)
	if unsafe and t.pedestrian_impacts > 0:
		result.reputation_earned = 0  # major safety failure


## Passenger rating % → ★ (interpolated within each band).
static func stars_for(rating: float, c: EconomyConfig) -> int:
	var b := c.rating_breaks
	var s := c.rating_stars
	for i in range(b.size() - 1):
		if rating < b[i + 1] or i == b.size() - 2:
			var f := clampf((rating - b[i]) / maxf(b[i + 1] - b[i], 0.001), 0.0, 1.0)
			var top := (s[i + 1] - 1) if i < b.size() - 2 else c.max_ride_reputation
			return roundi(lerpf(float(s[i]), float(top), f))
	return s[0]
