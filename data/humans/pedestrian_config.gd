class_name PedestrianConfig
extends Resource
## Human population, movement and awareness tunables. PROTOTYPE BASELINE v0.02.
## Walking speeds are km/h (converted internally).

@export_group("Population")
@export var pool_capacity := 18
## Pool slots kept free for physical passengers.
@export var reserved_for_passengers := 3
## Ambient humans (walkers, crossers, waiters, groups) kept near the player.
@export var ambient_target := 8
## Hard cap on simultaneously active humans (ambient + passengers).
@export var max_active := 12
@export var spawn_min_distance := 30.0
@export var spawn_max_distance := 95.0
## Ambient humans further than this (and out of view) return to the pool.
@export var despawn_distance := 130.0
## Waiting groups appear when the player is within this distance of the spot.
@export var group_activation_distance := 140.0
@export var spawn_interval := 0.35

@export_group("Archetype weights")
@export var weight_sidewalk_walker := 0.55
@export var weight_crossing_pedestrian := 0.3
@export var weight_waiting_pedestrian := 0.15

@export_group("Walking speeds (km/h)")
@export var slow_speed_kmh := Vector2(3.0, 3.5)
@export var normal_speed_kmh := Vector2(4.0, 5.0)
@export var fast_speed_kmh := Vector2(5.5, 6.5)
## Fraction of people per speed band (slow, normal, fast).
@export var speed_band_weights := Vector3(0.25, 0.55, 0.2)
@export var pause_seconds := Vector2(1.0, 4.0)
## Speed multiplier while hurrying off a crossing.
@export var hurry_multiplier := 1.9

@export_group("Crossing awareness")
## Extra seconds of gap (beyond time-to-clear) a person wants before crossing.
## Each person rolls a confidence inside this range.
@export var crossing_margin_seconds := Vector2(1.2, 3.2)
## Uncontrolled crossings: people accept tighter gaps (margin multiplier),
## but never less than min_uncontrolled_margin.
@export var uncontrolled_margin_scale := 0.65
@export var min_uncontrolled_margin := 0.8
## Vehicles considered up to this far from the crossing (m).
@export var awareness_range := 80.0
## Seconds between awareness checks per person (staggered).
@export var awareness_interval := 0.15
## Give up waiting and walk elsewhere after this long (s).
@export var give_up_wait_seconds := 25.0

@export_group("Player threat and incidents")
## Person reacts when the tuk approaches within this distance...
@export var react_distance := 10.0
## ...faster than this closing speed (km/h)...
@export var react_closing_speed_kmh := 14.0
## ...and its path passes within this lateral distance (m).
@export var react_lateral := 2.5
@export var reaction_seconds := 1.2
## PEDESTRIAN_DANGER: tuk passes within this clearance (m) above this speed.
@export var danger_clearance := 1.2
@export var danger_speed_kmh := 20.0
## PEDESTRIAN_DANGER: tuk on the sidewalk this close (m) above this speed.
@export var sidewalk_danger_clearance := 2.5
@export var sidewalk_danger_speed_kmh := 10.0
@export var danger_cooldown := 3.0
## PEDESTRIAN_IMPACT: footprint overlap (person radius, m) above this speed.
@export var person_radius := 0.28
@export var impact_min_speed_kmh := 3.0
