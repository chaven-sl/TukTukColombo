# Architecture (v0.4 — Prototype v0.03A)

## System map

```
                       ┌───────────────────── autoloads ─────────────────────┐
                       │ EventBus   SaveManager(SaveStore)   PlatformServices │
                       │ GameState (score, session stats, pause, debug flags) │
                       └──────────────────────────────────────────────────────┘
bootstrap.tscn ──► prototype_main.tscn (composition root: prototype_main.gd)
   ├─ TestTrack            RoadNetwork ─ RoadChain ─ RoadSegment …  IntersectionController
   │                         └─ builds Lane graph, connectors, spawn slots, scenery, tunnels, sidewalks
   │   └─ Pedestrians      PedestrianNetwork (walk graph, CrossingZones → Lane.crossings, PedestrianSpots)
   ├─ PlayerTuk            TukController (RigidBody3D) ◄─ PlayerInputSource (InputMap)
   ├─ ChaseCamera          follows interpolated tuk transform; impulse on `impacted`
   ├─ TrafficManager       TrafficPool(24 TrafficAgent) + AdaptiveTrafficBudget
   │                         agents ask IntersectionController for permission
   ├─ NearMissDetector     reads player + active agents ─► EventBus.skill_event
   ├─ ScoringSystem        ComboManager; EventBus.skill/collision ─► score_awarded, combo_changed
   ├─ HumanManager         pooled HumanAgents (roles + behaviours), ambient/groups/passengers,
   │                         player-safety checks → EventBus.pedestrian_danger / pedestrian_impact
   ├─ PassengerOfferManager one physical passenger + destination per pickup spot
   ├─ RideManager          ride state machine, RideTelemetry, PassengerReactionSystem → RideResult
   ├─ RideHud              offer card, ride panel, reaction bubble, result card, beacons
   ├─ HUD (PrototypeHud)   listens to EventBus; reads player telemetry
   ├─ DebugOverlay         F1/F2/F3
   └─ Pause                Esc
```

## Event flow

1. `TukController` detects body contact → `CollisionEvent` (MINOR/MAJOR/ROLLOVER) → `impacted` (local, camera) + `EventBus.collision_event`.
2. `NearMissDetector` confirms a pass → `SkillEvent` (CLOSE_CALL / TIGHT_GAP) → `EventBus.skill_event`.
3. `ScoringSystem` consumes both: skill → `ComboManager.register_event(base)` → `GameState.add_score` → `EventBus.score_awarded` + `combo_changed`; collision → `ComboManager.reset()` → `combo_changed(0)` + local `combo_lost`.
4. `PrototypeHud` renders popups/combo; `GameState` persists bests via `SaveManager` (autosave every 20 s when dirty, on pause and on quit).

5. (v0.02) `HumanManager` emits `pedestrian_danger` (never a reward) and `pedestrian_impact` (combo reset, ride failure, unsafe incident). `RideManager` turns skill/collision/pedestrian events plus per-tick samples into `RideTelemetry`; `PassengerSatisfaction` scores it with the passenger's profile; `ride_finished` carries the `RideResult` to `GameState` (save v2) and the HUD.

## Why these choices

| Decision | Reason |
|---|---|
| Custom raycast 3-wheel RigidBody | The single front wheel's stability triangle *is* the tuk feel; VehicleBody3D hides it. |
| Kinematic `AnimatableBody3D` traffic, `sync_to_physics = false` | Cheap, deterministic lane following; the player still collides with it. Sync-to-physics caused one-frame "teleports" of freshly pooled agents (found by the soak test). |
| One update loop in `TrafficManager` | 20 agents, one script callback, ordered spawning/despawning. |
| Lane graph (`Lane` polylines) not navigation | Lanes are known; graph lookup is O(1) and data-driven. |
| `IntersectionController` owns right-of-way | Agents never guess priority; conflicts are computed from connector geometry. |
| Player-centric traffic bubble, spawn ahead | Density where the player can interact; fog + tunnels hide spawns. |
| Pure-logic RefCounted classes | Unit-testable without scenes. |
| `SimClock` from physics frames | Headless `--fixed-fps` tests behave exactly like play. |
| Physics interpolation on | Smooth on high-refresh displays; teleports call `reset_physics_interpolation()`. |
| One `HumanAgent` for every person, roles as behaviour objects | Pedestrians and passengers share pooling, movement, reactions and presentation; future vendors/police are new roles, not new systems. |
| People have no physics body | They must never shove (or be shoved by) the rigid tuk; contact is a gameplay event from a footprint check. |
| Crossings live on the lane graph (`Lane.crossings`) | Traffic yields without knowing HumanAgent exists; pedestrians query traffic per crossing, not per frame per person. |
| Profile-neutral `RideTelemetry` + one `PassengerSatisfaction` | The same drive can be scored for any passenger — the central v0.02 design experiment — with no per-passenger code. |
| Pedestrian events on separate signals from `SkillEvent` | Makes "people are never a reward" structural, not a convention. |

