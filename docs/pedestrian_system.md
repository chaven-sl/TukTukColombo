# Pedestrian system

All speeds in km/h.

## Path network (`PedestrianNetwork`)

Generated from the road, so new road blocks bring their own walkways:

- **Sidewalks.** `RoadSegment` exports `sidewalk_left/right`, `sidewalk_width` (2.5 m) and trims. A raised (0.15 m) paved slab is built behind the kerb, with collision, and a walking line of nodes every ~4 m.
- **Joins.** Sidewalk ends within 7.5 m of each other are linked: consecutive segments and junction corners. Crossing a road is only possible through a crossing link.
- **Crossings.** `RoadSegment.crossing_s` / `crossing_styles` create a `CrossingZone`: two kerb-end nodes linked across the road, zebra markings for DESIGNATED crossings, and registration with every lane it crosses (`Lane.crossings`, with the conflict point on each lane).
- **Spots.** `PedestrianSpot` markers (WAIT, GROUP, PICKUP, DROPOFF) are level-authored and snapped to the nearest node. Optional placeholder dressing: bus shelter or shop front.
- **Search.** Breadth-first search over the graph runs only when someone picks a new destination. It reports whether the route uses a crossing (crossing pedestrians prefer such routes).

Test track: sidewalks on the long straight, the wide section, both west straights and both junction arms. 336 nodes, 11 sidewalk paths. Five crossings: zebras on the long straight, west straight B and north street; uncontrolled crossings on the long straight and south street. Three pickups, four destinations, a bus-stop group, a shop-front waiting area and a waiting point near a crossing.

## Archetypes

| Archetype | Behaviour |
|---|---|
| SIDEWALK_WALKER | walks to random destinations 4–40 nodes away, pauses 1–4 s |
| CROSSING_PEDESTRIAN | same, but prefers destinations whose route uses a crossing |
| WAITING_PEDESTRIAN | spawns at a WAIT spot and stands 10–30 s before walking off |
| GROUP_MEMBER | 3 people placed together at a GROUP spot (bus stop); idle, face each other |

Variation per person:
- **Walking speed:** slow 3.0–3.5 km/h (25%), normal 4.0–5.0 km/h (55%), fast 5.5–6.5 km/h (20%).
- **Pause length.**
- **Destination.**
- **Crossing confidence:** each person wants a 1.2–3.2 s gap beyond the time they need to cross.

## Crossing logic

At the kerb, `CrossingZone.assess(time_to_clear, margin, …)` computes the soonest vehicle arrival:
- **Lane traffic:** for every lane crossing the zone, agents on that lane and on its predecessors give a distance to the conflict point ÷ their speed. A vehicle body already on the band means BLOCKED.
- **Player tuk:** projected along the road axis, with its closing speed.

Outcomes:
- **SAFE:** time to the vehicle > time to clear + margin. The person starts CROSSING and the zone becomes occupied.
- **QUESTIONABLE:** inside the margin. The person waits with a HESITATE indicator.
- **DANGER:** a vehicle is closer than time to clear + 0.3 s, or blocking. The person waits; if the threat is the player and under 2 s away, they STEP_BACK.
- **Uncontrolled crossings:** the margin is × 0.65, but never below 0.8 s. People there accept tighter gaps, but nobody steps out without leaving the driver reaction time.
- **Mid-crossing danger:** the person HURRIES (× 1.9 speed) to the nearer side, turning back if under 35% across.
- **Give up:** after 25 s of waiting, the person walks somewhere else instead. This is the deadlock breaker, seen in the junction soak.

Traffic agents yield at an occupied crossing ahead: a stop point 2.5 m before the conflict, using the existing car-following model. They never reference HumanAgent, only `CrossingZone.occupied_count` via their lane.

## Reacting to the player

If the tuk approaches within 10 m, at a closing speed above 14 km/h, on a line passing within 2.5 m:
- **People on the sidewalk or at the kerb:** STEP_BACK, moving 0.9 m/s away from the tuk's line of travel for 1.2 s.
- **Waiting passengers:** they FREEZE (indicator only).
- **People crossing:** HURRY.

Indicators: yellow = hesitate, orange = step back / hurry, red = freeze. F4 shows the state, role and reaction labels, plus the walkway graph (crossings in green for designated, orange for uncontrolled).

Testing found a real defect: step-back first used the home sidewalk's "away from road" direction. A person standing in the road could step *into* the tuk's path. It now steps away from the tuk's actual line.

## Safety events (never rewards)

| Event | Condition | Effects |
|---|---|---|
| PEDESTRIAN_DANGER | tuk passes within 1.2 m of a person above 20 km/h; or drives on the sidewalk within 2.5 m above 10 km/h; or forces a crossing person to hurry. 3 s cooldown per person. | passenger safety and satisfaction down, a negative reaction, incident counters. **No score, no combo, no fare, no excitement.** |
| PEDESTRIAN_IMPACT | person's footprint inside the tuk's, above 3 km/h | person removed immediately (non-graphic, back to the pool); combo reset; an active ride FAILS; "UNSAFE DRIVING" notice; unsafe-incident counter saved |

The vehicle near-miss detector only reads `TrafficManager.active_agents` (`TrafficAgent`s). People are never in that list, so a person can never produce CLOSE CALL or TIGHT GAP. This is covered by a scenario test that drives between two people at 50 km/h, and by the satisfaction fuzz test.
