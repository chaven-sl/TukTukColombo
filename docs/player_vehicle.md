# Player vehicle — three-wheel controller

All values: **PROTOTYPE BASELINE v0.01a** (`data/vehicles/vehicle_tuning.gd`, instance `resources/vehicles/tuk_player_tuning.tres`). Not final tuning. All speeds in this document are **km/h**; the physics code works internally in SI units and converts for anything human-readable.

Design philosophy (from the first human playtest): **high agility + high consequence**, not low agility + artificial safety. The tuk always turns when asked; overcommitting at speed is punished by roll, wheel lift and rollover, not by refusing to steer.

## Model

`TukController` (RigidBody3D, 430 kg, custom CoM, explicit inertia) with three downward wheel rays from fixed mounts:

| Wheel | Mount (local) | Role |
|---|---|---|
| Front | (0, 0.35, −1.0) | steered, braked (40 %) |
| Rear left / right | (∓0.575, 0.35, +1.0) | driven, braked (30 % each), handbrake |

Per physics tick:
1. **Rays** (`force_raycast_update`, world layer only) → compression = travel + radius − hit distance.
2. **Suspension** spring + damper (+ stiff bump stop past travel), applied at the contact point **along the ground normal** (v0.01a fix, see below).
3. **Tyres**: velocity at the contact patch → longitudinal/lateral slip velocity. Lateral force = −slip × cornering stiffness × load ratio, never overshooting zero slip in one step. Longitudinal = drive (rear only) + brakes + rolling resistance (∝ load). Both clamped to a **per-wheel friction circle** (μ × load).
4. **Aero drag** ∝ speed².
5. **Roll assist + roll damping**: restoring torque about the forward axis, strong in town (14 000 N·m/rad up to 25 km/h), fading to 150 by 50 km/h; roll-rate damping 2500. Both release past 30° of roll. Light yaw damping.
6. **Roll state** telemetry: `STABLE → INSIDE_WHEEL_LIGHT (lighter rear wheel < 30 % of static load) → TWO_WHEEL (front + one rear grounded, roll > 4°) → ROLLOVER (up-vector < 60° from vertical)`, emitted as `roll_state_changed(state)`. Debug/state only in v0.01a (future: tyre audio, passenger reaction, camera, warning UI).
7. **Tipped**: ROLLOVER collision event after 0.6 s on its side, automatic recovery to the nearest lane after 2.5 s. **R** resets immediately.

The collision shape is a **convex hull** that tapers from the 1.3 m cabin to a 0.72 m nose (v0.01a fix). The near-miss detector still uses the 1.3 × 2.6 m bounding footprint.

### v0.01a physics defects fixed

Both were found while investigating "it won't roll over, it just washes wide":

1. **Suspension force along the body axis.** At 20°+ of roll the tilted spring force pushed the tuk outward (≈ load × sin(roll) — about 1.5 kN at 22°), cancelling a large share of cornering force. This capped lateral grip at speed and produced the "58–63 m turning radius" understeer. The ground pushes back along its normal, so the force is now applied along the contact normal.
2. **Full-width box collider.** The 1.3 m-wide body box's front corner hit the asphalt at ~22–25° of roll when the tuk pivoted about the front-wheel → outer-rear-wheel axis, propping it up like an outrigger. Ground contacts are not reported as collisions, so it was invisible — and it is why "flat-road steering cannot roll the tuk". The tapered hull matches the real nose.

No scripted rotation or fake tipping torque is involved: rollover now emerges from load transfer.

### Engine

Drive = traction-limited 1050 N at low speed, then power-limited (7.8 kW at the wheels), fading to zero over the last 2.5 km/h before the 70 km/h governor. Reverse: 650 N, limited to 14 km/h. **S** brakes while moving forward and reverses once nearly stopped; **W** brakes while rolling backwards. A parking brake holds the tuk when no pedal is pressed below 1.8 km/h.

### Steering (v0.01a)

Speed-sensitive limit with a smooth ease-out blend `t' = 1 − (1 − t)^1.25` between 35.5° (≤ 15 km/h) and 16° (≥ 70 km/h):

| Speed (km/h) | v0.01 | **v0.01a** | Brief target |
|---|---|---|---|
| ≤ 15 | 34.0° | **35.5°** | 35–36° |
| 20 | 30.9° | 33.3° | — |
| 30 | 25.2° | **29.1°** | 28–30° |
| 40 | 20.3° | 25.1° | — |
| 50 | 16.2° | **21.5°** | 20–22° |
| 60 | 13.1° | **18.3°** | 18–20° |
| 70 | 11.5° | **16.0°** | 15–17° |

Input slews at 3.2 /s towards a held direction and 4.5 /s back to centre or when counter-steering. Unit tests assert the targets, monotonic falloff and no step > 2° per km/h.

