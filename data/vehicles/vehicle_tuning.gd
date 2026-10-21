class_name VehicleTuning
extends Resource
## Player tuk handling parameters.
## PROTOTYPE BASELINE — every value here is a starting point for playtesting,
## not a final tuning. Units are SI (kg, m, N, s) unless the name says km/h.

@export_group("Body")
@export var mass_kg := 430.0
## Local centre of mass (z+ is towards the rear). Below the geometric centre,
## but high enough that body roll and tipping risk stay real.
@export var center_of_mass := Vector3(0.0, 0.61, 0.25)
## Principal inertia: x = pitch, y = yaw, z = roll.
@export var inertia := Vector3(330.0, 300.0, 150.0)
## Near-miss footprint (bounding box). The physics collision shape is a
## convex hull in player_tuk.tscn that tapers to the narrow nose; a full-width
## box scraped the asphalt at ~22° roll and propped the tuk up (v0.01 defect).
@export var body_size := Vector3(1.3, 1.43, 2.6)
@export var body_center := Vector3(0.0, 0.985, 0.05)

@export_group("Geometry")
@export var wheelbase := 2.0
@export var rear_track := 1.15
@export var wheel_radius := 0.21
## Local Y of the top of suspension travel (ray origin).
@export var mount_height := 0.35

@export_group("Suspension")
@export var suspension_travel := 0.22
@export var spring_front := 17000.0
@export var spring_rear := 18500.0
@export var damping_front := 2300.0
@export var damping_rear := 2600.0
@export var bump_stop_stiffness := 60000.0

@export_group("Tyres")
## Friction coefficient for the per-wheel friction circle.
@export var tyre_grip := 0.95
@export var front_grip_multiplier := 1.03
@export var rear_grip_multiplier := 1.0
## Lateral force per m/s of sideways slip at static load, N/(m/s)
## (≈ N per 3.6 km/h of slip).
@export var cornering_stiffness := 5200.0
## Raises the tyre force application point towards the CoM (m). 0 = contact
## patch (maximum roll moment). Higher = less roll / tipping.
@export var tyre_force_height := 0.0
@export var handbrake_rear_grip := 0.45
## Rolling resistance coefficient (fraction of wheel load).
@export var rolling_resistance := 0.015
## Aero drag: N per (m/s)^2.
@export var drag_coefficient := 0.75

@export_group("Engine and brakes")
## Governed top speed; drive fades out over the last governor_band_kmh.
@export var top_speed_kmh := 70.0
@export var governor_band_kmh := 2.5
## Traction-limited rear drive force at low speed (N).
@export var drive_force := 1050.0
## Engine power at the wheels (W). Above ~25 km/h drive is power-limited.
@export var engine_power_w := 7800.0
@export var brake_force := 3800.0
@export_range(0.0, 1.0) var brake_front_bias := 0.4
@export var reverse_force := 650.0
@export var max_reverse_speed_kmh := 14.0
@export var handbrake_force := 1400.0
## Holds the tuk still when no pedal is pressed at walking pace.
@export var parking_brake_force := 900.0

@export_group("Steering")
## Maximum front wheel angle at or below steer_low_speed_kmh.
@export var max_steer_angle_deg := 35.5
## Front wheel angle at steer_high_speed_kmh and above.
@export var high_speed_steer_angle_deg := 16.0
@export var steer_low_speed_kmh := 15.0
@export var steer_high_speed_kmh := 70.0
## Ease-out exponent of the blend: t' = 1 - (1 - t)^k. Higher drops the
## angle earlier. 1.25 gives ~29 deg at 30 km/h, ~21.5 at 50, ~18 at 60 and
## 16 at 70 km/h, with a finite slope everywhere (no kink at 15 km/h).
@export var steer_falloff_exponent := 1.25
## Steering input units per second towards a held direction.
@export var steering_response := 3.2
## Steering input units per second back to centre / when counter-steering.
@export var steering_return_speed := 4.5

@export_group("Stability")
## Roll-restoring torque (N·m per rad) while grounded. Fades with speed so
## the tuk is forgiving in town and genuinely risky when fast.
@export var roll_assist_low_speed := 14000.0
@export var roll_assist_high_speed := 150.0
@export var roll_assist_fade_start_kmh := 25.0
@export var roll_assist_fade_end_kmh := 50.0
@export var roll_assist_damping := 2500.0
## Beyond this roll angle the assist lets go: a real tip-over.
@export var roll_assist_cutoff_deg := 30.0
@export var yaw_damping := 150.0
## Generic body angular damping (replaces the project default).
@export var angular_damp := 0.3

@export_group("Collisions and recovery")
## Player speed change across a contact (km/h) below which it is ignored.
@export var collision_minor_speed_kmh := 5.4
## Player speed change across a contact (km/h) at or above which it is MAJOR.
@export var collision_major_speed_kmh := 21.6
## Fraction of velocity kept after a major collision.
@export var major_collision_speed_retention := 0.55
@export var impact_cooldown := 0.6
## Roll-state telemetry thresholds (fraction of static wheel load).
@export var inside_wheel_light_load := 0.3
## Seconds on its side before the tuk is automatically put back on the road.
@export var auto_recover_tipped_seconds := 2.5


## Speed-sensitive steering limit, blended smoothly (no hard clamp steps).
func steer_limit_deg(speed_kmh: float) -> float:
	var span := maxf(steer_high_speed_kmh - steer_low_speed_kmh, 0.01)
	var t := clampf((speed_kmh - steer_low_speed_kmh) / span, 0.0, 1.0)
	t = 1.0 - pow(1.0 - t, steer_falloff_exponent)
	return lerpf(max_steer_angle_deg, high_speed_steer_angle_deg, t)


## Fraction of drive force available at a forward speed (internal m/s; km/h = ×3.6).
func drive_curve(forward_speed: float) -> float:
	var v := maxf(forward_speed, 0.0)
	var power_limit := 1.0
	if v > 0.1:
		power_limit = minf(1.0, engine_power_w / (drive_force * v))
	var top := top_speed_kmh / 3.6
	var band := maxf(governor_band_kmh / 3.6, 0.1)
	var governor := clampf((top - v) / band, 0.0, 1.0)
	return power_limit * governor


## Fraction of reverse force available at a reverse speed (internal m/s, positive).
func reverse_curve(reverse_speed: float) -> float:
	return clampf(1.0 - reverse_speed / (max_reverse_speed_kmh / 3.6), 0.0, 1.0)


func roll_assist_at(speed_kmh: float) -> float:
	var span := maxf(roll_assist_fade_end_kmh - roll_assist_fade_start_kmh, 0.01)
	var t := clampf((speed_kmh - roll_assist_fade_start_kmh) / span, 0.0, 1.0)
	return lerpf(roll_assist_low_speed, roll_assist_high_speed, t)
