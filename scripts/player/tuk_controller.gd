class_name TukController
extends RigidBody3D
## Original three-wheel raycast vehicle for the player tuk.
##
## One steered front wheel and two driven rear wheels. Each wheel is a
## downward ray with a spring-damper and a slip-velocity tyre model limited by
## a per-wheel friction circle. VehicleBody3D is deliberately not used: the
## single front wheel gives a narrow stability triangle, and owning the forces
## lets the tuk roll, lean and (when abused at speed) tip like a real one.
##
## Body roll, pitch under acceleration/braking and kerb disturbances come from
## real forces at the contact points. A speed-faded roll assist keeps normal
## driving forgiving; it lets go past a cutoff so extreme steering at speed is
## genuinely dangerous.

signal impacted(event: CollisionEvent)
signal was_reset()
## Stability telemetry for future tyre audio, passenger reactions, camera or
## warning UI. v0.01a: debug/state only.
signal roll_state_changed(state: RollState)

enum RollState { STABLE, INSIDE_WHEEL_LIGHT, TWO_WHEEL, ROLLOVER }

const FRONT := 0
const REAR_LEFT := 1
const REAR_RIGHT := 2
const WHEEL_COUNT := 3
const WORLD_MASK := 1
const PLAYER_LAYER := 2
const TRAFFIC_LAYER := 4

@export var tuning: VehicleTuning

## Written by an input source (keyboard, touch, autopilot).
var input := VehicleInputState.new()
## Callable(Vector3) -> Transform3D giving a safe pose for resets.
var reset_pose_provider: Callable

# --- Telemetry (HUD, camera, debug, tests) ---
var forward_speed := 0.0
var speed_kmh := 0.0
var steer_input := 0.0
var steer_angle_deg := 0.0
var roll_deg := 0.0
var pitch_deg := 0.0
var lateral_accel := 0.0
var longitudinal_accel := 0.0
var grounded_wheels := 0
var is_tipped := false
var roll_state: RollState = RollState.STABLE
## Load on the more lightly loaded rear wheel as a fraction of its static load.
var inside_wheel_load_ratio := 1.0
var wheel_grounded := PackedByteArray([0, 0, 0])
var wheel_compression := PackedFloat32Array([0.0, 0.0, 0.0])
var wheel_load := PackedFloat32Array([0.0, 0.0, 0.0])
var wheel_contact := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var wheel_force := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var mount_points_local := PackedVector3Array()

var _rays: Array[RayCast3D] = []
var _contact_normal := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
var _prev_compression := PackedFloat32Array([0.0, 0.0, 0.0])
var _static_load := PackedFloat32Array([1.0, 1.0, 1.0])
var _wheel_spin := PackedFloat32Array([0.0, 0.0, 0.0])
var _prev_velocity := Vector3.ZERO
var _tick_velocity := Vector3.ZERO
var _tipped_time := 0.0
var _rollover_reported := false
var _last_impact_time := -100.0
var _pending_major_slowdown := false
var _reset_requested := false

@onready var _front_steer: Node3D = $Visual/FrontSteer
@onready var _wheel_nodes: Array[Node3D] = [$Visual/FrontSteer, $Visual/RearLeft, $Visual/RearRight]
@onready var _spin_nodes: Array[Node3D] = [$Visual/FrontSteer/Spin, $Visual/RearLeft/Spin, $Visual/RearRight/Spin]


func _ready() -> void:
	if tuning == null:
		tuning = VehicleTuning.new()
	mass = tuning.mass_kg
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = tuning.center_of_mass
	inertia = tuning.inertia
	can_sleep = false
	# Drag, rolling resistance and roll/yaw damping are modelled explicitly;
	# the engine's default body damping would add ~400 N of hidden drag.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = tuning.angular_damp
	contact_monitor = true
	max_contacts_reported = 6
	collision_layer = PLAYER_LAYER
	collision_mask = WORLD_MASK | TRAFFIC_LAYER
	body_entered.connect(_on_body_entered)
	_build_wheels()


