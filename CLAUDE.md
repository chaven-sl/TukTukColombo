# TukTuk Colombo — working instructions

Original stylised Sri Lankan tuk-tuk driving game. Current phase: **Prototype v0.03B1 — performance recovery + visual quality** on the Fort–Pettah Gateway slice (awaiting owner visual/playtest approval; `docs/PROTOTYPE_V003B1_REPORT.md`). The game boots into `scenes/districts/fort_pettah/fort_pettah_slice.tscn`; the greybox `prototype_main.tscn` stays for regression tests. v0.01a vehicle handling is the approved **MVP HANDLING BASELINE**: do not retune steering, CoM, grip, suspension, rollover, roll assist, engine or brakes unless a reproducible defect requires it — document and report first. Handling philosophy: **high agility + high consequence** — the tuk always turns when asked; overcommitting at speed is punished by roll, wheel lift and rollover, never by removing steering authority. Objective of v0.01: *make driving a three-wheeler through moving traffic genuinely enjoyable for five minutes.* Everything else is infrastructure.

## Repository identity

- Production repository: https://github.com/chaven-sl/TukTukColombo.git (`chaven-sl/TukTukColombo`), default branch `main`.
- Never modify, commit to, push to, or import production code from any other repository.
- Before any git push, confirm `git remote -v` shows `origin` as the URL above and `gh auth status` shows `chaven-sl` as the active account.
- Logical commits (`feat(vehicle): …`, `fix(traffic): …`, `test(prototype): …`). Never force-push or rewrite history. Never commit `.godot/`, build output or editor junk.

## Competitor research

- Competitor APK research is external research only. It lives outside this repository (`../research/`).
- Never commit APKs, decompiled code, extracted assets, or research notes from it into this repository. Use it only as reference; write all game code and assets from scratch.

## Fixed stack (do not change without explicit approval)

Godot **4.7.2 stable** · **GDScript** · **Mobile** renderer · **Jolt** physics · Android first (develop on macOS) · landscape · 3D stylised realism · low third-person chase camera. Never migrate to Unity/Unreal/C#/Forward+/Compatibility. No third-party plugins, vehicle packages, asset packs, input/joystick frameworks or SDKs.

Godot CLI on this machine: `/Applications/Godot.app/Contents/MacOS/Godot` (also in `~/Downloads`). Not on `PATH`.

## Commands

```bash
# Play (or open the project in the editor and press F5)
/Applications/Godot.app/Contents/MacOS/Godot --path .
# All automated checks (~1 min): import, unit, handling, dynamics, scoring, human world, input, 2× traffic+humans soak
tools/run_tests.sh
# Individual stages
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/scenarios/vehicle_handling_test.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/scenarios/vehicle_dynamics_test.tscn   # swerve/rollover/recovery
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/scenarios/scoring_scenarios_test.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/scenarios/human_world_test.tscn   # people + rides
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/scenarios/gps_incident_test.tscn   # hire UX, GPS, incidents
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/scenarios/hud_safe_area_test.tscn   # HUD in safe area, 5 ratios x 6 cutouts
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/scenarios/world_containment_test.tscn   # containment, damage, recovery, props
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/scenarios/pavement_safety_test.tscn   # pedestrian emergency evasion
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/scenarios/fort_pettah_test.tscn   # v0.03B art/presentation/audio checks
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/scenarios/traffic_soak_test.tscn -- --duration=360 [--park-near-junction | --incidents | --offroad | --fort-pettah]
# Fort–Pettah quality-gate screenshots (windowed) → user://test_results/screens/v003b_gate_*.png
/Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 1280x720 res://tests/scenarios/fort_pettah_screens.tscn -- --gates
# Regenerate the procedural first-pass audio (numpy) → assets/audio/sfx/
python3 tools/audiogen/generate_audio.py
# Android (debug only; see docs/android_setup.md)
tools/android_preflight.sh && tools/export_android_debug.sh   # → builds/android/tuktukcolombo-debug.apk (git-ignored)
tools/install_android_debug.sh                                # needs an adb device; never uninstalls
tools/android_perf_test.sh 300 [opts]                         # deterministic device perf test; opts = A/B switches, e.g. audio_off,shadows_off,scale=0.75 (keep the phone UNLOCKED)
# Touch on desktop: -- --force-touch-controls (or project setting tuktuk/dev/force_touch_controls)
# Simulated cutout / safe area (logical units): -- --simulate-safe-area=L,T,R,B
# Real window: FPS + screenshots to user://test_results/screens
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/scenarios/traffic_soak_test.tscn -- --duration=60 --screenshots [--perf]
```

