class_name TrafficVehicleClass
extends Resource
## One logical traffic vehicle type. Behaviour and placeholder look are data.

enum Kind { CAR, BUS, MOTORCYCLE, TUK }

@export var id: StringName = &"car"
@export var kind: Kind = Kind.CAR

@export_group("Size")
@export var length := 4.3
@export var width := 1.8
@export var height := 1.5

@export_group("Speed")
@export var min_speed_kmh := 25.0
@export var max_speed_kmh := 48.0
@export var max_accel := 2.2
## Normal braking used for planning (stop lines, curves, followers).
@export var comfortable_decel := 3.0
## Hard limit. Agents never decelerate faster than this.
@export var max_decel := 7.0

@export_group("Following")
## Desired time gap to the vehicle ahead (s).
@export var time_headway := 1.3
## Bumper-to-bumper standstill gap (m).
@export var min_gap := 2.5
## Reserved for lane changing (not implemented in v0.01).
@export_range(0.0, 1.0) var lane_change_tendency := 0.0

@export_group("Population")
@export var spawn_weight := 1.0
## Number of pooled instances created for this class.
@export var pool_count := 6
@export var body_colors := PackedColorArray([Color(0.85, 0.85, 0.85)])
