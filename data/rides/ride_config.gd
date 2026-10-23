class_name RideConfig
extends Resource
## Ride loop, satisfaction model and fare tunables. PROTOTYPE BASELINE v0.02.
## Speeds are km/h. Subscores are 0–100.

@export_group("Pickup and arrival")
## v0.02 accept distance (m). Kept for reference/tests; since v0.03A1 the
## hire is offered from hire_offer_radius and the GPS leads to the pickup.
@export var accept_radius := 12.0
## v0.03A1: the nearest waiting passenger within this straight-line distance
## (m) is offered as a hire (card + ACCEPT HIRE); GPS then guides to them.
@export var hire_offer_radius := 220.0
## Tuk must be within this distance of the passenger to board (m)...
@export var pickup_radius := 9.0
## ...and slower than this (km/h).
@export var pickup_max_speed_kmh := 5.0
## Accepted offer is cancelled if the tuk ends up this much farther from the
## passenger than when the hire was accepted (m), and at least
## cancel_distance away.
@export var cancel_distance := 90.0
@export var cancel_extra_distance := 140.0
@export var boarding_seconds := 0.8
@export var arrive_radius := 12.0
@export var arrive_max_speed_kmh := 5.0
## Seconds the result card stays (interact dismisses earlier).
@export var result_display_seconds := 7.0
## Delay before a finished offer's pickup gets a new passenger (s).
@export var offer_respawn_seconds := 6.0
## New offers pick destinations at least this far by road (m).
@export var min_offer_route_m := 250.0
## A confirmed rollover during a ride fails the ride (v0.02 decision).
@export var fail_on_rollover := true

@export_group("Time score")
## Ratio actual/target time -> score: <= fast_ratio = 100, 1.0 = on_time_score,
## late_ratio = late_score, very_late_ratio = very_late_score (linear between).
@export var fast_ratio := 0.75
@export var on_time_score := 80.0
@export var late_ratio := 1.3
@export var late_score := 50.0
@export var very_late_ratio := 2.0
@export var very_late_score := 8.0

@export_group("Safety score")
@export var minor_collision_penalty := 12.0
@export var major_collision_penalty := 30.0
@export var rollover_penalty := 60.0
## Per vehicle-risk event (close call 1, tight gap 2, two-wheel 3), scaled by
## (1 - risk_tolerance).
@export var vehicle_risk_penalty := 7.0
@export var pedestrian_danger_safety_penalty := 18.0
@export var pedestrian_impact_safety_penalty := 100.0

@export_group("Comfort score")
@export var hard_brake_penalty := 4.0
@export var two_wheel_second_penalty := 14.0
@export var extreme_roll_second_penalty := 6.0
@export var collision_comfort_penalty := 8.0
## Penalty for the fraction of ride time above preferred speed + tolerance.
@export var overspeed_fraction_penalty := 70.0
## Per close call / tight gap, scaled by max(-close_call_preference, 0).
@export var near_miss_discomfort := 6.0
@export var extreme_roll_deg := 15.0
@export var hard_brake_g := 0.55

@export_group("Excitement score (vehicle events only)")
@export var excitement_baseline := 15.0
@export var close_call_excitement := 9.0
@export var tight_gap_excitement := 16.0
## Controlled two-wheel moment (no rollover), scaled by two_wheel_preference.
@export var two_wheel_excitement := 8.0
@export var high_speed_kmh := 45.0
@export var high_speed_fraction_excitement := 45.0
@export var combo_peak_excitement := 2.0

@export_group("Severe penalties on final satisfaction")
## Per collision, × collision_penalty_multiplier: crashes ruin every ride,
## even for a passenger who mostly cares about time.
@export var minor_collision_final_penalty := 6.0
@export var major_collision_final_penalty := 15.0
## Applied after weighting, × pedestrian_danger_sensitivity. Never positive.
@export var pedestrian_danger_final_penalty := 8.0

@export_group("Fare (prototype rupees)")
@export var pickup_fee := 100.0
@export var fare_per_km := 90.0
@export var fare_rounding := 10.0
## Satisfaction where the adjustment is zero (%).
@export var neutral_satisfaction := 60.0
## Fare fraction per satisfaction point above/below neutral.
@export var adjustment_per_point := 0.005
@export var max_bonus_fraction := 0.4
@export var max_penalty_fraction := -0.5

@export_group("Reactions")
@export var reaction_global_cooldown := 4.0
@export var reaction_key_cooldown := 12.0
## Rushed-style "hurry up" when a time-focused passenger crawls below this...
@export var hurry_speed_kmh := 22.0
## ...for this long (s), not counting the first seconds after pickup.
@export var hurry_after_seconds := 7.0
