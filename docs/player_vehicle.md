# Player vehicle — three-wheel controller

All values: **PROTOTYPE BASELINE** (`data/vehicles/vehicle_tuning.gd`, instance `resources/vehicles/tuk_player_tuning.tres`). Not final tuning.

## Model

`TukController` (RigidBody3D, 430 kg, custom CoM, explicit inertia) with three downward wheel rays from fixed mounts:

| Wheel | Mount (local) | Role |
|---|---|---|
| Front | (0, 0.35, −1.0) | steered, braked (40 %) |
| Rear left / right | (∓0.575, 0.35, +1.0) | driven, braked (30 % each), handbrake |

Per physics tick:
1. **Rays** (`force_raycast_update`, world layer only) → compression = travel + radius − hit distance.
2. **Suspension** spring + damper (+ stiff bump stop past travel) applied at the contact point along body up.
3. **Tyres**: velocity at the contact patch → longitudinal/lateral slip velocity. Lateral force = −v_lat × cornering stiffness × load ratio, capped so it never overshoots zero slip in one step. Longitudinal = drive (rear only) + brakes (never reversing the wheel) + rolling resistance (∝ load). Both clamped to a **per-wheel friction circle** (μ × load).
4. **Aero drag** ∝ v².
5. **Roll assist**: restoring torque about the forward axis, strong at low speed (5500 N·m/rad) fading to 500 by 65 km/h, released past 32° of roll so a real tip-over can happen. Light yaw damping.
6. **Tipped detection** (up.y < 0.5): ROLLOVER event after 0.6 s, automatic recovery to the nearest lane after 2.5 s. **R** resets immediately.

No `VehicleBody3D`, no artificial anti-tip clamp. Body roll, nose dive and squat come from real forces at the contact points (CoM above the contact plane).

### Engine

Drive = traction-limited 1050 N at low speed, then power-limited (7.8 kW at the wheels), faded to zero across the last 2.5 km/h before the 70 km/h governor. Reverse: 650 N, limited to 14 km/h. **S** brakes while moving forward and reverses once nearly stopped; **W** brakes while rolling backwards. A parking brake holds the tuk when no pedal is pressed below 0.5 m/s.

### Steering

Speed-sensitive limit, smooth ease-out blend `t' = 1 − (1 − t)^1.55` between 34° (≤15 km/h) and 11.5° (≥70 km/h):

| Speed | Max front-wheel angle |
|---|---|
| ≤ 15 km/h | 34.0° |
| 30 km/h | 25.2° |
| 50 km/h | 16.2° |
| 70 km/h | 11.5° |

Input slews at 3.2 /s towards a held direction and 4.5 /s back to centre or when counter-steering. Unit test asserts monotonic and no step >2° per km/h.

## Measured behaviour (headless, `tests/scenarios/vehicle_handling_test.tscn`)

| Scenario | Result |
|---|---|
| Static sag | front 0.094 m, rear 0.071 m of 0.22 m travel |
| 0–40 km/h | **5.73 s** (target 5.5–7) |
| 0–60 km/h | 12.5 s |
| Top speed (40 s full throttle) | **68.2 km/h** (target ≈70) |
| Braking 50→0 | 13.8 m, 2.37 s, nose dive 2.85° |
| Reverse | 9.6 km/h after 5 s |
| Full lock at 12 km/h | turning radius **3.2 m**, roll 4.1°, upright |
| Half lock at 30 km/h | radius 10.1 m, 0.71 g, roll **7.6°** (inner wheel momentarily light), upright |
| Full lock at 30 km/h | radius 9.2 m (front-grip limited), roll 6.7° |
| Half lock at 60 km/h | roll **21.5°, on two wheels**, 0.45 g, radius 58 m (heavy understeer) |
| Full lock at 65 km/h | roll 22°, two wheels, did not tip |
| Full-lock flick L→R at 60 km/h | roll 20.8°, did not tip |
| Slalom ±0.7 at 45 km/h | roll 13°, recovered upright, yaw settled |
| Kerb strike 25 km/h at 20° | roll 7.5°, pitch 2.5°, compression 0.197 m, crossed, no tip |
| Reset from lying on side | upright, 3 wheels grounded |

### Observations

- Low-speed agility is very tuk-like (3.2 m radius, large lock).
- Roll is clearly visible from ~25 km/h and becomes dramatic (two-wheel lift) above ~50 km/h with large inputs. This is the "warning" behaviour.
- On flat road, steady steering **does not tip** the tuk: the lightly loaded front tyre saturates first (understeer), capping lateral acceleration (~0.45 g at 60 km/h) below the tip threshold, so the tuk balances at ~22°. Tip-overs need an additional disturbance (kerb while cornering, collision). Playtest should decide whether this is "risky enough".
- High-speed understeer makes big steering inputs at 60+ km/h feel weak. Knobs: `front_grip_multiplier`, `cornering_stiffness`, `high_speed_steer_angle_deg`.
- A sensitivity sweep of CoM height (0.55 / 0.57 / 0.58 / 0.62 m) showed roll at 30 km/h half-lock of 6.6° / 7.6° / 8.4° / 12°. 0.57 chosen.

## Most influential tuning variables

`center_of_mass.y`, `roll_assist_high_speed`, `roll_assist_cutoff_deg`, `front_grip_multiplier`, `cornering_stiffness`, `high_speed_steer_angle_deg`, `steer_falloff_exponent`, `steering_response`, `engine_power_w`, `spring_*`/`damping_*`, `tyre_force_height` (raise to reduce roll moment).

## Collisions

Body contact (`contact_monitor`) classifies by the player's horizontal velocity change across the contact: < 1.5 m/s ignored, < 6 m/s MINOR, ≥ 6 m/s MAJOR (keeps 55 % of velocity, stronger camera impulse). 0.6 s cooldown. Any traffic contact also marks the agent (`last_collision_time`) so in-progress near-miss candidates on it are rejected, and makes the agent hold for 1.5 s. Ground contacts are ignored.
