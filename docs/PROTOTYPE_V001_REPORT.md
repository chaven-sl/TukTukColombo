# Prototype v0.01 Report — Architecture v0.2 + First Playable Driving Slice

Date: 2026-10-21 · Engine: Godot 4.7.2 stable · GDScript · Mobile renderer · Jolt · tested on Apple M2 (macOS)

## BUILD STATUS

**PASS — with human playtest outstanding.**

The full loop runs: launch → drive immediately → traffic → close calls → tight gaps → combo → collision resets combo → keep driving, indefinitely. Every automated stage passes (`tools/run_tests.sh`): 40 unit tests (237 assertions), 13 vehicle handling scenarios, 6 scoring scenarios, an input smoke test through the real InputMap, and two 6-minute traffic soaks. **Not done:** no human has played it yet (feel is unverified), and it has not run on an Android device.

## FILES CREATED

```
project.godot (configured)        CLAUDE.md (rewritten)        .gitignore (extended)
autoload/      event_bus.gd  game_state.gd  save_manager.gd  platform_services.gd
data/          vehicles/vehicle_tuning.gd  camera/chase_camera_config.gd
               traffic/{traffic_vehicle_class,traffic_config,traffic_budget_config}.gd
               scoring/scoring_config.gd  passengers/passenger_profile.gd
resources/     vehicles/{tuk_player_tuning,chase_camera}.tres
               traffic/{car,bus,motorcycle,tuk,traffic_config,traffic_budget}.tres
               scoring/scoring_config.tres  passengers/{rushed,careful,thrill_seeker}.tres
locale/        en.po  si.po  ta.po
scenes/        bootstrap/bootstrap.{tscn,gd}  prototype/prototype_main.{tscn,gd}
               player/player_tuk.tscn  road/test_track.tscn
scripts/       player/{tuk_controller,player_input_source,vehicle_input_state,collision_event}.gd
               camera/chase_camera.gd
               road/{lane,road_segment,road_chain,road_network,intersection_controller,road_materials,scenery_spawner}.gd
               traffic/{traffic_agent,traffic_agent_factory,traffic_pool,traffic_manager}.gd
               performance/adaptive_traffic_budget.gd
               scoring/{near_miss_detector,combo_manager,scoring_system,skill_event}.gd
               ui/{prototype_hud,pause_controller}.gd  debug/debug_overlay.gd
               utilities/{save_store,oriented_rect,sim_clock,math_util}.gd
tests/         run_tests.gd  test_case.gd  unit/test_*.gd (7 suites)
               scenarios/{vehicle_handling,scoring_scenarios,input_smoke,traffic_soak}_test.{gd,tscn}
               support/autopilot_driver.gd
tools/         run_tests.sh
docs/          architecture  player_vehicle  traffic_system  scoring_system  performance_budget
               localisation  testing  roadmap  PROTOTYPE_V001_REPORT (this file)
```

## ARCHITECTURE

There is no GameManager. `prototype_main.gd` is the composition root and wires the systems explicitly:
- `RoadNetwork` builds the lane graph.
- `TukController` is the only rigid body.
- `TrafficManager` owns the pool, spawning, budget and the single agent update loop.
- `NearMissDetector` sends events to `ScoringSystem`/`ComboManager`, which feed the HUD.

There are 4 autoloads: EventBus (cross-system gameplay events only), SaveManager, PlatformServices (no-op) and GameState. Tunables are Resources: schemas in `data/`, instances in `resources/`. Pure rules live in RefCounted classes so they can be unit tested. Details are in `docs/architecture.md`.

## VEHICLE CONTROLLER

