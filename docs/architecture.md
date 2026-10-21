# Architecture (v0.2 — Prototype v0.01)

## System map

```
                       ┌───────────────────── autoloads ─────────────────────┐
                       │ EventBus   SaveManager(SaveStore)   PlatformServices │
                       │ GameState (score, session stats, pause, debug flags) │
                       └──────────────────────────────────────────────────────┘
bootstrap.tscn ──► prototype_main.tscn (composition root: prototype_main.gd)
   ├─ TestTrack            RoadNetwork ─ RoadChain ─ RoadSegment …  IntersectionController
   │                         └─ builds Lane graph, connectors, spawn slots, scenery, tunnels
   ├─ PlayerTuk            TukController (RigidBody3D) ◄─ PlayerInputSource (InputMap)
   ├─ ChaseCamera          follows interpolated tuk transform; impulse on `impacted`
   ├─ TrafficManager       TrafficPool(24 TrafficAgent) + AdaptiveTrafficBudget
   │                         agents ask IntersectionController for permission
   ├─ NearMissDetector     reads player + active agents ─► EventBus.skill_event
   ├─ ScoringSystem        ComboManager; EventBus.skill/collision ─► score_awarded, combo_changed
   ├─ HUD (PrototypeHud)   listens to EventBus; reads player telemetry
   ├─ DebugOverlay         F1/F2/F3
   └─ Pause                Esc
```

## Event flow

1. `TukController` detects body contact → `CollisionEvent` (MINOR/MAJOR/ROLLOVER) → `impacted` (local, camera) + `EventBus.collision_event`.
2. `NearMissDetector` confirms a pass → `SkillEvent` (CLOSE_CALL / TIGHT_GAP) → `EventBus.skill_event`.
3. `ScoringSystem` consumes both: skill → `ComboManager.register_event(base)` → `GameState.add_score` → `EventBus.score_awarded` + `combo_changed`; collision → `ComboManager.reset()` → `combo_changed(0)` + local `combo_lost`.
4. `PrototypeHud` renders popups/combo; `GameState` persists bests via `SaveManager` (autosave every 20 s when dirty, on pause and on quit).

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

## Data layout

- `data/vehicles/vehicle_tuning.gd` → `resources/vehicles/tuk_player_tuning.tres`
- `data/camera/chase_camera_config.gd` → `resources/vehicles/chase_camera.tres`
- `data/traffic/{traffic_vehicle_class,traffic_config,traffic_budget_config}.gd` → `resources/traffic/*.tres`
- `data/scoring/scoring_config.gd` → `resources/scoring/scoring_config.tres`
- `data/passengers/passenger_profile.gd` → `resources/passengers/{rushed,careful,thrill_seeker}.tres`

Script defaults are the PROTOTYPE BASELINE; `.tres` files override only where an instance differs. Tune in the inspector on the `.tres`.

## Future layering (must stay easy)

`Player Tuk → Passenger Profile → Fare/Mission → Traffic Skill → Passenger Satisfaction → Reward → Progression`.
Skill events already carry clearance, relative speed, side and `is_oncoming`, which a future `PassengerSatisfaction` system can weight with `PassengerProfile` fields. A mission layer will sit beside `ScoringSystem` and subscribe to the same EventBus signals; nothing in v0.01 needs to change for that.

## Road construction

`RoadSegment` = straight or constant-radius arc with lane count, lane/median/shoulder widths (each can taper), edge type (kerb/barrier/none). `RoadChain` places children end to end, can start at an intersection arm and end in a tunnel portal. `RoadNetwork.build()` lays out chains, builds geometry + collision, generates lanes, auto-connects coincident lane ends, asks each `IntersectionController` to build connectors and conflicts, then builds spawn slots, scenery and the lane debug mesh. New districts = new chains of segments; no traffic code changes.
