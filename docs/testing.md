# Testing

No test plugin. Everything runs with the stock Godot binary, headless where possible.

```bash
tools/run_tests.sh      # all stages, ~30 s, non-zero exit on failure
```

Set `GODOT=/path/to/Godot` if the binary is not at `/Applications/Godot.app/Contents/MacOS/Godot`. After adding a `class_name` script run `godot --headless --path . --import` (the script does this).

## Stages

| Stage | Command | Covers |
|---|---|---|
| Unit | `--headless --script res://tests/run_tests.gd` | combo progression/timeout/reset; passenger profile loading/validation; save round-trip, backup rotation, corrupt-primary recovery, all-corrupt reset, interrupted-save temp recovery, v0→v1 migration, future-schema refusal, type normalisation; adaptive budget hysteresis (dips ignored, gradual steps, cooldown, slower recovery, no thrash, caps); steering curve targets and smoothness; drive/roll-assist curves; oriented-rect distance; lane sampling/advisory; InputMap actions; renderer/physics/orientation settings; translations + fallback; four traffic classes / pool 24 |
| Vehicle handling | `--headless --fixed-fps 60 res://tests/scenarios/vehicle_handling_test.tscn` | settle, 0–40/top speed, braking + nose dive, reverse, low-speed radius, turns at 30/60/65 km/h, high-speed flick, slalom recovery, kerb strike, reset from side |
| Vehicle dynamics (v0.01a) | `--headless --fixed-fps 60 res://tests/scenarios/vehicle_dynamics_test.tscn` | urban swerve 50 km/h, emergency swerve 60, brief top-speed swerve 68, sustained top-speed rollover, two-wheel recovery, town stability 25/30/35, rollover matrix 40/50/60/70, lane-change matrix 50/60/70 (all reported in km/h). `-- --screenshots` in a window adds chase-camera frames of two-wheel and rollover moments |
| Scoring | `--headless --fixed-fps 60 res://tests/scenarios/scoring_scenarios_test.tscn` | close call, extremely close non-contact pass, clearance/speed rejections, tight gap (tight and looser), lane-spacing negative, combo ×1→×3, collision → no award + reset |
| Human world + passengers (v0.02) | `… res://tests/scenarios/human_world_test.tscn` | sidewalk walking, crossing wait/proceed, reaction to the tuk, people never score CLOSE CALL/TIGHT GAP, pedestrian impact (event, combo reset, removal), full ride loop for all three passengers (offer, accept, boarding, telemetry, completion + fare, exit, pool return, offer respawn), drive-by pickup refusal, impact fails an active ride |
| Input smoke | `… res://tests/scenarios/input_smoke_test.tscn` | real prototype scene driven through InputMap actions: W/A/D/S, reverse, R, H, F1/F2/F3, Esc pause/resume |
| Mobile touch + lifecycle (v0.03A) | `… res://tests/scenarios/mobile_touch_test.tscn` (and `-- --force-touch-controls`) | desktop default = keyboard, touch HUD hidden; one input source at a time; injected multitouch steer+GO / steer+BRAKE moves the real tuk; quick reversal; horn/pause/accept taps; Android Back pause↔resume, never quits; focus loss pauses, cancels touches, no auto-resume, ride untouched; route-direction regression for every offer × destination |
| GPS + hire + incidents (v0.03A1) | `… res://tests/scenarios/gps_incident_test.tscn` | hire offered from a distance, exactly one selected, selected beacon/marker dominant, others muted; pickup route on the lane graph (0.00 m offset), direction-legal, starts at tuk/ends at passenger; off-route detection + rate-limited recalculation; STOP TO PICK UP; boarding clears, destination route appears automatically; completion and cancellation clear; world collision ignored; LIGHT/MODERATE/MAJOR tiers; other_agent_id resolution; driver exits → approaches → argues at talking distance → returns → pool; one altercation max; vehicle held then resumes; player drives away → no chase; no score; pool bounded |
| Traffic + incidents soak | `… traffic_soak_test.tscn -- --duration=240 --incidents` | a scripted collision every 7 s (LIGHT/MODERATE/MAJOR cycle) on top of the normal soak: ≤ 1 driver out, ≤ 1 vehicle held, no hold beyond the cap, no driver leak, no runaway incidents, plus every normal soak check |
| Traffic soak (drive) | `… traffic_soak_test.tscn -- --duration=360` | autopilot laps through traffic: pool/node leaks, bounded population, no visible spawns, no teleports, no traffic overlap, junction service, bounded signal waits, speed variety, natural close calls, collision rate |
| Traffic soak (junction) | `… -- --duration=360 --park-near-junction` | player parked beside the junction: throughput, no stalls/deadlock |