The vehicle is an original raycast three-wheel `RigidBody3D`. `VehicleBody3D` is not used.
- **Wheels:** one steered front wheel and two driven rear wheels. Each has a downward ray with a spring-damper and a bump stop.
- **Tyres:** a slip-velocity tyre model, scaled by load, with a per-wheel friction circle.
- **Engine:** a traction-limited, then power-limited, drive with a soft 70 km/h governor, plus aero drag.
- **Body response:** roll, squat, dive and kerb jolts come from forces at the contact points, below a CoM 0.57 m up and 0.25 m behind the wheelbase centre.
- **Roll assist:** a speed-faded roll assist (strong in town, weak above 65 km/h) lets go past 32°, so a real tip-over is possible.
- **Steering:** speed-sensitive and smoothly blended, with separate response and return rates.
- **Collisions:** classified by the player's velocity change (MINOR ≥ 1.5 m/s, MAJOR ≥ 6 m/s). A major collision also bleeds speed and gives a stronger camera impulse.
- **Recovery:** a tuk tipped over for 2.5 s is put back on the nearest lane automatically, and **R** resets immediately.
- **Input:** goes through `VehicleInputState`, so touch controls or an autopilot can replace the keyboard without touching the vehicle.

Full measurements are in `docs/player_vehicle.md`.

## CURRENT TUNING VALUES (PROTOTYPE BASELINE)

| Group | Parameter | Value |
|---|---|---|
| Body | mass | 430 kg |
| | centre of mass (local) | (0, 0.57, 0.25) m |
| | inertia pitch/yaw/roll | 330 / 300 / 150 kg·m² |
| Geometry | wheelbase / rear track / wheel radius | 2.0 / 1.15 / 0.21 m |
| Engine | top speed (governed) | 70 km/h (measured 68.2) |
| | drive force (traction) / power | 1050 N / 7.8 kW |
| | 0–40 km/h (measured) | 5.73 s |
| | reverse force / max | 650 N / 14 km/h |
| Brakes | total force / front bias | 3800 N / 40 % |
| | 50→0 km/h (measured) | 13.8 m, 2.37 s |
| | handbrake / parking brake | 1400 N / 900 N |
| Steering | max angle ≤15 km/h | 34° |
| | 30 / 50 / 70 km/h | 25.2° / 16.2° / 11.5° |
| | blend | ease-out exponent 1.55 between 15 and 70 km/h |
| | response / return | 3.2 /s, 4.5 /s |
| Suspension | travel | 0.22 m |
| | spring front / rear | 17 000 / 18 500 N/m |
| | damping front / rear | 2300 / 2600 N·s/m |
| | bump stop | 60 000 N/m |
| Tyres | grip μ / front multiplier | 0.95 / 0.92 |
| | cornering stiffness | 4200 N per m/s |
| | rolling resistance / drag | 0.015 × load / 0.75 N·(m/s)⁻² |
| Stability | roll assist low → high speed | 5500 → 500 N·m/rad (20→65 km/h) |
| | roll assist cutoff / damping | 32° / 900 |
| | yaw damping / angular damp | 150 / 0.3 |
| Camera | FOV base → high speed (vertical) | 67° → 76° (at 70 km/h) |
| | distance / height | 6.3 m (+0.5 at speed) / 2.8 m |
| | look target | 18 m ahead, 2.4 m high |
| | yaw follow (lateral lag) | 4.5 |
| | accel pull-back / brake push-in | 0.12 m per m/s² (max 0.45) / 0.08 (max 0.5) |
| | collision impulse | spring 120, damping 16, minor 0.6, major 1.6 |

## TRAFFIC SYSTEM

- **Agents:** 24 pooled kinematic agents (12 car, 3 bus, 5 motorcycle, 4 tuk). They follow lanes with Intelligent Driver Model car-following and slow for curves using lane curvature.
- **Avoidance:** agents brake for the player and for stop lines.
- **Speeds:** each vehicle gets its own random target speed within its class range (measured spread σ ≈ 7.5 km/h), so traffic doesn't move as a synchronised convoy.
- **Traffic bubble:** vehicles spawn 75–170 m ahead of the player's direction of travel, out of view (fog beyond 110 m, or tunnel portals). Vehicles more than 45 m behind, more than 190 m away, stuck, or over budget are recycled, but only when unseen.
- **Population:** 14 active by design, at least 11 after the initial fill in a 6-minute soak.
- **Not implemented:** lane changes.