## Measured behaviour (headless, deterministic)

### Straight line (`vehicle_handling_test`)

| Scenario | Result |
|---|---|
| 0–40 km/h | 5.75 s |
| 0–60 km/h | 13.0 s |
| Top speed (40 s full throttle) | 68.0 km/h |
| Braking 50 → 0 km/h | 13.3 m, 2.18 s, nose dive 3.1° |
| Reverse | 10.6 km/h after 5 s |
| Full lock at 12 km/h | turning radius 2.9 m |
| Kerb strike 25 km/h at 20° | roll 7.4°, crossed, no tip |

### Swerves and rollover (`vehicle_dynamics_test`, throttle held at entry speed)

"Two-wheel" = time in the TWO_WHEEL state; lateral = sideways displacement achieved by the manoeuvre.

| Scenario | Max roll | Peak lateral g | Lateral | Two-wheel | Result |
|---|---|---|---|---|---|
| A urban swerve 50 km/h (full L → full R, 0.45 s each) | 14.9° | 0.93 | 2.97 m | 0.57 s | recovers on 3 wheels |
| B emergency swerve 60 km/h (full, 0.55 s each) | 20.1° | 0.94 | 4.10 m | 0.77 s | recovers on 3 wheels |
| C top-speed brief swerve 68 km/h (full 0.5 s, −0.6 0.5 s) | 19.2° | 0.98 | 3.73 m | 0.72 s | recovers on 3 wheels |
| D top-speed sustained full lock 68 km/h | 85° | 0.95 | — | 0.78 s | **rolls over** |
| E two-wheel recovery 66 km/h (lock until two-wheel, countersteer 0.4 for 0.6 s) | 13.2° | 0.94 | 2.61 m | 0.47 s | settles on 3 wheels |
| Town lane change 25 km/h (±0.6) | 5.0° | 0.82 | 2.93 m | 0 | stable |
| Town lane change 35 km/h (±0.6) | 6.9° | 0.92 | 3.49 m | 0.08 s | stable |
| Town sustained half lock 30 km/h (5 s) | 6.5° | 0.91 | — | 0 | stable (inside wheel light) |

The "rollover matrix" and "lane change" tables are in `docs/PROTOTYPE_V001A_REPORT.md`.

### Observations

- Town (≤ 35 km/h) stays planted: roll ≤ 7°, no two-wheel moments in normal lane changes.
- From ~45 km/h big inputs lift the inside rear wheel; the two-wheel phase lasts ~0.5–0.8 s and is recoverable by releasing or countersteering.
- **Sustained full lock rolls the tuk at ≥ 50 km/h** after ~0.8–0.9 s on two wheels; at 40 km/h it scrubs speed and stays upright.
- Holding half lock for 4 s at 60 km/h also rolls it (v0.01 handling scenario, now intentionally "risky").
- Lateral grip peaks ~0.93–0.98 g; v0.01 was effectively capped near 0.72 g (understeer).
- The two-wheel window before a sustained turn becomes a rollover (~0.8 s) is the key playtest number: too short feels unfair, too long feels safe.

## Most influential tuning variables

`roll_assist_damping` (swerve recoverability vs sustained rollover), `center_of_mass.y`, `roll_assist_high_speed` / `roll_assist_fade_*_kmh`, `roll_assist_cutoff_deg`, `front_grip_multiplier`, `cornering_stiffness`, `high_speed_steer_angle_deg`, `steer_falloff_exponent`, `steering_response`, `tyre_force_height` (raise to reduce roll moment).

A sweep of CoM height with the old box collider (0.61 → 0.70 m) left the roll plateau at 24–26°, which is how the collider defect was isolated. With the hull: CoM 0.61 m + damping 900 rolled over on a 50 km/h lane change (too fragile); damping 2500 separates brief swerves (recoverable) from sustained overcommitment (rollover); damping 4000 made brief swerves too tame (C rolled only 12°).

## Collisions

Body contact classifies by the player's horizontal speed change across the contact: < 5.4 km/h ignored, < 21.6 km/h MINOR, ≥ 21.6 km/h MAJOR (keeps 55 % of velocity, stronger camera impulse). 0.6 s cooldown. Any traffic contact also marks the agent so in-progress near-miss candidates on it are rejected, and makes the agent hold for 1.5 s. Ground contacts are ignored.

## Camera during instability

The chase camera inherits 15 % of chassis roll (capped at 5°, smoothed), so two-wheel moments read on screen without the horizon swinging with the chassis. While the tuk is on its side or tumbling, the camera holds its heading instead of following the rolling chassis. Verified with windowed screenshots of a 60 km/h two-wheel moment and a 68 km/h rollover.
