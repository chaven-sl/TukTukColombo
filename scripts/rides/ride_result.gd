class_name RideResult
extends RefCounted
## Outcome of one ride, for the result card, saves and tests.

enum Outcome { COMPLETED, FAILED }
enum FailReason { NONE, PEDESTRIAN_IMPACT, ROLLOVER, VEHICLE_DISABLED }

var outcome: Outcome = Outcome.COMPLETED
var fail_reason: FailReason = FailReason.NONE
var profile: PassengerProfile
var destination_key := ""
var route_distance_m := 0.0
var telemetry: RideTelemetry
var satisfaction: PassengerSatisfaction
var base_fare := 0
var adjustment := 0
var final_fare := 0
## Translation key summarising the driving style.
var style_key := ""
## v0.04 economy (RidePayout): job tier, explained payout lines
## [[translation key, Rs.], …], cash and reputation actually earned.
var job_tier: int = 0
var payout_lines: Array = []
var cash_earned := 0
var reputation_earned := 0


static func calculate_base_fare(route_distance_m: float, c: RideConfig) -> int:
	var raw := c.pickup_fee + c.fare_per_km * route_distance_m / 1000.0
	return int(round(raw / c.fare_rounding) * c.fare_rounding)


static func calculate_adjustment(base: int, satisfaction_pct: float, c: RideConfig) -> int:
	var fraction := clampf((satisfaction_pct - c.neutral_satisfaction) * c.adjustment_per_point,
			c.max_penalty_fraction, c.max_bonus_fraction)
	return int(round(base * fraction / c.fare_rounding) * c.fare_rounding)


## Dominant driving-style label for the result card.
static func style_for(t: RideTelemetry, s: PassengerSatisfaction) -> String:
	if t.pedestrian_danger > 0 or t.pedestrian_impacts > 0:
		return "STYLE_UNSAFE_PEDESTRIANS"
	if t.collisions >= 2 or t.rollovers > 0:
		return "STYLE_CRASHY"
	if t.close_calls + t.tight_gaps >= 3 or t.two_wheel_events >= 2:
		return "STYLE_DAREDEVIL"
	if s.time_score >= 85.0:
		return "STYLE_FAST"
	if s.time_score < 50.0:
		return "STYLE_SLOW"
	return "STYLE_SMOOTH"
