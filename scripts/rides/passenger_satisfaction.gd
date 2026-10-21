class_name PassengerSatisfaction
extends RefCounted
## Systemic satisfaction model. ONE function for every passenger:
##
##   time, safety, comfort, excitement  (shared subscores, 0–100)
##   final = Σ normalised_profile_weight × subscore − severe penalties
##
## Profiles differ only through data (weights, risk tolerance, preferences).
## Pedestrian danger/impact can only ever LOWER satisfaction: it is never an
## input to excitement, and every penalty using it is clamped non-positive.

var time_score := 0.0
var safety_score := 0.0
var comfort_score := 0.0
var excitement_score := 0.0
var weighted := 0.0
var severe_penalty := 0.0
var final_score := 0.0
var target_seconds := 0.0


static func evaluate(t: RideTelemetry, profile: PassengerProfile, route_distance_m: float,
		config: RideConfig) -> PassengerSatisfaction:
	var r := PassengerSatisfaction.new()
	var w := profile.normalised_weights()
	r.target_seconds = maxf(route_distance_m, 1.0) / (profile.expected_speed_kmh / 3.6)
	r.time_score = time_subscore(t.elapsed / maxf(r.target_seconds, 0.1), config)
	r.safety_score = safety_subscore(t, profile, config)
	r.comfort_score = comfort_subscore(t, profile, config)
	r.excitement_score = excitement_subscore(t, profile, config)
	r.weighted = w.x * r.time_score + w.y * r.safety_score + w.z * r.comfort_score + w.w * r.excitement_score
	r.severe_penalty = -absf(config.pedestrian_danger_final_penalty * profile.pedestrian_danger_sensitivity) \
			* float(t.pedestrian_danger)
	var minor := t.collisions - t.major_collisions
	r.severe_penalty -= (minor * config.minor_collision_final_penalty + t.major_collisions * config.major_collision_final_penalty) \
			* profile.collision_penalty_multiplier
	if t.pedestrian_impacts > 0:
		r.severe_penalty -= 100.0
	r.final_score = clampf(r.weighted + minf(r.severe_penalty, 0.0), 0.0, 100.0)
	return r


static func time_subscore(ratio: float, c: RideConfig) -> float:
	if ratio <= c.fast_ratio:
		return 100.0
	if ratio <= 1.0:
		return lerpf(100.0, c.on_time_score, (ratio - c.fast_ratio) / (1.0 - c.fast_ratio))
	if ratio <= c.late_ratio:
		return lerpf(c.on_time_score, c.late_score, (ratio - 1.0) / (c.late_ratio - 1.0))
	if ratio <= c.very_late_ratio:
		return lerpf(c.late_score, c.very_late_score, (ratio - c.late_ratio) / (c.very_late_ratio - c.late_ratio))
	return c.very_late_score


static func safety_subscore(t: RideTelemetry, p: PassengerProfile, c: RideConfig) -> float:
	var score := 100.0
	var minor := t.collisions - t.major_collisions
	score -= (minor * c.minor_collision_penalty + t.major_collisions * c.major_collision_penalty) * p.collision_penalty_multiplier
	score -= t.rollovers * c.rollover_penalty
	var risk_events := float(t.close_calls + 2 * t.tight_gaps + 3 * t.two_wheel_events)
	score -= risk_events * c.vehicle_risk_penalty * (1.0 - p.risk_tolerance)
	# Pedestrian danger: full penalty regardless of risk tolerance.
	score -= t.pedestrian_danger * c.pedestrian_danger_safety_penalty * p.pedestrian_danger_sensitivity
	score -= t.pedestrian_impacts * c.pedestrian_impact_safety_penalty
	return clampf(score, 0.0, 100.0)


static func comfort_subscore(t: RideTelemetry, p: PassengerProfile, c: RideConfig) -> float:
	var score := 100.0
	score -= t.hard_brakes * c.hard_brake_penalty
	score -= t.two_wheel_seconds * c.two_wheel_second_penalty * maxf(1.0 - p.two_wheel_preference, 0.0)
	score -= t.extreme_roll_seconds * c.extreme_roll_second_penalty * (1.0 - p.risk_tolerance)
	score -= t.collisions * c.collision_comfort_penalty
	if t.elapsed > 0.0:
		var overspeed := t.seconds_above(p.speed_preference_kmh + p.speed_tolerance_kmh)
		score -= (overspeed / t.elapsed) * c.overspeed_fraction_penalty
	score -= (t.close_calls + t.tight_gaps) * c.near_miss_discomfort * maxf(-p.close_call_preference, 0.0)
	return clampf(score, 0.0, 100.0)


## Vehicle-only excitement. Pedestrian events are deliberately NOT inputs.
static func excitement_subscore(t: RideTelemetry, p: PassengerProfile, c: RideConfig) -> float:
	var score := c.excitement_baseline
	var near_miss_appetite := maxf(p.close_call_preference, 0.0)
	score += t.close_calls * c.close_call_excitement * near_miss_appetite
	score += t.tight_gaps * c.tight_gap_excitement * near_miss_appetite
	if t.rollovers == 0:
		score += t.two_wheel_events * c.two_wheel_excitement * maxf(p.two_wheel_preference, 0.0)
	if t.elapsed > 0.0:
		score += (t.seconds_above(c.high_speed_kmh) / t.elapsed) * c.high_speed_fraction_excitement
	score += t.combo_peak * c.combo_peak_excitement * near_miss_appetite
	return clampf(score, 0.0, 100.0)