Results also go to `user://test_results/*.json` (macOS: `~/Library/Application Support/Godot/app_userdata/TukTuk Colombo/test_results/`).

Windowed runs (`godot --path . res://tests/scenarios/traffic_soak_test.tscn -- --duration=60 --screenshots [--perf]`) add FPS, CPU-time and draw-call figures and save screenshots.

## Latest results (2026-10-23, Apple M2, after v0.03A1)

All 13 stages pass — unit **90 tests / 916 assertions** (new: floating-origin steering incl. 10 s jitter test, RoutePlan geometry/turns/instructions, incident tiers, temperaments, severity-dominates rules, profile collision lines); GPS + incidents scenario PASS; incidents soak PASS. Windowed extras: `tests/scenarios/gps_incident_screens.tscn` (hire card, GPS, altercation screenshots). See `docs/PROTOTYPE_V003A1_REPORT.md`.

## After v0.03A (2026-10-22, Apple M2)

All 10 stages pass — unit **80 tests / 765 assertions** (new: touch mapper + multitouch state, layout on 5 aspect ratios × 4 safe areas, export preset, mobile settings, graphics profiles, mood); mobile touch both modes PASS; v0.01–v0.02 stages unchanged and passing. Windowed-only extras: `tests/scenarios/touch_layout_screens.tscn` with `--resolution WxH` saves forced-touch screenshots; `godot --path . -- --perf-test=20` runs the device perf test on desktop. See `docs/PROTOTYPE_V003A_REPORT.md`.

## After v0.02 (2026-10-21)

All 8 stages pass — see `docs/PROTOTYPE_V002_REPORT.md` (unit 61 tests / 545 assertions incl. same-drive passenger tests, pedestrian-danger fuzz, save v1→v2; human world PASS; both soaks now also check the human pool, transitions, crossing deadlocks and stranding).

## After v0.01a

All stages pass — see `docs/PROTOTYPE_V001A_REPORT.md` for the figures (unit 40 tests / 238 assertions; dynamics all checks; scoring 9/9; input smoke; soaks clean). The v0.01 figures below are kept for history.

## v0.01 results

- Unit: **40 tests, 237 assertions, 0 failures**.
- Vehicle handling: **all checks pass** (numbers in player_vehicle.md).
- Scoring scenarios: **6/6 pass**.
- Input smoke: **all controls pass**.
- Soak drive 360 s: all checks pass — 342 spawns, max 14 / min 11 active, 0 leaks / teleports / overlaps / visible spawns, 9 close calls, 0 tight gaps (autopilot), 4 minor + 1 major collisions, max signal wait 15 s.
- Soak junction 360 s: all checks pass — 104 grants (57/47), max wait 22 s, max gap between grants 15 s.

## What automated tests cannot tell you

Whether it is *fun*. Handling feel, camera comfort, popup readability, near-miss fairness and traffic "aliveness" need human playtests; see the report's playtest priorities.

## Manual test checklist

Launch → drive immediately → accelerate into traffic → weave → CLOSE CALL popup → thread two vehicles → TIGHT GAP → build combo → collide → COMBO LOST → keep driving several minutes. Also: R reset, Esc pause/resume, F1/F2/F3 debug, H horn (no visible effect yet), kerb hits, sharp corner at speed, narrow barrier section, junction during red.
