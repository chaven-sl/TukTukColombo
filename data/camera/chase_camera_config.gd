class_name ChaseCameraConfig
extends Resource
## Low third-person chase camera. PROTOTYPE BASELINE.
## Priority is traffic readability: restrained motion, no constant shake.

@export var base_fov := 67.0
@export var high_speed_fov := 76.0
## Speed (km/h) at which the high-speed FOV is fully reached.
@export var fov_full_speed_kmh := 70.0
@export var fov_response := 2.5

@export var distance := 6.3
## Extra distance added gradually at full speed.
@export var speed_distance_add := 0.5
@export var height := 2.8
@export var look_ahead := 18.0
@export var look_height := 2.4

## How quickly the camera swings behind the tuk (lower = more lateral lag).
@export var yaw_follow := 4.5
## Metres of pull-back per m/s^2 of forward acceleration.
@export var accel_pullback := 0.12
## Metres of push-in per m/s^2 of braking.
@export var brake_compression := 0.08
@export var max_pullback := 0.45
@export var max_compression := 0.5
@export var longitudinal_response := 3.0

## Collision impulse spring (short and restrained).
@export var impulse_stiffness := 120.0
@export var impulse_damping := 16.0
@export var minor_impulse := 0.6
@export var major_impulse := 1.6
