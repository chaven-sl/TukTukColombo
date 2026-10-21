# Prototype v0.01a Report — Handling Calibration Sprint

Date: 2026-10-21 · Godot 4.7.2 · tested headless on Apple M2 · **all speeds in km/h**

Status: **PASS — awaiting human playtest.** All automated stages pass. Feel is unverified until the project owner drives it.

# HUMAN FEEDBACK ADDRESSED

| Feedback | What changed | Result |
|---|---|---|
| "A sharp sustained turn at top speed should be able to topple the tuk — it can't." | Fixed two physics defects that were propping the tuk up: the tilted suspension force and a full-width collision box that scraped the asphalt at ~22–25° of roll. Then calibrated roll assist and roll damping. | Sustained full lock rolls the tuk at 50, 60 and 70 km/h after ~0.8 s on two wheels. It is driven by physics, not scripted. |
| "At speed the tuk is too hard to swerve and turn." | More steering angle at speed (11.5° → 16° at 70 km/h, smoother falloff) and more front grip. Removing the suspension defect also removed most of the understeer. | Lane changes at 50–70 km/h move ~4.0–4.1 m sideways (v0.01: ~3.0 m). Peak lateral grip ~0.95 g (v0.01: ~0.72 g). |
| High agility + high consequence | Strong roll assist only in town; it fades out by 50 km/h. Roll damping separates brief swerves (recoverable) from sustained overcommitment (rollover). | Progression: stable → strong roll → inside wheel light → two wheels → recoverable if released or countersteered → rollover if held. |
| Very close passes sometimes scored nothing | The minimum-clearance exclusion is removed; collision detection decides. | An 8 cm non-contact pass now scores. |
| TIGHT GAP too rare | Window, threat clearance and threat speed were retuned. | A looser 1.2 m-each-side squeeze now registers. Normal 1.6 m lane spacing does not. |

# PHYSICS CHANGES

1. **Suspension force direction (defect fix).** The spring force is now applied along the ground contact normal instead of the body's up axis. At large roll the old direction added an outward push of about load × sin(roll), roughly 1.5 kN at 22°. That cancelled cornering force and caused the "washes wide" understeer.
2. **Collision shape (defect fix).** The 1.3 × 1.43 × 2.6 m box is replaced by a convex hull that tapers to a 0.72 m nose, matching the visual tuk. The old box's front corner touched the ground at ~22–25° of roll and propped the tuk up. Ground contacts aren't reported as collisions, so this was invisible. A centre-of-mass sweep from 0.61 to 0.70 m didn't move the roll plateau (24–26°), which is how this was found.
3. **Steering curve.** Wider at every speed, with a gentler ease-out (exponent 1.55 → 1.25) so the angle stays useful at speed while staying smooth.
4. **Front grip and cornering stiffness** raised, so steering input turns into direction change and load transfer instead of front-tyre slide.
5. **Roll assist profile.** Stronger in town (14 000 up to 25 km/h) so 20–40 km/h driving is trustworthy, fading to almost nothing (150) by 50 km/h. Cutoff 32° → 30°. **Roll damping 900 → 2500** is the key lever: it damps the fast roll overshoot of a swerve without changing the steady-state tipping point, so brief swerves recover while sustained locks roll.
6. **Roll-state signal.** `TukController.roll_state_changed(STABLE / INSIDE_WHEEL_LIGHT / TWO_WHEEL / ROLLOVER)` plus `inside_wheel_load_ratio`. Telemetry only.
7. **Camera.** Inherits 15% of chassis roll (max 5°) so two-wheel moments read on screen, and holds its heading while the tuk is tipped or tumbling. Vehicle physics is unchanged by the camera.
8. **Units.** Collision thresholds and scoring speeds are now configured in km/h. Speeds shown in the debug HUD, test output and docs are km/h.

# BEFORE VS AFTER