Scripts that reference autoloads (EventBus, GameState…) cannot be loaded in `--script` mode; test them in scene-based scenarios. A script parse error makes headless Godot wait forever — `tools/run_tests.sh` wraps every stage in a timeout. Run `--import` after adding any new `class_name` script (refreshes the global class cache used by headless runs). "It compiles" is not a test result — run the scenario that exercises the change.

## Architecture principles

- **Composition over monoliths.** No GameManager. `scenes/prototype/prototype_main.gd` is the composition root: it wires systems explicitly; systems never look each other up by arbitrary scene path.
- **Data-driven.** Tunables live in Resources: class scripts in `data/`, instances (`.tres`) in `resources/`. Mark prototype values `PROTOTYPE BASELINE`.
- **Signals.** Local signals between neighbours; `EventBus` only for cross-system gameplay events (`skill_event`, `collision_event`, `score_awarded`, `combo_changed`, `performance_budget_changed`, `player_reset`, `horn_sounded`, pedestrian/ride events, and v0.03A1 incident hooks `traffic_incident_started/resolved`, `traffic_horn`, `driver_shout`).
- **Minimal autoloads:** `EventBus`, `SaveManager`, `PlatformServices`, `GameState` (in that order). Nothing else is global.
- **Detection ≠ scoring ≠ UI.** `NearMissDetector` emits events → `ScoringSystem`/`ComboManager` decide value → HUD presents.
- **People are never a reward.** Pedestrian incidents use their own signals (`pedestrian_danger`, `pedestrian_impact`); they must never reach score, combo, fare or passenger excitement. The near-miss detector only reads `TrafficAgent`s.
- **One human foundation.** Every person is a pooled `HumanAgent`; new kinds of people are new roles + behaviour objects, not new systems. People have no physics body.
- **One satisfaction model.** Passengers differ only through `PassengerProfile` data; never add per-passenger scoring code.
- **Pure logic is testable.** Rules live in RefCounted classes (`ComboManager`, `AdaptiveTrafficBudget`, `SaveStore`, `OrientedRect`, `VehicleTuning` helpers) with nodes as thin wrappers.
- **Platform isolation.** Gameplay never calls SDKs; it calls `PlatformServices` (no-op in v0.01).
- **Collisions are never a reward.** `TrafficIncidentManager` turns traffic collisions into social reactions (horn, shout, driver gets out and argues) — never score/combo/fare; no violence, no chase. One altercation at a time; drivers are pooled `HumanAgent`s (role `TRAFFIC_DRIVER`).
- **GPS reuses the lane graph.** `RoadNetwork.route_path()` → `RoutePlan` → `RouteGuidance`; never search routes every frame (accept / boarding / reset / rate-limited off-route only).
- **No invisible walls; consequences instead.** Road → pavement/forecourt (accessible, dangerous) → buildings/walls/poles (solid, can damage) → district ring → VOID failsafe. Static bodies carry a `WorldSurface` tag; TukController stays map-agnostic (it only reports `CollisionEvent.other_body`). Damage (`VehicleDamageState`) is applied in the input layer, never by retuning physics. All resets go through `WorldRecoveryManager.safe_reset_pose` (nearest legal lane, behind the crash, clear of traffic/people).
- **People get out of the way.** Projected-threat evasion (EVADE / DIVE) for every role, never into a traffic lane or through a structure; danger/impact rules unchanged and never a reward.
- **HUD lives in the safe area.** Every HUD layer builds under `HudSafeArea`; banners only via `NotificationPresenter` (priorities; CRITICAL suppresses score popups). Text wraps with max lines — never fixed widths that overflow.
- **One human input source.** Keyboard (`PlayerInputSource`) or touch (`TouchInputSource`), chosen once by `InputMode`; both only write `VehicleInputState`. Touch taps reuse existing paths (horn event, `RideManager.request_accept()`, `GameState.set_paused()`). Android Back pauses/resumes and never quits.
- **Android signing.** Debug keystore only (per-machine editor setting). Never create/commit a release keystore or store signing config without explicit approval. Package `com.chavensl.tuktukcolombo` is provisional.
- **Art follows physics (v0.03B).** Collision and visual geometry are separate: district art is merged visual chunks (`DistrictChunks`) + simple box proxies (`BuildingProxies`/`PropProxies`/`ForecourtProxies`); vehicles are physics root + `Visual/HeroArt` / `Body`; people are `HumanAgent` + `CharacterRig`. Art never adds colliders or changes mass/CoM. All art is procedural GDScript (no downloads, no Blender); rules in `docs/art_bible.md`, budgets in `docs/fort_pettah_art_budget.md`.
- **Audio is presentation (v0.03B).** `DistrictAudio` reads telemetry + EventBus hooks only; buses Vehicle/Traffic/Ambience/UI (`default_bus_layout.tres`); fixed voice pools, range limits, cooldowns; sounds are original procedural WAVs from `tools/audiogen/`. No music.
- **Mobile GPU budget (v0.03B1).** The reference Mali-G610 is pixel-bound: medium tier renders 3D at 0.67 + FSR. Spend art budget on geometry/silhouettes, not per-pixel effects. Measure with `PerfSections` + render GPU timings (`TIME_PROCESS` includes the vsync wait — never quote it as CPU work). Docs must quote the real `.tres` values (unit-tested).
- **Debuggable.** F1 overlay / F2 traffic / F3 vehicle; debug code lives in `scripts/debug/` and is removable.

