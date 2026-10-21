# TukTuk Colombo — working instructions

Original stylised Sri Lankan tuk-tuk driving game. Current phase: **Prototype v0.02 — human world + passenger vertical slice** (complete, awaiting owner playtest). v0.01a vehicle handling is the approved **MVP HANDLING BASELINE**: do not retune steering, CoM, grip, suspension, rollover, roll assist, engine or brakes unless a reproducible defect requires it — document and report first. Handling philosophy: **high agility + high consequence** — the tuk always turns when asked; overcommitting at speed is punished by roll, wheel lift and rollover, never by removing steering authority. Objective of v0.01: *make driving a three-wheeler through moving traffic genuinely enjoyable for five minutes.* Everything else is infrastructure.

## Repository identity

- Production repository: https://github.com/chaven-sl/TukTukColombo.git (`chaven-sl/TukTukColombo`), default branch `main`.
- Never modify, commit to, push to, or import production code from any other repository.
- Before any git push, confirm `git remote -v` shows `origin` as the URL above and `gh auth status` shows `chaven-sl` as the active account.
- Logical commits (`feat(vehicle): …`, `fix(traffic): …`, `test(prototype): …`). Never force-push or rewrite history. Never commit `.godot/`, build output or editor junk.

## Competitor research

- Competitor APK research is external research only. It lives outside this repository (`../research/`).
- Never commit APKs, decompiled code, extracted assets, or research notes from it into this repository. Use it only as reference; write all game code and assets from scratch.

## Fixed stack (do not change without explicit approval)

Godot **4.7.2 stable** · **GDScript** · **Mobile** renderer · **Jolt** physics · Android first (develop on macOS) · landscape · 3D stylised realism · low third-person chase camera. Never migrate to Unity/Unreal/C#/Forward+/Compatibility. No third-party plugins, vehicle packages, asset packs or SDKs.

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
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tests/scenarios/traffic_soak_test.tscn -- --duration=360 [--park-near-junction]
# Real window: FPS + screenshots to user://test_results/screens
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/scenarios/traffic_soak_test.tscn -- --duration=60 --screenshots [--perf]
```

Scripts that reference autoloads (EventBus, GameState…) cannot be loaded in `--script` mode; test them in scene-based scenarios. A script parse error makes headless Godot wait forever — `tools/run_tests.sh` wraps every stage in a timeout. Run `--import` after adding any new `class_name` script (refreshes the global class cache used by headless runs). "It compiles" is not a test result — run the scenario that exercises the change.

## Architecture principles

- **Composition over monoliths.** No GameManager. `scenes/prototype/prototype_main.gd` is the composition root: it wires systems explicitly; systems never look each other up by arbitrary scene path.
- **Data-driven.** Tunables live in Resources: class scripts in `data/`, instances (`.tres`) in `resources/`. Mark prototype values `PROTOTYPE BASELINE`.
- **Signals.** Local signals between neighbours; `EventBus` only for cross-system gameplay events (`skill_event`, `collision_event`, `score_awarded`, `combo_changed`, `performance_budget_changed`, `player_reset`, `horn_sounded`).
- **Minimal autoloads:** `EventBus`, `SaveManager`, `PlatformServices`, `GameState` (in that order). Nothing else is global.
- **Detection ≠ scoring ≠ UI.** `NearMissDetector` emits events → `ScoringSystem`/`ComboManager` decide value → HUD presents.
- **People are never a reward.** Pedestrian incidents use their own signals (`pedestrian_danger`, `pedestrian_impact`); they must never reach score, combo, fare or passenger excitement. The near-miss detector only reads `TrafficAgent`s.
- **One human foundation.** Every person is a pooled `HumanAgent`; new kinds of people are new roles + behaviour objects, not new systems. People have no physics body.
- **One satisfaction model.** Passengers differ only through `PassengerProfile` data; never add per-passenger scoring code.
- **Pure logic is testable.** Rules live in RefCounted classes (`ComboManager`, `AdaptiveTrafficBudget`, `SaveStore`, `OrientedRect`, `VehicleTuning` helpers) with nodes as thin wrappers.
- **Platform isolation.** Gameplay never calls SDKs; it calls `PlatformServices` (no-op in v0.01).
- **Debuggable.** F1 overlay / F2 traffic / F3 vehicle; debug code lives in `scripts/debug/` and is removable.

## Directory rules

| Path | Contents |
|---|---|
| `autoload/` | the four global services only |
| `data/<domain>/` | Resource **class** scripts (schemas) |
| `resources/<domain>/` | Resource **instances** (`.tres`) |
| `scenes/<domain>/` | scenes; a scene's root script may sit beside it |
| `scripts/<domain>/` | runtime code: `player camera traffic road humans rides scoring performance ui debug utilities` |
| `locale/` | `en.po si.po ta.po` |
| `tests/unit/` | headless logic tests (`test_*.gd`, extend `tests/test_case.gd`) |
| `tests/scenarios/` | scene-based simulation tests; `tests/support/` test-only helpers (autopilot) |
| `docs/` | design/technical docs and reports |
| `assets/` | original placeholder assets only |

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

Delivered: v0.01 (`docs/PROTOTYPE_V001_REPORT.md`), v0.01a (`docs/PROTOTYPE_V001A_REPORT.md`), v0.02 (`docs/PROTOTYPE_V002_REPORT.md`). **Next: owner playtest answering the 10 experiential questions in the v0.02 report.** Do not start v0.03 (touch controls, audio, art, economy, more passengers) without that review.

## Known technical debt

- Road geometry is generated at runtime (not `@tool`), so `test_track.tscn` looks empty in the editor.
- Hand-written `.tscn/.tres` without UIDs (Godot adds them when re-saved in the editor).
- Traffic: no lane changes; treats the player as an obstacle only in a straight line ahead; kinematic traffic can shove the player; yields only to occupied crossings.
- Pedestrians: placeholder figures, no animation; uneven density (no sidewalks on the loop's east side); route estimates may imply a U-turn at pickup.
- Android toolchain not configured on this Mac (no templates/SDK/JDK).
- Near-miss footprint is the 1.3 × 2.6 m bounding box while physics uses a tapered hull (nose passes scored slightly conservatively).
- Roll-state signal (`TukController.roll_state_changed`) has no player-facing feedback yet.
- Sinhala/Tamil: no shipped font with those glyphs; strings are placeholders needing native review.
- Performance numbers are from an Apple M2 only; no Android measurement yet.
- HUD built in code rather than in an editable scene.