| Parameter | v0.01 | v0.01a | Reason |
|---|---|---|---|
| Suspension force direction | body up | ground normal | Defect: tilted force caused high-speed understeer |
| Collision shape | 1.3 m full-width box | tapered convex hull (0.72 m nose) | Defect: box corner propped the tuk up at ~24° roll |
| Centre of mass height | 0.57 m | 0.61 m | Higher load transfer, so rollover is possible at speed |
| `front_grip_multiplier` | 0.92 | 1.03 | The front tyre saturated first and the tuk washed wide |
| `cornering_stiffness` | 4200 | 5200 | Quicker lateral response to steering |
| `max_steer_angle_deg` (≤ 15 km/h) | 34.0° | 35.5° | Nimbler in dense traffic |
| `high_speed_steer_angle_deg` (70 km/h) | 11.5° | 16.0° | High-speed steering must stay useful |
| `steer_falloff_exponent` | 1.55 | 1.25 | Less aggressive falloff with speed |
| `roll_assist_low_speed` | 5500 | 14 000 | Town driving stable and forgiving |
| `roll_assist_high_speed` | 500 | 150 | Little help at speed, so consequences are real |
| Roll-assist fade | 20 → 65 km/h | 25 → 50 km/h | Help ends before high-speed manoeuvres |
| `roll_assist_cutoff_deg` | 32° | 30° | Lets go a little earlier |
| `roll_assist_damping` | 900 | 2500 | Brief swerve recoverable, sustained lock rolls |
| Collision thresholds | 1.5 / 6 m/s | 5.4 / 21.6 km/h | Same values, km/h standard |
| Camera roll inheritance | 0 | 15% (max 5°) | Communicate instability without nausea |
| Peak lateral grip at speed | ~0.72 g | ~0.95 g | Measured |
| Lane change ±0.6 at 60 km/h, sideways travel | 3.00 m | 4.05 m | Measured |
| Sustained full lock at 68 km/h | stays on two wheels at 22°, never rolls | rolls after ~0.8 s on two wheels | Measured |

# NEW STEERING CURVE

| Speed (km/h) | ≤ 15 | 20 | 25 | 30 | 40 | 50 | 60 | 70 |
|---|---|---|---|---|---|---|---|---|
| v0.01 max wheel angle | 34.0° | 30.9° | 28.0° | 25.2° | 20.3° | 16.2° | 13.1° | 11.5° |
| **v0.01a max wheel angle** | **35.5°** | 33.3° | 31.2° | **29.1°** | 25.1° | **21.5°** | **18.3°** | **16.0°** |
| Brief target | 35–36° | | | 28–30° | | 20–22° | 18–20° | 15–17° |

Blend: `t = clamp((speed − 15) / 55)`, `t' = 1 − (1 − t)^1.25`. Steering input slews at 3.2/s and returns or counters at 4.5/s. The curve is monotonic, with no step larger than 2° per km/h (unit tested).

# ROLLOVER TEST RESULTS

Flat asphalt, throttle held at the entry speed. "Sustained" = full lock held for 5 s. "Lock-then-release" = full lock until the two-wheel state (or 2.5 s), then the steering is released.

| Speed | Sustained full lock: max roll / wheel lift / result | Lock-then-release: max roll / two-wheel time / result |
|---|---|---|
| **40 km/h** | 12.9° / inside rear lifts (1.85 s two-wheel) / **no rollover**: scrubs down to 15 km/h, stays upright | 8.6° / 0.30 s / settles on three wheels |
| **50 km/h** | 85° / two wheels for 0.88 s / **rolls over** | 12.3° / 0.52 s / settles on three wheels |
| **60 km/h** | 85° / two wheels for 0.78 s / **rolls over** | 12.9° / 0.60 s / settles on three wheels |
| **70 km/h** (68 entry) | 85° / two wheels for 0.78 s / **rolls over** | 13.3° / 0.63 s / settles on three wheels |

**Recovery behaviour.** At every speed, releasing the steering as soon as the tuk goes onto two wheels lets it drop back onto three without help. Scenario E (66 km/h): lock until two-wheel, then countersteer 0.4 for 0.6 s. It peaked at 13.2° of roll, spent 0.47 s on two wheels and settled. Recovery comes from the physics: the lateral load falls, the inside wheel comes down, and roll damping removes the bounce. There is no scripted correction.