## Directory rules

| Path | Contents |
|---|---|
| `autoload/` | the four global services only |
| `data/<domain>/` | Resource **class** scripts (schemas) |
| `resources/<domain>/` | Resource **instances** (`.tres`) |
| `scenes/<domain>/` | scenes; a scene's root script may sit beside it |
| `scripts/<domain>/` | runtime code: `player camera traffic road world humans rides navigation scoring performance ui input platform debug utilities art audio districts` |
| `locale/` | `en.po si.po ta.po` |
| `tests/unit/` | headless logic tests (`test_*.gd`, extend `tests/test_case.gd`) |
| `tests/scenarios/` | scene-based simulation tests (autopilot lives in `scripts/debug/` so the device perf test can use it) |
| `tools/` | test runner and Android scripts (excluded from exports) |
| `builds/android/` | local APK output — git-ignored, never committed |
| `docs/` | design/technical docs and reports |
| `assets/` | original assets only: `fonts/` (Noto, SIL OFL, licences beside them), `audio/sfx/` (procedural) |

## Performance requirements

Mid-range Android target; stable 30 FPS floor on supported low-end devices. Avoid in `_process`/`_physics_process`: allocations, `get_nodes_in_group`, tree searches, string building (debug excepted, throttled). Prefer cached references, pooling, squared distances, fixed-size packed arrays, data Resources. One RigidBody (the player); traffic is kinematic and pooled (24). Traffic casts no shadows; one DirectionalLight; no SSR/volumetrics/post. See `docs/performance_budget.md`.

## Unit standard

All speeds presented to people — docs, reports, test output, debug HUD, tuning tables, acceptance criteria, config descriptions — are **km/h**. Physics internals may use m/s; convert (×3.6) for anything human-readable, and document the km/h equivalent of any threshold stored in another unit. Prefer `_kmh` config fields.

