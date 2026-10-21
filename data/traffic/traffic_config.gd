class_name TrafficConfig
extends Resource
## Population and spawning rules for TrafficManager. PROTOTYPE BASELINE.

## Desired number of active agents around the player (gameplay density).
@export var gameplay_density_target := 14

@export_group("Spawning")
@export var spawn_interval := 0.2
@export var spawn_attempts := 16
## Normal spawns happen in this distance band from the player...
@export var spawn_min_distance := 75.0
@export var spawn_max_distance := 170.0
## When the player is moving, spawn only ahead of them (traffic is wasted
## behind a player who is driving away from it).
@export var spawn_ahead_only := true
## Agents this far behind the player (and out of view) are recycled ahead.
@export var behind_despawn_distance := 45.0
## ...and must be outside the camera view unless farther than this
## (the fog hides anything beyond it).
@export var hidden_distance := 110.0
## First fill at level start may spawn closer, but never right ahead.
@export var initial_spawn_min_distance := 30.0
@export var initial_clear_ahead := 60.0
## Minimum distance along a lane to the nearest other agent.
@export var min_spawn_separation := 22.0
## Minimum straight-line distance to any other agent.
@export var min_spawn_clearance := 12.0
## Chance a spawn uses a tunnel source lane instead of a road slot.
@export_range(0.0, 1.0) var source_spawn_chance := 0.25

@export_group("Despawning")
@export var despawn_distance := 190.0
## Agents stopped this long and out of view are recycled (anti-deadlock).
@export var stuck_despawn_seconds := 30.0

@export_group("Behaviour")
## Agents treat the player as an obstacle within this distance ahead.
@export var player_detection_distance := 45.0
## Route weights at junctions (connector movements).
@export var turn_weight_straight := 0.6
@export var turn_weight_left := 0.22
@export var turn_weight_right := 0.18
## Hold time after the player hits an agent.
@export var collision_hold_seconds := 1.5