func _build_wheels() -> void:
	var t := tuning
	var half_track := t.rear_track * 0.5
	var half_wb := t.wheelbase * 0.5
	mount_points_local = PackedVector3Array([
		Vector3(0.0, t.mount_height, -half_wb),
		Vector3(-half_track, t.mount_height, half_wb),
		Vector3(half_track, t.mount_height, half_wb),
	])
	for i in WHEEL_COUNT:
		var ray := RayCast3D.new()
		ray.name = "WheelRay%d" % i
		ray.position = mount_points_local[i]
		ray.target_position = Vector3(0.0, -(t.suspension_travel + t.wheel_radius), 0.0)
		ray.collision_mask = WORLD_MASK
		ray.add_exception(self)
		add_child(ray)
		_rays.append(ray)
		_wheel_nodes[i].position = Vector3(mount_points_local[i].x, t.wheel_radius, mount_points_local[i].z)
	# Static load split from the CoM position between the axles.
	var weight := t.mass_kg * 9.81
	var front_share := clampf((half_wb - t.center_of_mass.z) / t.wheelbase, 0.1, 0.9)
	_static_load[FRONT] = weight * front_share
	_static_load[REAR_LEFT] = weight * (1.0 - front_share) * 0.5
	_static_load[REAR_RIGHT] = _static_load[REAR_LEFT]


func request_reset() -> void:
	_reset_requested = true


func half_extents() -> Vector2:
	return Vector2(tuning.body_size.x * 0.5, tuning.body_size.z * 0.5)


func _physics_process(delta: float) -> void:
	var ps := PerfSections.begin()
	_physics_process_body(delta)
	PerfSections.end(PerfSections.PLAYER_PHYSICS, ps)


