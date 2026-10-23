class_name VehicleDamageConfig
extends Resource
## Crash consequence tunables (v0.03A2). PROTOTYPE BASELINE. Not an RPG health
## bar: an incident/recovery state. Speeds are km/h of the impact's velocity
## change (CollisionEvent.impact_speed_kmh) — measured head-on into a building
## the tuk stops dead, so the change ≈ the approach speed (15→15, 22→22,
## 30→30, 40→40, 50→48 km/h); glancing hits produce a smaller change.

## Below this: LIGHT (scrape / slow bump) — no damage, keep driving.
@export var hard_min_kmh := 16.0
## At or above this: DISABLING. Between: HARD → DAMAGED.
@export var disabling_min_kmh := 33.0
## HARD: engine cut (immobilised) for this long, then limp.
@export var immobilised_seconds := 1.2
## DAMAGED limp: throttle scale and how long until HEALTHY again.
@export_range(0.1, 1.0) var limp_throttle := 0.6
@export var limp_seconds := 8.0
## DISABLED: total time before the road reset (comes to rest first).
@export var recovery_delay := 2.0
## After a reset, impacts are ignored this long (prevents reset loops).
@export var post_reset_grace := 1.5