Details are in `docs/traffic_system.md`.

## INTERSECTION SYSTEM

`IntersectionController` generates 14 connector lanes from the lanes touching its edges, using left-hand-traffic lane rules. It computes conflict sets from path proximity and shared exits.
- **Signals:** a two-axis cycle (14 s / 9 s green, 3 s amber, 1.5 s all-red).
- **Permission:** an agent may enter only on green (or amber if it can't stop), with no conflicting reservation or occupancy, room on its exit lane, and, for right turns, no oncoming priority traffic within 32 m.
- **Agents:** never decide right-of-way themselves.
- **Junction stress test (6 min):** 104 grants, longest wait 22 s, longest gap between grants 15 s, no deadlock.

## ADAPTIVE PERFORMANCE SYSTEM

`AdaptiveTrafficBudget` sets the agent count to `min(density target 14, performance ceiling)`.
- **FPS sampling:** frame rate is averaged over 0.5 s windows.
- **Stepping down:** below 27 FPS for 3 s steps the ceiling down by 2.
- **Recovery:** above 50 FPS for 10 s steps it up by 1.
- **Stability:** a dead band between the thresholds, plus a 4 s cooldown between changes.
- **Limits:** the ceiling stays between 8 and 20 and starts at 14.

Unit tests cover dips being ignored, gradual stepping, cooldown, slower recovery, no thrashing under oscillating FPS, and the caps. The F1 overlay shows FPS, frame time, target, ceiling, active count and pool size.

## NEAR-MISS SYSTEM

Detection runs as a candidate state machine using exact edge-to-edge distances between oriented rectangles: candidate → track the minimum clearance and side → the agent crosses the player's reference plane → confirm no contact → classify.
- **CLOSE_CALL:** clearance of 0.15–0.85 m and relative speed ≥ 6 m/s.
- **TIGHT_GAP:** threat passes (≤ 1.2 m, ≥ 4 m/s) on opposite sides within 0.7 s.
- **Anti-spam:** each agent has a 2.5 s cooldown, any contact rejects the pass, and cruising alongside at low relative speed expires the candidate.

Testing found a real bug: legitimate overtakes expired before they finished. It is fixed and documented in `docs/scoring_system.md`.

## COMBO SYSTEM

`ComboManager` (pure rules):
- Each skill event adds to the chain, refreshes a 3.0 s timeout and sets the multiplier to `min(chain, 5)`.
- Points are base × multiplier: CLOSE CALL 25, TIGHT GAP 50.
- Timeout or any collision resets the combo.

`ScoringSystem` routes events between EventBus and GameState. The HUD shows popups like "CLOSE CALL +25" and "TIGHT GAP ×2 +100", a combo label that pulses with a timeout bar, and "COMBO LOST" on collision.

## SAVE SYSTEM

`SaveStore` handles `user://save_v1.json` with `schema_version`, `settings` and `prototype_stats` (best_combo, highest_score, total_close_calls, total_tight_gaps).
- **Write:** to a `.tmp` file, then verify it, then rotate the previous valid primary to `.bak`, then promote the temp file.
- **Load:** primary → temp → backup → defaults. A corrupt primary is quarantined as `.corrupt` and is never rotated over a good backup.
- **Migrations:** step-wise, with a v0→v1 template. Future schemas are refused.
- **Types:** normalised, so JSON floats become ints again.
- **SaveManager:** the autoload wrapper. GameState autosaves when stats change, at most every 20 s, and on pause or quit.

10 unit tests cover this.

## LOCALISATION FOUNDATION

- **Translation:** Godot's translation system with `locale/en.po` (complete), `si.po` and `ta.po` (two test strings each, empty strings fall back to English).
- **Locale setting:** stored in the save.
- **UI text:** all player-facing UI uses keys.
- **Fonts:** no Sinhala/Tamil font is shipped yet, because no vetted font is available. `docs/localisation.md` covers the workflow, the OFL font requirement and the complex-script testing requirement.

## PLATFORM SERVICES

The `PlatformServices` autoload is a no-op facade with `track_event`, `show_rewarded_ad`, `show_interstitial`, `purchase`, `restore_purchases`, `is_online`, `cloud_save` and `cloud_load`, plus result signals emitted deferred with safe defaults. No SDK is integrated.

## PASSENGER PROFILE STUB

The `PassengerProfile` Resource has id, display_name_key, time/safety/comfort weights, risk_tolerance, collision_penalty_multiplier, speed preference/tolerance and close_call_preference, plus `validate()` and `normalised_weights()`. Three sample profiles exist: RUSHED, CAREFUL and THRILL_SEEKER. Gameplay doesn't read them. Unit tests check they load, validate and differ meaningfully.

## AUTOMATED TEST RESULTS

Run `tools/run_tests.sh`. The whole suite takes about 30 s headless on the M2.

| Stage | Result |
|---|---|
| Unit (7 suites) | PASS — 40 tests, 237 assertions |
| Vehicle handling (13 scenarios) | PASS — all checks |
| Scoring scenarios (6) | PASS — close call, wide pass rejected, slow pass rejected, tight gap, combo ×1→×3, collision → no award + reset |
| Input smoke (real scene) | PASS — W/A/D/S, reverse, R, H, F1/F2/F3, Esc pause/resume |
| Traffic soak, driving (360 s) | PASS — 0 pool leaks, 0 node growth, active ≤14 (min 11), 0 visible spawns, 0 teleports, 0 traffic overlaps, junction both axes, max wait 15 s, speed σ 7.8 km/h, 9 natural close calls, 5 collisions |
| Traffic soak, junction stress (360 s) | PASS — 104 grants (57/47), max wait 22 s, max grant gap 15 s |

Bugs the tests caught and that are now fixed:
- The default engine damping capped top speed at 35 km/h.
- Rolling resistance was scaled per m/s.
- Telemetry was stale after a teleport.
- `sync_to_physics` caused one-frame teleports of pooled agents.
- Population collapsed because spawns were placed in a ring around the player.
- Near-miss candidates expired during legitimate overtakes.
- The steering blend had a 2°-per-km/h kink at 15 km/h.
- Lane reference cycles leaked at exit.

## MANUAL TEST RESULTS

- **Windowed runs with the autopilot on the real game:** I reviewed four screenshots. The grey-box world, left-hand lane markings, black/white kerbs, fog, readable traffic (cars, bus, motorcycle with rider, tuks), the HUD score, speed and "COMBO ×1" all render correctly. Camera framing was adjusted after review: the tuk now sits at about 59–86% of screen height, with traffic ahead readable above its roof.
- **Keyboard controls:** verified through the InputMap action path in the input smoke test, but not by a human at a keyboard.
- **Not done:** no human playtest of feel, fairness or fun. That is the next step.

## CURRENT PERFORMANCE OBSERVATIONS

- **Desktop (Apple M2, 1280×720):** 60 FPS, vsync-locked (p5 ≈ 58–59), 148–154 draw calls.
- **Gameplay CPU (scripts + Jolt):** about 2.6 ms mean, 8.2 ms max per frame.
- **Headless:** 2 simulated minutes run in about 5 s.
- **Android:** not measured. A rough extrapolation for a mid-range device is 8–13 ms of gameplay CPU per frame. That fits a 30 FPS floor comfortably and needs verifying for 60 FPS.

Details are in `docs/performance_budget.md`.

## KNOWN ISSUES

1. **Steering can't tip the tuk on flat road.** The front tyre saturates first, capping lateral g at about 0.45 at speed, so the tuk balances on two wheels at about 22°. Tip-overs need an extra disturbance such as a kerb or collision. This may feel "too safe" or odd.
2. **Strong understeer at 60+ km/h.** Even full lock gives a 58–63 m radius once the inner wheel lifts, so steering may feel unresponsive at top speed.
3. **The tuk fills about 27% of screen height** (the 59–86% band), slightly more than the 20–25% target. This is a consequence of the vertical 67° FOV at the specified distance and height.
4. **Traffic has no lane changes.** It only treats the player as an obstacle in a straight line ahead, so it can misjudge in curves. Kinematic traffic can shove the player.
5. **Traffic churn is high:** about 340 spawns in 6 minutes, because of the ahead-only bubble. If the player drives against the loop direction, traffic must refill ahead.
6. **The tight gap almost never happens naturally with the autopilot.** It is proven only by the deterministic scenario. Real players may find the 0.7 s window and 1.2 m threat clearance too strict or too loose.
7. **Very close passes (under 0.15 m) without contact score nothing,** per the brief's lower bound. This may feel unfair.
8. **A tuk on two wheels shows a strong 20°+ roll,** with no audio or visual warning beyond the roll itself.
9. **Sinhala/Tamil render as boxes** because there is no font yet. The debug overlay text is English only.
10. **Road geometry is generated at runtime,** so `test_track.tscn` looks empty in the editor. Scenes and resources were hand-written without UIDs; Godot adds them when you save in the editor.
11. **No audio.** The horn only emits an event.
12. **No touch controls yet,** although the architecture is ready for them.
13. **Not tested on Android.**
14. **Sink-lane agents wait at a tunnel end while visible.** If the player stares into a tunnel, a short queue can build inside.

## TUNING VARIABLES FOR HUMAN TEST

Order of importance for the first playtest:

1. **High-speed steering authority:** `front_grip_multiplier` (0.92), `cornering_stiffness` (4200), `high_speed_steer_angle_deg` (11.5) and `steer_falloff_exponent` (1.55). This decides whether weaving at 50–65 km/h feels agile or sluggish.
2. **Danger level:** `center_of_mass.y` (0.57), `roll_assist_high_speed` (500), `roll_assist_cutoff_deg` (32) and `tyre_force_height` (0). This decides how scary and tippy the tuk feels, and whether tipping should be possible from steering alone.
3. **Near-miss fairness:** `max_valid_clearance` (0.85 m), `min_relative_speed` (6 m/s), `tight_gap_window` (0.7 s), `tight_gap_threat_clearance` (1.2 m) and `min_valid_clearance` (0.15 m). Do close calls fire when they *feel* close?
4. **Traffic density and pace:** `gameplay_density_target` (14), the class speed ranges, `spawn_min/max_distance` (75/170 m) and `behind_despawn_distance` (45 m). Are there enough gaps to thread?
5. **Camera comfort:** `distance` (6.3), `height` (2.8), `look_ahead` (18) / `look_height` (2.4), `base_fov`/`high_speed_fov` (67/76) and `yaw_follow` (4.5).

Also worth watching: `combo_timeout` (3.0 s), `steering_response`/`steering_return_speed` (3.2/4.5), and `engine_power_w` (7800).

Edit the `.tres` files in `resources/` from the Godot inspector. F1 shows the live values while driving.

## NEXT RECOMMENDED STEP

Run a **human playtest session of v0.01**: 3–5 people, 10 minutes each, keyboard. Record the debug overlay and tune the five variable groups above. Alongside that, get an **Android export performance baseline on one mid-range device**: FPS, frame time, draw calls, gameplay CPU, and whether the adaptive budget engages.

Do not add features until both are done. Touch controls, audio and passengers belong to v0.02 and later (see `docs/roadmap.md`).
