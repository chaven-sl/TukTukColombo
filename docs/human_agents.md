# Human agents

Every person in the world, whether an ambient pedestrian or a passenger, is a pooled `HumanAgent` (`scripts/humans/human_agent.gd`). There is no separate "Pedestrian" or "Passenger" class: roles share one foundation.

```
HumanAgent (Node3D, pooled, no physics body)
  ├─ role: SIDEWALK_WALKER | CROSSING_PEDESTRIAN | WAITING_PEDESTRIAN | GROUP_MEMBER | PASSENGER
  ├─ state (explicit, validated) + reaction (HESITATE / STEP_BACK / HURRY / FREEZE)
  ├─ behaviour: PedestrianBehaviour (ambient roles) | PassengerBehaviour (PASSENGER)
  └─ Visual (placeholder): capsule body, sphere head, passenger marker, reaction dot, debug label
```

Future roles (vendor, police, bus passenger, mission NPC) slot in as new `Role` values with their own behaviour object. None are implemented.

## Traffic drivers (v0.03A1)

Role `TRAFFIC_DRIVER` + `DriverBehaviour`; states `EXITING_VEHICLE →
APPROACHING_PLAYER → ARGUING → RETURNING_TO_VEHICLE` (then back to the pool).
Only in the world during a traffic altercation; owned by
`TrafficIncidentManager`; never despawned by the ambient population logic;
one pool slot reserved. See `traffic_incidents.md`.

## Why not a physics body

People are a gameplay concept, not physics obstacles. A `CharacterBody3D` or `RigidBody3D` would let the player's rigid tuk be shoved by, or shove, people in absurd ways, and would cost broadphase time. Contact with the tuk is decided by `HumanManager` with an allocation-free footprint test (`OrientedRect.point_distance`, person radius 0.28 m) and handled as the `PEDESTRIAN_IMPACT` gameplay event. Traffic never collides with people either: it yields at crossings through `CrossingZone`.

## State machine

| State | Owner | Meaning |
|---|---|---|
| INACTIVE | HumanManager | in the pool, hidden |
| IDLE | PedestrianBehaviour | standing (pause, waiting spot, group) |
| WALKING | PedestrianBehaviour | following a node path on the pedestrian graph |
| WAITING_TO_CROSS | PedestrianBehaviour | at the kerb end of a crossing, judging traffic |
| CROSSING | PedestrianBehaviour | on the carriageway (crossing occupied) |
| REACTING | PedestrianBehaviour | stepping back or freezing because of the tuk |
| WAITING_FOR_PICKUP | PassengerBehaviour | passenger at the pickup spot |
| APPROACHING_TUK | PassengerBehaviour | walking to the tuk's BoardingPoint |
| BOARDING | PassengerBehaviour | short boarding beat (0.8 s) |
| RIDING | PassengerBehaviour | hidden, following the tuk's SeatMarker |
| EXITING | PassengerBehaviour | walking from the tuk to the drop-off |
| RETURNING_TO_POOL | HumanManager | being released |

Transitions are whitelisted in `HumanAgent.TRANSITIONS`. Each role object owns the transitions between its own states (no global match statement). `set_state()` rejects and counts anything else (`HumanAgent.invalid_transitions`, asserted to stay 0 in tests and the soak). Leaving WAITING_TO_CROSS or CROSSING always releases the crossing's waiting/occupied counters, including when someone is pulled back into the pool mid-crossing. Every active state can return to the pool.

## Presentation contract

The logic never touches meshes beyond the placeholder visual it owns. A future animated character only needs to replace `Visual` and read `state`, `reaction`, `is_moving` and the facing. The tuk scene has `SeatMarker` and `BoardingPoint` nodes, so a visible seated passenger later needs no restructuring.

## Pool and population (`HumanManager`)

| Setting | Value |
|---|---|
| Pool capacity | 18 (3 slots reserved for passengers) |
| Ambient target | 8 (walkers, crossers, waiters, groups) |
| Max active | 12, passengers included |
| Spawn band | 30–95 m from the player; never in view closer than 70 m |
| Despawn | beyond 130 m and out of view (passengers are never despawned by distance) |

There is one update loop for all agents. Crossing awareness is staggered (every 0.15 s per person, with random phase). Cost measured on the M2: about 0.04–0.1 ms per physics tick.

Extensibility (not built): lower update rates by distance, LOD/impostors for distant crowds, and a device-adaptive density ceiling (the same pattern as `AdaptiveTrafficBudget`).