## Coding conventions

- GDScript with static types everywhere; `:=` only when the type is inferable (never on Variant/Dictionary reads). Use `minf/maxf/clampf/absf`, not the Variant versions.
- `class_name` for reusable types; autoloads have none.
- Tabs; `##` doc comments on classes and non-obvious exports; comments explain *why*.
- Units SI (m, s, kg, N); names ending `_kmh`/`_deg` say otherwise. Godot forward is `-Z`.
- Sri Lanka drives on the **left**: forward lanes sit left of the centre line; right turns cross traffic and give way.
- Player-facing text only via translation keys (`tr("UI_…")`); add keys to all three `.po` files.
- Gameplay timestamps use `SimClock.now()` (physics-frame based) so headless fixed-step tests match real play.

## Prohibited shortcuts

- No ads, analytics, Firebase/AdMob/IAP/Play Games, accounts, cloud save, leaderboards — `PlatformServices` stubs only.
- No economy/spending/garage/upgrades/progression/new passenger types until the roadmap phase says so. The fare is a prototype readout only.
- No `VehicleBody3D` swap, generic 4-wheel controller, or "make it untippable" hacks for the player tuk.
- No `Area3D`-enter = score near-miss logic; no UI inside detection code.
- No instantiate/free of traffic during gameplay; no NavigationServer for lane traffic.
- No questionable fonts/assets; no competitor code or assets.
- Don't claim "fun"/"works" without running the scenario tests and, for feel, a human playtest.

## Current phase & next step

Delivered: v0.01, v0.01a, v0.02, v0.03A, v0.03A1, v0.03A2, v0.03B Fort–Pettah Gateway, v0.03B1 performance + visual quality (`docs/PROTOTYPE_V003B1_REPORT.md`). **Next: owner installs the debug APK, judges the look and answers the 10 questions in the v0.03B1 report.** Do not start economy, garage, progression, monetisation, police, weather, day/night, map expansion or v0.04 without approval.

## Known technical debt

- Road geometry is generated at runtime (not `@tool`), so `test_track.tscn` looks empty in the editor.
- Hand-written `.tscn/.tres` without UIDs (Godot adds them when re-saved in the editor).
- Traffic: no lane changes; treats the player as an obstacle only in a straight line ahead; kinematic traffic can shove the player; yields only to occupied crossings.
- v0.03B art is procedural first-pass (vertex colour, no hand-modelled assets); audio is synthesised placeholder (no real recordings, no VO); Sinhala/Tamil sign/locale strings need native review.
- Pedestrians: uneven density (no sidewalks on the loop's east side). Pickups now face legal directions, so some quoted routes are long laps (e.g. careful passenger 0.9–1.2 km).
- Android: debug APK only (80 MB, mostly the debug engine library); graphics tier not auto-selected per device; no haptics. v0.03A1 steering/GPS/incidents not yet judged on a phone.
- Incidents: driver exit/argue is procedural rig animation with placeholder audio; the chase camera can hide a driver in front of the tuk; door side is fixed to the vehicle's right.
- GPS: turns only at junction connectors; the test track has few junctions, so most instructions are PICKUP/DESTINATION distances; ribbon is prototype styling.
- Near-miss footprint is the 1.3 × 2.6 m bounding box while physics uses a tapered hull (nose passes scored slightly conservatively).
- Roll-state signal (`TukController.roll_state_changed`) has no player-facing feedback yet.
- Sinhala/Tamil: Noto fonts shipped (v0.03B); strings are placeholders needing native review.
- Performance numbers are from an Apple M2 only; real-device baseline pending (`tools/android_perf_test.sh`).
- HUD built in code rather than in an editable scene.
- World: the long straight's west side has no raised pavement; the open lots inside the loop are large and empty; district ring is grey-box; props are not physics bodies (by design); no permanent vehicle deformation; evasion/dive are placeholder hop/lean (no animation).