func _physics_process_body(delta: float) -> void:
	if _reset_requested:
		_reset_requested = false
		_perform_reset()
		return
	if _pending_major_slowdown:
		_pending_major_slowdown = false
		linear_velocity *= tuning.major_collision_speed_retention

	var t := tuning
	var xf := global_transform
	var up := xf.basis.y
	var fwd := -xf.basis.z
	var right := xf.basis.x
	_prev_velocity = linear_velocity

	forward_speed = linear_velocity.dot(fwd)
	speed_kmh = absf(forward_speed) * 3.6
	var accel := (linear_velocity - _tick_velocity) / delta
	_tick_velocity = linear_velocity
	lateral_accel = lerpf(lateral_accel, accel.dot(right), 0.15)
	longitudinal_accel = lerpf(longitudinal_accel, accel.dot(fwd), 0.15)

	_update_steering(delta)
	var steer_rad := deg_to_rad(steer_angle_deg)

	# --- Driver intent -> total drive and brake force ---
	var drive_total := 0.0
	var brake_total := 0.0
	if input.throttle > 0.01:
		if forward_speed < -0.8:
			brake_total += t.brake_force * input.throttle
		else:
			drive_total += t.drive_force * input.throttle * t.drive_curve(forward_speed)
	if input.brake > 0.01:
		if forward_speed > 0.8:
			brake_total += t.brake_force * input.brake
		elif input.throttle <= 0.01:
			drive_total -= t.reverse_force * input.brake * t.reverse_curve(-forward_speed)
	if input.throttle <= 0.01 and input.brake <= 0.01 and absf(forward_speed) < 0.5:
		brake_total += t.parking_brake_force

	# --- Pass 1: wheel rays ---
	grounded_wheels = 0
	var grounded_rear := 0
	for i in WHEEL_COUNT:
		var ray := _rays[i]
		ray.force_raycast_update()
		if ray.is_colliding():
			var hit := ray.get_collision_point()
			var mount := xf * mount_points_local[i]
			wheel_grounded[i] = 1
			wheel_compression[i] = (t.suspension_travel + t.wheel_radius) - mount.distance_to(hit)
			wheel_contact[i] = hit
			_contact_normal[i] = ray.get_collision_normal()
			grounded_wheels += 1
			if i != FRONT:
				grounded_rear += 1
		else:
			wheel_grounded[i] = 0
			wheel_compression[i] = 0.0

	# --- Pass 2: suspension and tyre forces ---
	var mass_share := mass / float(WHEEL_COUNT)
	for i in WHEEL_COUNT:
		if wheel_grounded[i] == 0:
			_prev_compression[i] = 0.0
			wheel_load[i] = 0.0
			wheel_force[i] = Vector3.ZERO
			continue
		var is_front := i == FRONT
		var comp := wheel_compression[i]
		var comp_velocity := (comp - _prev_compression[i]) / delta
		_prev_compression[i] = comp
		var spring := t.spring_front if is_front else t.spring_rear
		var damper := t.damping_front if is_front else t.damping_rear
		var f_susp := spring * comp + damper * comp_velocity
		if comp > t.suspension_travel:
			f_susp += t.bump_stop_stiffness * (comp - t.suspension_travel)
		f_susp = maxf(f_susp, 0.0)
		wheel_load[i] = f_susp
		var offset := wheel_contact[i] - xf.origin
		var n := _contact_normal[i]
		# The ground pushes back along its normal. Applying the spring force
		# along the (rolled) body axis instead would add a sideways push that
		# grows with roll and cancels cornering force (v0.01 understeer defect).
		apply_force(n * f_susp, offset)

		var wheel_fwd := fwd.rotated(up, -steer_rad) if is_front else fwd
		wheel_fwd = (wheel_fwd - n * wheel_fwd.dot(n)).normalized()
		var wheel_right := wheel_fwd.cross(n)
		var point_velocity := linear_velocity + angular_velocity.cross(offset)
		var v_long := point_velocity.dot(wheel_fwd)
		var v_lat := point_velocity.dot(wheel_right)

		# Lateral: slip-velocity model, scaled by load, never overshooting
		# zero slip within one step.
		var load_ratio := clampf(f_susp / maxf(_static_load[i], 1.0), 0.0, 2.0)
		var f_lat := -v_lat * t.cornering_stiffness * load_ratio
		var lat_cap := absf(v_lat) * mass_share / delta
		f_lat = clampf(f_lat, -lat_cap, lat_cap)

		# Longitudinal: drive (rear), brakes, rolling resistance.
		var f_long := 0.0
		if not is_front and grounded_rear > 0:
			f_long += drive_total / float(grounded_rear)
		var wheel_brake := brake_total * (t.brake_front_bias if is_front else (1.0 - t.brake_front_bias) * 0.5)
		var handbraking := input.handbrake and not is_front
		if handbraking:
			wheel_brake += t.handbrake_force * 0.5
		if wheel_brake > 0.0:
			var stop_cap := absf(v_long) * mass_share / delta
			f_long -= signf(v_long) * minf(wheel_brake, stop_cap)
		f_long -= clampf(v_long * 2.0, -1.0, 1.0) * t.rolling_resistance * f_susp

		# Friction circle.
		var grip := t.tyre_grip * (t.front_grip_multiplier if is_front else t.rear_grip_multiplier)
		var max_force := grip * f_susp
		if handbraking:
			f_lat = clampf(f_lat, -max_force * t.handbrake_rear_grip, max_force * t.handbrake_rear_grip)
		var magnitude := sqrt(f_long * f_long + f_lat * f_lat)
		if magnitude > max_force and magnitude > 0.0:
			var circle_scale := max_force / magnitude
			f_long *= circle_scale
			f_lat *= circle_scale
		var tyre_force := wheel_fwd * f_long + wheel_right * f_lat
		apply_force(tyre_force, offset + up * t.tyre_force_height)
		wheel_force[i] = tyre_force
		_wheel_spin[i] = fmod(_wheel_spin[i] + v_long / t.wheel_radius * delta, TAU)

	# --- Aero drag ---
	var horizontal_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	apply_central_force(-horizontal_velocity * horizontal_velocity.length() * t.drag_coefficient)

	# --- Stability: speed-faded roll assist and light yaw damping ---
	var tilt := up.cross(Vector3.UP)
	var roll_sin := tilt.dot(fwd)
	roll_deg = rad_to_deg(asin(clampf(roll_sin, -1.0, 1.0)))
	pitch_deg = rad_to_deg(asin(clampf(tilt.dot(right), -1.0, 1.0)))
	if grounded_wheels >= 2:
		if absf(roll_deg) < t.roll_assist_cutoff_deg:
			var roll_rate := angular_velocity.dot(fwd)
			var stiffness := t.roll_assist_at(speed_kmh)
			apply_torque(fwd * (roll_sin * stiffness - roll_rate * t.roll_assist_damping))
		apply_torque(-up * angular_velocity.dot(up) * t.yaw_damping)

	_update_tipped(delta, up)
	_update_roll_state()
	_update_wheel_visuals(steer_rad)


func _update_roll_state() -> void:
	inside_wheel_load_ratio = minf(wheel_load[REAR_LEFT] / maxf(_static_load[REAR_LEFT], 1.0),
			wheel_load[REAR_RIGHT] / maxf(_static_load[REAR_RIGHT], 1.0))
	var state := RollState.STABLE
	if is_tipped:
		state = RollState.ROLLOVER
	elif grounded_wheels == 2 and wheel_grounded[FRONT] == 1 and absf(roll_deg) > 4.0:
		state = RollState.TWO_WHEEL
	elif inside_wheel_load_ratio < tuning.inside_wheel_light_load and grounded_wheels >= 2:
		state = RollState.INSIDE_WHEEL_LIGHT
	if state != roll_state:
		roll_state = state
		roll_state_changed.emit(state)