v0.01 for comparison: sustained full lock never rolled at any speed. It sat on two wheels at 12–22° for the whole 5 s.

# SWERVE TEST RESULTS

Swerve scenarios with acceptance checks:

| Test | Input | Max roll | Peak lateral g | Sideways travel | Two-wheel | Result |
|---|---|---|---|---|---|---|
| A urban swerve, 50 km/h | full L 0.45 s → full R 0.45 s | 14.9° | 0.93 | 2.97 m | 0.57 s | recovers |
| B emergency swerve, 60 km/h | full L 0.55 s → full R 0.55 s | 20.1° | 0.94 | 4.10 m | 0.77 s | recovers |
| C brief swerve, 68 km/h | full 0.5 s → −0.6 0.5 s | 19.2° | 0.98 | 3.73 m | 0.72 s | recovers |
| D sustained, 68 km/h | full lock held | 85° | 0.95 | — | 0.78 s | **rolls over** |

Representative lane change / obstacle avoidance, steering ±0.6 for 0.6 s each:

| Speed | Steering input | Max roll | Wheel lift | Sideways travel | Recovery | Understeer dominant? |
|---|---|---|---|---|---|---|
| 50 km/h | ±0.6 | 16.3° | two wheels 0.63 s | 3.92 m (v0.01: 2.99 m) | settles on three wheels | No: full lane plus margin |
| 60 km/h | ±0.6 | 17.9° | two wheels 0.67 s | 4.05 m (v0.01: 3.00 m) | settles on three wheels | No |
| 70 km/h (68 entry) | ±0.6 | 18.3° | two wheels 0.70 s | 4.11 m (v0.01: 2.98 m) | settles on three wheels | No |

Town stability checks (must stay trustworthy):

| Test | Max roll | Two-wheel | Result |
|---|---|---|---|
| Lane change ±0.6, 25 km/h | 5.0° | none | stable |
| Lane change ±0.6, 35 km/h | 6.9° | 0.08 s | stable |
| Half lock held 5 s, 30 km/h | 6.5° | none (inside wheel light) | stable |

# NEAR-MISS CHANGES

- **Minimum clearance removed.** It used to be 0.15 m. Any pass with no actual contact can score; contact detection decides. *Verified:* an 8 cm pass at 50 km/h scores CLOSE CALL with no collision.
- **Close-call max clearance:** 0.85 → 0.95 m.
- **Relative-speed threshold:** 21 km/h (was 21.6 km/h, i.e. 6 m/s). *Verified:* a 0.3 m pass at 18 km/h is rejected.
- **Candidate tracking** starts at 15.75 km/h relative (75% of the threshold). Alongside-farming expiry still applies below 12.6 km/h relative.

# TIGHT-GAP CHANGES

- **Window:** 0.7 → 0.9 s.
- **Threat clearance:** 1.2 → 1.35 m.
- **Threat relative speed:** 14.4 → 16 km/h. This is within the brief's 14–18 km/h range and keeps slow creeping out.

*Verified:*
- Squeezing between cars at 1.2 m and 1.25 m, with crossings about 0.6 s apart, gives TIGHT GAP (it would have been missed in v0.01).
- The original 0.5 m squeeze still gives CLOSE CALL then TIGHT GAP ×2.
- Normal 1.6 m-each-side lane spacing gives nothing.

The autopilot soak still produced 0 natural tight gaps; it doesn't aim for gaps. Natural frequency needs the human playtest.

# AUTOMATED TEST RESULTS

`tools/run_tests.sh`: **ALL TEST STAGES PASSED**