## Data layout

- `data/vehicles/vehicle_tuning.gd` → `resources/vehicles/tuk_player_tuning.tres`
- `data/camera/chase_camera_config.gd` → `resources/vehicles/chase_camera.tres`
- `data/traffic/{traffic_vehicle_class,traffic_config,traffic_budget_config}.gd` → `resources/traffic/*.tres`
- `data/scoring/scoring_config.gd` → `resources/scoring/scoring_config.tres`
- `data/passengers/passenger_profile.gd` → `resources/passengers/{rushed,careful,thrill_seeker}.tres`
- `data/humans/pedestrian_config.gd` → `resources/humans/pedestrian_config.tres`
- `data/rides/ride_config.gd` → `resources/rides/ride_config.tres` (pickup, satisfaction, fare, reactions)

Script defaults are the PROTOTYPE BASELINE; `.tres` files override only where an instance differs. Tune in the inspector on the `.tres`.

## Future layering (must stay easy)

`Player Tuk → Passenger Profile → Fare/Mission → Traffic Skill → Passenger Satisfaction → Reward → Progression`.
Skill events already carry clearance, relative speed, side and `is_oncoming`, which a future `PassengerSatisfaction` system can weight with `PassengerProfile` fields. A mission layer will sit beside `ScoringSystem` and subscribe to the same EventBus signals; nothing in v0.01 needs to change for that.

## Mobile layer (v0.4)

- **Input:** `InputMode` picks keyboard (`PlayerInputSource`) *or* touch (`TouchInputSource`) once at startup; both only write `VehicleInputState`. `MobileControls` (CanvasLayer) turns raw `InputEventScreenTouch/Drag` into a pure `TouchControlState`; layout is the pure `MobileLayout.compute()` against the display safe area. Taps reuse existing paths (`EventBus.horn_sounded`, `RideManager.request_accept()`, `GameState.set_paused()`). See `mobile_input.md`.
- **Lifecycle:** `PauseController` owns Android Back (pause ↔ resume, never quit) and focus loss (pause, no auto-resume). `GameState` still flushes stats on app pause.
- **Platform:** `GraphicsProfile` Resources (LOW/MEDIUM/HIGH) applied by the composition root. `SessionPerformanceMonitor` + `DevicePerfTest` (autopilot, fixed seeds) for device baselines. `AutopilotDriver` now lives in `scripts/debug/` so builds can run the perf test.
- **Routes:** `RoadNetwork.route(from, to, heading)` is direction-aware (start lanes follow the heading or kerb lane; destination snaps to its kerb lane), falling back to the undirected search only when no legal route exists.
- **Ride HUD:** in-ride mood is qualitative (`PassengerMood`: HAPPY / IMPATIENT / NERVOUS / EXCITED / BORED / UPSET) from projected subscores; the numeric rating stays on the result card only.

## Road construction

`RoadSegment` = straight or constant-radius arc with lane count, lane/median/shoulder widths (each can taper), edge type (kerb/barrier/none). `RoadChain` places children end to end, can start at an intersection arm and end in a tunnel portal. `RoadNetwork.build()` lays out chains, builds geometry + collision, generates lanes, auto-connects coincident lane ends, asks each `IntersectionController` to build connectors and conflicts, then builds spawn slots, scenery and the lane debug mesh. New districts = new chains of segments; no traffic code changes.
