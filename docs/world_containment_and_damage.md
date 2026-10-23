# World containment, crash consequences and recovery (v0.03A2)

Owner playtest: the tuk could leave the road and drive forever into empty
world. Principle: **no invisible walls beside roads**. The hierarchy is

| Layer | Surface (`WorldSurface.Type`) | Behaviour |
|---|---|---|
| Road | ROAD | normal driving |
| Pavement / forecourt / open lots | SIDEWALK, FORECOURT, KERB | physically accessible, dangerous (people) |
| Shopfronts, buildings, walls, poles | BUILDING, WALL, PROP | real collision, can damage the tuk |
| Outside the district / below the world | VOID | failsafe recovery only |

## Surface model

`WorldSurface` (pure, `scripts/world/`) tags every static body at build time
(meta `surface`): road edge bodies KERB (or WALL for jersey barriers), ground
FORECOURT, scenery blocks BUILDING, trees/lamps/shelter posts PROP, tunnel
WALL, spot shop blocks BUILDING, district ring BUILDING/WALL.
`classify_point()` answers ROAD / SIDEWALK / FORECOURT / VOID for a position.
`CollisionEvent.other_body` (+ approach speed, frontality) is the only
TukController change — it stays map-agnostic.

## Physical containment

- **District ring** (`DistrictBoundary`): the road network's footprint + 38 m,
  enclosed by a continuous ring of grey-box buildings (6–18 m) and compound
  walls just outside it. One MultiMesh + one static body of boxes.
- **Shopfront row**: behind every pavement, buildings now stand 1.2–3.5 m
  back (a forecourt) instead of 5–10 m; elsewhere blocks stay set back.
- **Spot dressing** (shop front block, bus-shelter posts) now has collision.
- Kerbs stay physical: chamfered 15 cm kerb resists at low speed, climbs at
  ~25 km/h (tested: 27 → 22 km/h scrub while climbing).
- Open lots between the roads and the ring stay drivable.
- Known: the long straight's west side has no raised pavement (pre-existing).

## Crash damage (`VehicleDamageState`, `resources/vehicles/vehicle_damage.tres`)

Only solid structures (BUILDING / WALL / PROP) damage the tuk; kerbs, ground
and traffic never do. Impact = velocity change across the hit (km/h).
Measured head-on into a building the tuk stops dead: 15→15, 22→22, 30→30,
40→40, 50→48 km/h; glancing hits produce less.

| Tier | Impact | Result |
|---|---|---|
| LIGHT | < 16 km/h | dust puff, keep driving |
| HARD | 16–33 km/h | DAMAGED: engine cut 1.2 s, then limp (60 % throttle) for 8 s, smoke |
| DISABLING | ≥ 33 km/h, or HARD while DAMAGED | DISABLED: engine off, comes to rest, "TUK DISABLED / RESETTING TO ROAD" ~2 s, road reset |

Applied in the **input layer** (`VehicleDamageManager`, physics priority −5,
between input sources and the tuk) — vehicle physics are untouched. A
1.5 s grace after any reset prevents reset loops. Effects: dust/debris burst,
sparks on hard hits, lingering smoke while damaged (pre-built CPU particles,
no fire, no explosion).

An **active ride fails** on DISABLED (`FailReason.VEHICLE_DISABLED`, no fare,
passenger collision line). HARD crashes keep the ride (existing collision
penalties apply).

## Recovery (`WorldRecoveryManager`)

Owns `TukController.reset_pose_provider`: every reset (R, tipped
auto-recover, DISABLED, failsafe) goes to the nearest legal lane, 10 m
**behind** the crash point if clear (then −18, −4, −26, +6 … m), upright,
facing the lane direction, clear of traffic (9 m), people (5 m) and
junction boxes. Camera snaps (existing `was_reset`), GPS recalculates
(existing `player_reset`). Never the world origin.

Failsafe (bug protection): below y −4 or outside the district rect + 3 m →
recover("void"). Tests: never triggered by driving.

## Impact props (`ImpactPropManager`)

Up to 16 signs, box stacks, cones, stall boards and displays along pavement
back edges. Not physics bodies (they never stop the tuk): a cheap footprint
test near the player; < 6 km/h wobble, else knocked with a ballistic tumble;
box stacks/displays shed pooled debris (≤ 18 pieces); settle, shrink away,
respawn out of view after 25 s. `EventBus.prop_knocked` audio hook.
Building walls are never destructible.

## Hooks

`EventBus.world_impact(tier, pos, surface)`, `vehicle_damage_changed(state)`,
`vehicle_recovered(reason)`, `prop_knocked(pos, kind)`.