func _update_steering(delta: float) -> void:
	var t := tuning
	var target := clampf(input.steer, -1.0, 1.0)
	var holding := absf(target) > 0.01 and (signf(target) == signf(steer_input) or absf(steer_input) < 0.01)
	var rate := t.steering_response if holding else t.steering_return_speed
	steer_input = move_toward(steer_input, target, rate * delta)
	steer_angle_deg = steer_input * t.steer_limit_deg(speed_kmh)


func _update_tipped(delta: float, up: Vector3) -> void:
	is_tipped = up.y < 0.5
	if not is_tipped:
		_tipped_time = 0.0
		_rollover_reported = false
		return
	_tipped_time += delta
	if _tipped_time > 0.6 and not _rollover_reported:
		_rollover_reported = true
		var ev := CollisionEvent.new()
		ev.severity = CollisionEvent.Severity.MAJOR
		ev.kind = CollisionEvent.Kind.ROLLOVER
		ev.impact_speed = linear_velocity.length()
		ev.position = global_position
		ev.timestamp = SimClock.now()
		impacted.emit(ev)
		EventBus.collision_event.emit(ev)
	if _tipped_time > tuning.auto_recover_tipped_seconds:
		_reset_requested = true


func _update_wheel_visuals(steer_rad: float) -> void:
	var t := tuning
	for i in WHEEL_COUNT:
		var node := _wheel_nodes[i]
		var extension := t.suspension_travel
		if wheel_grounded[i] == 1:
			extension = t.suspension_travel - clampf(wheel_compression[i], 0.0, t.suspension_travel)
		node.position.y = mount_points_local[i].y - extension
		_spin_nodes[i].rotation.x = -_wheel_spin[i]
	_front_steer.rotation.y = -steer_rad


func _on_body_entered(body: Node) -> void:
	if body.has_meta(&"is_ground"):
		return
	var now := SimClock.now()
	var agent := body as TrafficAgent
	if agent != null:
		agent.notify_player_contact(now)
	var delta_v := _prev_velocity - linear_velocity
	delta_v.y = 0.0
	var impact := delta_v.length()
	if impact * 3.6 < tuning.collision_minor_speed_kmh or now - _last_impact_time < tuning.impact_cooldown:
		return
	_last_impact_time = now
	var ev := CollisionEvent.new()
	ev.severity = CollisionEvent.Severity.MAJOR if impact * 3.6 >= tuning.collision_major_speed_kmh else CollisionEvent.Severity.MINOR
	ev.kind = CollisionEvent.Kind.TRAFFIC if agent != null else CollisionEvent.Kind.WORLD
	ev.impact_speed = impact
	ev.position = global_position
	ev.impulse_direction = (-delta_v).normalized()
	ev.other_agent_id = agent.agent_id if agent != null else -1
	ev.other_body = body as Node3D
	var fwd := -global_transform.basis.z
	ev.approach_speed_kmh = absf(_prev_velocity.dot(fwd)) * 3.6
	ev.frontal = clampf(absf(ev.impulse_direction.dot(fwd)), 0.0, 1.0)
	ev.timestamp = now
	if ev.severity == CollisionEvent.Severity.MAJOR:
		_pending_major_slowdown = true
	impacted.emit(ev)
	EventBus.collision_event.emit(ev)


func _perform_reset() -> void:
	var pose := Transform3D(MathUtil.basis_from_forward(-global_transform.basis.z), global_position + Vector3.UP * 0.5)
	if reset_pose_provider.is_valid():
		pose = reset_pose_provider.call(global_position)
	teleport(pose)


## Places the tuk at `pose` at rest. Used for spawn, R reset and auto-recovery.
func teleport(pose: Transform3D) -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = pose
	_prev_velocity = Vector3.ZERO
	_tick_velocity = Vector3.ZERO
	steer_input = 0.0
	steer_angle_deg = 0.0
	forward_speed = 0.0
	speed_kmh = 0.0
	lateral_accel = 0.0
	longitudinal_accel = 0.0
	is_tipped = false
	roll_state = RollState.STABLE
	_tipped_time = 0.0
	_rollover_reported = false
	_pending_major_slowdown = false
	for i in WHEEL_COUNT:
		_prev_compression[i] = 0.0
	input.clear()
	reset_physics_interpolation()
	was_reset.emit()
	EventBus.player_reset.emit()
