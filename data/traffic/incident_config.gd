class_name IncidentConfig
extends Resource
## Traffic collision reaction tunables (v0.03A1). PROTOTYPE BASELINE.
## Speeds km/h, distances m, times s.

## Traffic contact below this impact speed (and not MAJOR) is LIGHT; at or
## above it is MODERATE. CollisionEvent MAJOR is always MAJOR.
@export var moderate_min_kmh := 14.0
## Floor for the exit chance on a MAJOR collision, whatever the temperament.
@export_range(0.0, 1.0) var major_min_exit_chance := 0.85
@export var temperaments: Array[DriverTemperament] = []

@export_group("Timing")
@export var stop_seconds := 0.9
## Honk-and-yell only (no exit) duration range.
@export var honk_only_seconds := Vector2(1.5, 2.5)
@export var exit_seconds := 0.7
@export var resume_delay := 0.6
## Hard cap on one altercation, whatever happens.
@export var max_incident_seconds := 22.0
## Argument length multiplier for MODERATE (MAJOR uses major_argue_scale).
@export var moderate_argue_scale := 0.8
@export var major_argue_scale := 1.3
@export var shout_interval := 1.3

@export_group("Driver")
## Walking pace towards / away from the tuk (km/h).
@export var driver_walk_kmh := 6.0
## Gives up walking over after this long (s) — never a chase.
@export var approach_max_seconds := 6.0
## Stops this far from the tuk to argue.
@export var argue_distance := 2.4
## The player "has left" when this far from the driver...
@export var leave_distance := 18.0
## ...or moving faster than this while more than 6 m away.
@export var leave_speed_kmh := 14.0

@export_group("Limits")
## LIGHT reactions: minimum gap between any two (s) and per traffic vehicle.
@export var light_cooldown := 0.8
@export var agent_cooldown := 8.0

@export_group("Following traffic")
@export var follower_horn_interval := 1.5
@export_range(0.0, 1.0) var follower_horn_chance := 0.35
@export var follower_horn_radius := 45.0
