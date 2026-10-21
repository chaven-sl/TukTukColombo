# Traffic system

## Lanes and roads

- `Lane` (RefCounted): world-space polyline, cumulative distances, per-point **curvature advisory speed** (√(a_lat·r), smoothed), successors/predecessors/neighbours, and junction connector data. Agents are addressed as `(lane, s)`.
- `RoadSegment` generates `lanes_per_direction` lanes each way. Left-hand traffic: forward lanes left of the centre line, lane 0 innermost.
- `RoadNetwork` auto-connects lanes whose end/start coincide (≤0.75 m, aligned), so chains and closed loops link without manual wiring. Lanes with no predecessor are **sources** and no successor are **sinks** (both inside tunnel portals).

## Test track

Closed loop (~1.2 km, 2+2 lanes): 260 m long straight → gentle 90° curve (r 90 m) → **wide** section (3.8 m lanes, 2.5 m shoulders, painted median, tapers in/out) → **sharp** 90° corner (r 22 m) → **narrow** section (2.9 m lanes, concrete barriers, tapers) → 208 m straight → corner (r 40 m) → **four-way junction** → corner back to start. North and south arms (1+1 lanes, 110 m) end in tunnel portals that hide traffic sources/sinks. Kerbs are black/white striped and chamfered so wheels ride up. Player spawns at the start of the long straight (quiet initial zone). Roadside grey-box blocks, trees and lamp posts (MultiMesh) give speed reference.

## Intersection

`IntersectionController` (one per junction):
- **Connectors** built from every lane ending/starting on its box edges. Movement from the turn angle (straight / left / right). Lane-use rules (left-hand traffic): left turns kerb lane → kerb lane, right turns inner lane → inner lane, straight keeps index. 14 connectors on the test junction.
- **Conflicts**: two connectors conflict if their paths pass within 2.3 m or share an exit lane (merge); connectors from the same approach lane don't (that is a queue handled by car-following).
- **Signals**: through-axis green 14 s → amber 3 s → all-red 1.5 s → cross-axis green 9 s → amber 3 s → all-red 1.5 s. Signal heads change colour.
- **Permission** = green (amber only for agents that can't stop comfortably, or give-way agents already waiting at the line) AND no conflicting connector reserved/occupied AND exit lane has room AND, for right turns (give-way), no priority agent within 32 m about to use a conflicting path.
- Agents check `is_movement_open()` while approaching (no reservation, so they don't slow for green lights) and `request_entry()` within their stopping distance (+5 m), which reserves until they leave the connector. A safety net clamps an agent at the stop line if it would otherwise enter without permission.

## Agents

`TrafficAgent` (`AnimatableBody3D`, kinematic, box collider on the traffic layer, no shadows). Speed via the **Intelligent Driver Model** against the nearest of: leader on this lane / next lane / sibling connectors / one lane beyond; the player (straight-line check ahead); an unpermitted stop line. Desired speed = random per-spawn target in the class range, reduced ahead of curves using the advisory speeds with comfortable braking. Pose = midpoint of samples ±0.6·half-length along the path, so vehicles turn smoothly through curves. Player contact: hold for 1.5 s.

| Class | Size L×W×H (m) | Speed range | Pool | Spawn weight |
|---|---|---|---|---|
| CAR | 4.3 × 1.8 × 1.5 | 25–48 km/h | 12 | 5 |
| BUS | 11 × 2.5 × 3.1 | 20–40 km/h | 3 | 1.2 |
| MOTORCYCLE | 2.0 × 0.8 × 1.45 | 30–55 km/h | 5 | 2 |
| TUK | 2.6 × 1.3 × 1.75 | 22–42 km/h | 4 | 2 |

Lane changing is **not** implemented (`lane_change_tendency` reserved).

## Pool and population

`TrafficPool`: 24 agents built at level start, bucketed by class; acquire/release only. `TrafficManager` runs one loop over active agents each physics tick, tries a spawn every 0.2 s (two when ≥4 short), and runs a despawn pass every 0.25 s.

- **Spawn**: scans all ~360 precomputed road slots for those 75–170 m away, **ahead of the player's travel direction** when moving, and out of the camera view unless beyond 110 m (fog). Also 25 % chance to use a hidden tunnel source. Lane separation ≥22 m and ≥12 m from any agent. Initial fill allows ≥30 m but never within 60 m straight ahead.
- **Despawn** (only when out of view): beyond 190 m; more than 45 m behind a moving player; parked at a sink; stopped >30 s (anti-deadlock); or over the budget target.
- Sink agents seen by the camera wait at the tunnel end instead of vanishing.

## Adaptive traffic budget

`actual_target = min(gameplay_density_target (14), performance_ceiling)`. `AdaptiveTrafficBudget` averages FPS over 0.5 s windows. Below 27 FPS for 3 s → ceiling −2; above 50 FPS for 10 s → +1; between thresholds both timers reset; 4 s cooldown between changes; ceiling ∈ [8, 20], starts at 14. Changes emit `EventBus.performance_budget_changed`. Config: `resources/traffic/traffic_budget.tres`.

## Verified (see testing.md)

6 simulated minutes driving + 6 minutes parked by the junction: pool never leaks (free + active = 24 every second), no node growth, active ≤14 (min 11–13 after fill), 0 visible spawns, 0 teleports, 0 traffic self-overlaps, junction 104 grants (57 through / 47 cross), longest red wait 22 s, longest gap between grants 15 s, target-speed σ ≈ 7.5 km/h, ~1.5 close calls/min from a crude autopilot, 0.8 collisions/min.
