class_name ChaseCamera
extends Camera3D
## Low third-person chase camera.
##
## Follows the interpolated vehicle transform every rendered frame. Motion cues
## are deliberately small: lateral lag through yaw smoothing, slight pull-back
## under acceleration, slight push-in under braking, gradual speed FOV, and a
## short damped impulse on collisions. No constant shake.

@export var config: ChaseCameraConfig

var target: TukController

var _yaw := 0.0
var _longitudinal_offset := 0.0
var _impulse_offset := Vector3.ZERO
var _impulse_velocity := Vector3.ZERO
var _last_forward := Vector3.FORWARD
var _roll := 0.0


func _ready() -> void:
	if config == null:
		config = ChaseCameraConfig.new()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = config.base_fov
	near = 0.1
	far = 260.0


func set_target(vehicle: TukController) -> void:
	target = vehicle
	snap_to_target()


func snap_to_target() -> void:
	if target == null:
		return
	var fwd := _flat_forward(target.global_transform)
	_yaw = atan2(-fwd.x, -fwd.z)
	_longitudinal_offset = 0.0
	_impulse_offset = Vector3.ZERO
	_impulse_velocity = Vector3.ZERO
	_place(target.global_transform, 0.0)


## Connected to TukController.impacted.
func on_vehicle_impact(event: CollisionEvent) -> void:
	var strength := config.major_impulse if event.severity == CollisionEvent.Severity.MAJOR else config.minor_impulse
	var direction := event.impulse_direction
	if direction.length_squared() < 0.01:
		direction = Vector3.UP
	_impulse_velocity += (direction * 0.7 + Vector3.UP * 0.3) * strength * 6.0


func _process(delta: float) -> void:
	if target == null:
		return
	var xf := target.get_global_transform_interpolated()
	# While the tuk is on its side or tumbling, hold the heading: following a
	# rolling chassis's forward vector would swing the view around.
	if not target.is_tipped:
		var fwd := _flat_forward(xf)
		var target_yaw := atan2(-fwd.x, -fwd.z)
		_yaw = lerp_angle(_yaw, target_yaw, MathUtil.smoothing(config.yaw_follow, delta))
	var wanted_roll := 0.0
	if not target.is_tipped:
		wanted_roll = clampf(target.roll_deg * config.roll_inheritance, -config.max_camera_roll_deg, config.max_camera_roll_deg)
	_roll = lerpf(_roll, wanted_roll, MathUtil.smoothing(config.roll_response, delta))

	var accel := target.longitudinal_accel
	var wanted := 0.0
	if accel >= 0.0:
		wanted = minf(accel * config.accel_pullback, config.max_pullback)
	else:
		wanted = maxf(accel * config.brake_compression, -config.max_compression)
	_longitudinal_offset = lerpf(_longitudinal_offset, wanted, MathUtil.smoothing(config.longitudinal_response, delta))

	var speed_t := clampf(target.speed_kmh / config.fov_full_speed_kmh, 0.0, 1.0)
	var wanted_fov := lerpf(config.base_fov, config.high_speed_fov, speed_t * speed_t)
	fov = lerpf(fov, wanted_fov, MathUtil.smoothing(config.fov_response, delta))

	# Damped spring for collision impulses.
	var spring_accel := -_impulse_offset * config.impulse_stiffness - _impulse_velocity * config.impulse_damping
	_impulse_velocity += spring_accel * delta
	_impulse_offset += _impulse_velocity * delta

	_place(xf, speed_t)


func _place(xf: Transform3D, speed_t: float) -> void:
	var cam_fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var dist := config.distance + config.speed_distance_add * speed_t + _longitudinal_offset
	var origin := xf.origin
	global_position = origin - cam_fwd * dist + Vector3.UP * config.height + _impulse_offset
	look_at(origin + cam_fwd * config.look_ahead + Vector3.UP * config.look_height, Vector3.UP)
	if absf(_roll) > 0.01:
		rotate_object_local(Vector3.BACK, deg_to_rad(_roll))


func _flat_forward(xf: Transform3D) -> Vector3:
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		return _last_forward
	_last_forward = fwd.normalized()
	return _last_forward
