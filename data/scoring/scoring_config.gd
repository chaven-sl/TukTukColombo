class_name ScoringConfig
extends Resource
## Near-miss detection thresholds and combo rules. PROTOTYPE BASELINE.

@export_group("Points")
@export var close_call_points := 25
@export var tight_gap_points := 50
## Architected only; ONCOMING is not emitted in v0.01.
@export var oncoming_points := 35

@export_group("Combo")
@export var max_multiplier := 5
@export var combo_timeout := 3.0
## Collisions at or above this severity reset the combo (0 = MINOR).
@export var combo_reset_min_severity := 0

@export_group("Close call")
## Candidate tracking starts within this edge-to-edge distance (m).
@export var proximity_distance := 2.0
## A pass scores when the closest clearance is inside this band (m).
@export var min_valid_clearance := 0.15
@export var max_valid_clearance := 0.85
## Relative speed needed at the pass (m/s). 6 m/s ≈ 22 km/h.
@export var min_relative_speed := 6.0
## The player must be driving, not parked while traffic passes.
@export var min_player_speed_kmh := 15.0
## A candidate that stays alongside at low relative speed (below 60% of
## min_relative_speed) for longer than this expires without scoring (s).
## Stops "cruise next to a car" farming without punishing slow bus overtakes.
@export var max_alongside_time := 0.8
## Absolute cap on how long one candidate can be tracked (s).
@export var max_track_time := 5.0
## After crossing, wait this long (or until fully clear) to confirm no contact.
@export var confirm_time := 0.35
## Per-agent cooldown before it can score again (s).
@export var agent_cooldown := 2.5
## Squared-distance broad phase (m).
@export var broad_phase_radius := 14.0

@export_group("Tight gap")
## Passing threats on both sides within this window is a TIGHT GAP (s).
@export var tight_gap_window := 0.7
## Each side's clearance must be within this (m).
@export var tight_gap_threat_clearance := 1.2
@export var tight_gap_min_relative_speed := 4.0


func points_for(event_type: int) -> int:
	match event_type:
		SkillEvent.Type.CLOSE_CALL:
			return close_call_points
		SkillEvent.Type.TIGHT_GAP:
			return tight_gap_points
		SkillEvent.Type.ONCOMING:
			return oncoming_points
	return 0