| Stage | Result |
|---|---|
| Unit tests | PASS: 40 tests, 238 assertions. The steering-curve test now asserts the v0.01a targets. |
| Vehicle handling (v0.01 scenarios, all kept) | PASS: 0–40 km/h 5.75 s, top 68.0 km/h, 50→0 km/h in 13.3 m, 2.9 m turning radius, kerb/slalom recover, reset works |
| **Vehicle dynamics (new)** | PASS: steering curve, A urban swerve 50, B emergency swerve 60, C brief swerve 68, D sustained rollover 68, E two-wheel recovery, town stability ×3, rollover at 60 and 70, no rollover at 40, lane changes |
| Scoring scenarios | PASS 9/9, including the extremely close pass, the slow close pass, the looser tight gap and the lane-spacing negative |
| Input smoke (real scene) | PASS: W/A/D/S, reverse, R, H, F1/F2/F3, Esc |
| Traffic soak, driving, 6 min | PASS: 0 pool leaks, 0 node growth, 0 visible spawns, 0 teleports, 0 traffic overlaps, active 11–14, max signal wait 21 s, 6 close calls, 4 collisions, **0 rollovers by the autopilot** (normal driving doesn't tip) |
| Junction stress, 6 min | PASS: 105 grants (60/45), max wait 28 s, max gap between grants 10 s, no deadlock |

Regressions checked: traffic pooling, node growth, junction deadlock, visible spawns, the save system (unit tests), localisation (unit tests), platform abstraction (unchanged), input handling (smoke test). No existing test was weakened. The one v0.01 handling scenario whose behaviour changed (half lock held at 60 km/h now rolls over) only asserts visible roll, which still passes. That change is intended.

# PERFORMANCE REGRESSION CHECK

Windowed `--perf` run on the M2: 60 FPS vsync-locked (p5 59.8). Gameplay CPU (scripts + Jolt) is **1.34 ms mean / 4.0 ms max** per frame (v0.01: 2.6 / 8.2 ms on a different run), with 117–150 draw calls. The changes add one convex hull (instead of a box) and a few multiplications per tick, so there's no measurable cost. Traffic is unchanged and still lightweight. No Android measurement yet.

# REMAINING ISSUES

1. **The two-wheel window before a sustained turn becomes a rollover is about 0.8 s.** That's a strong feel lever (`roll_assist_damping`), and it may be too short or too long for humans.
2. **Rollover from sustained full lock begins at about 50 km/h.** At 40 km/h the tuk only scrubs speed. Whether 50 km/h is the right threshold is a playtest judgement.
3. **Holding half lock at 60 km/h for 4 s also rolls the tuk.** That's realistic for a 2.2 g demand, but it could surprise players who hold a long curve too tight.
4. **The near-miss footprint is still the 1.3 × 2.6 m bounding box,** while physics uses the tapered hull. Passes right at the nose can be scored about 0.3 m more conservatively than the true shape.
5. **The test autopilot never threads tight gaps,** so natural tight-gap frequency is unmeasured.
6. **Roll-state telemetry has no player-facing feedback yet** (no audio or warning), by design.
7. **Carried over from v0.01:** no lane changes for traffic, no Sinhala/Tamil font, no touch controls, no audio, no Android measurement.
8. **`project.godot` has an uncommitted editor re-save** that drops three lines equal to engine defaults (orientation landscape, fallback locale `en`, 60 physics ticks). No behaviour changes. It was left uncommitted for the owner to decide.

# HUMAN PLAYTEST QUESTIONS

Please drive the build for 10 minutes or more (weave through traffic, try hard swerves at 50, 60 and 70 km/h, hold a turn at top speed, and try to save a two-wheel moment). Then answer in your own words. Experiences, not numbers:

1. Does the tuk now change direction rapidly enough?
2. Does it still feel controllable at 50–60 km/h?
3. Does high-speed steering feel dangerous rather than sluggish?
4. Does the rollover progression (lean → wheel lifts → two wheels → over) feel believable?
5. Can you recover from two-wheel moments?
6. Do close calls trigger when you *expect* them to?
7. Does TIGHT GAP happen often enough to be satisfying but rarely enough to feel special?

Tip: F1 shows speed (km/h), steering, roll angle, roll state, TWO-WHEEL YES/NO and the inside wheel's load while you drive.
