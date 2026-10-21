# Prototype v0.02 Report — Human World + Passenger Vertical Slice (Architecture v0.3)

Date: 2026-10-21 · Godot 4.7.2 · Mobile renderer · Jolt · tested on Apple M2 · **all speeds in km/h**

# STATUS

**PASS — awaiting owner playtest.**

Every item in the v0.02 definition of complete is implemented and covered by automated tests. All eight test stages pass: unit, handling, dynamics, scoring, human world + passengers, input smoke, and two 6-minute soaks with traffic and humans.

What's still unverified is the *feel* (does each passenger change how you drive?), which needs the owner. Android is blocked: no tooling is configured on this Mac.

Vehicle physics were not changed. The v0.01a handling baseline is untouched (`vehicle_tuning.gd` and `tuk_controller.gd` are unchanged); the tuk scene only gained `SeatMarker` and `BoardingPoint` markers.

# HUMAN NPC ARCHITECTURE

There is one shared foundation, `HumanAgent`: a pooled `Node3D` with no physics body. It has a role (SIDEWALK_WALKER, CROSSING_PEDESTRIAN, WAITING_PEDESTRIAN, GROUP_MEMBER, PASSENGER), a validated state machine, a reaction state, and a behaviour object per role (`PedestrianBehaviour`, `PassengerBehaviour`).

`HumanManager` owns the pool, the ambient population, the groups, passenger acquisition, one update loop, and the player-safety checks. Presentation is a swappable placeholder (capsule and head, marker, reaction dot, F4 label), so animated characters can replace it later without behaviour changes.

Future roles (vendor, police, bus passenger, mission NPC) are new Role values plus a behaviour object. None are built. Details are in `docs/human_agents.md`.

# NPC STATE MACHINE

States: `INACTIVE, IDLE, WALKING, WAITING_TO_CROSS, CROSSING, REACTING, WAITING_FOR_PICKUP, APPROACHING_TUK, BOARDING, RIDING, EXITING, RETURNING_TO_POOL`.

- **Whitelist:** allowed transitions are listed per state in `HumanAgent.TRANSITIONS`.
- **Ownership:** each behaviour owns its own states; the manager owns the pool states.
- **Rejected transitions:** counted, and must be 0. Results: 0 in the scenario tests and 0 in both soaks.
- **Crossing counters:** waiting/occupied counts are always released on leaving a crossing state.
- **Pool exit:** every state can return to the pool.

# PEDESTRIAN POOL

| | Value |
|---|---|
| Pool capacity | 18 (3 reserved for passengers) |
| Ambient active target | **8** |
| Max active (passengers included) | 12 |
| Spawn | 30–95 m from player, never in view closer than 70 m |
| Despawn | beyond 130 m, out of view (passengers exempt) |

Soak results:
- **Driving:** 197 spawns and 186 releases with zero pool violations, max 12 active, no node growth.
- **Junction:** max 11 active.

# PATH / CROSSING SYSTEM

`PedestrianNetwork` is generated from road segments: sidewalks (a raised 2.5 m paved slab with collision), joins at segment ends and junction corners, crossing links, and level-authored `PedestrianSpot`s. The test track has 336 nodes and 11 sidewalk paths.

- **5 crossings:**
  - **3 designated (zebra):** long straight, west straight B (by the bus stop), north street.
  - **2 uncontrolled:** long straight, south street.
- **Spots:** 3 pickups, 4 destinations (Market, Temple Road, South Junction, Central Stop), a bus-stop **group of 3** with a shelter, a shop-front waiting area, and a waiting point by a crossing.

Details are in `docs/pedestrian_system.md`.

# VEHICLE AWARENESS

`CrossingZone.assess()` is a per-crossing query. It does no per-person physics.
- **Traffic:** for each lane the crossing cuts, vehicles on that lane and its predecessors give time = distance to the conflict point ÷ speed. A vehicle body already on the band means BLOCKED.
- **Player:** the tuk is projected onto the road axis with its closing speed.

Outcomes:
- **SAFE:** cross.
- **QUESTIONABLE:** HESITATE.
- **DANGER:** wait, or STEP_BACK if the player is under 2 s away.
- **Already crossing:** HURRY to the nearer side, turning back if under 35% across.
- **Give up:** after 25 s of waiting, walk elsewhere. This is the deadlock breaker.

Uncontrolled crossings accept tighter gaps (× 0.65), never below 0.8 s beyond the time to clear.

Traffic yields to an *occupied* crossing through `Lane.crossings`. `TrafficAgent` never references HumanAgent.

On the sidewalk, a tuk approaching within 10 m at over 14 km/h on a collision line makes people STEP_BACK away from its line of travel. Waiting passengers FREEZE.

# PEDESTRIAN SAFETY RULES

| Rule | Enforcement |
|---|---|
| People never award CLOSE CALL / TIGHT GAP | The near-miss detector only iterates `TrafficAgent`s. Scenario: drive between two people at 50 km/h → 0 skill events, 0 score, PEDESTRIAN_DANGER registered instead. |
| PEDESTRIAN_DANGER never rewards (no score, combo, fare or excitement) | `ScoringSystem` deliberately does not listen to it. The excitement subscore has no pedestrian inputs. Profile validation requires a positive sensitivity. Penalties are clamped non-positive. 300-ride fuzz test. |
| Even the Thrill Seeker loses satisfaction | Scenario 5: −21 points on the same drive. |
| Impacts are non-graphic | The person is removed instantly (back to the pool): no ragdoll, no gore, no physics toy. |

# PASSENGER ARCHITECTURE

- **Data:** `PassengerProfile` gains `excitement_weight`, `two_wheel_preference`, `pedestrian_danger_sensitivity`, `expected_speed_kmh`, `priority_key` and `marker_color`. The schema is backward-safe and validation/normalisation are tested.
- **Offers:** `PassengerOfferManager` gives one physical passenger per pickup.
- **Lifecycle:** `RideManager` is the explicit ride state machine.
- **Measurement and scoring:** `RideTelemetry` aggregates the ride; `PassengerSatisfaction` is the one shared model.
- **Reactions:** `PassengerReactionSystem` picks lines from profile data.
- **Results:** `RideResult` holds the fare and summary; `RideHud` shows the cards, beacons and bubbles.

Interaction uses the new `interact` InputMap action (E). `RideManager.request_accept()` is input-agnostic, ready for touch.

# THREE PASSENGER PROFILES

| | Late Executive | Careful Aunty | Thrill Seeker |
|---|---|---|---|
| Primary desire | get there fast | safe, smooth journey | exciting vehicle driving |
| Weights time / safety / comfort / excitement | .55 / .25 / .10 / .10 | .10 / .55 / .35 / 0 | .15 / .15 / .05 / .65 |
| Vehicle risk tolerance | 0.6 | 0.1 | 0.95 |
| Close calls / tight gaps | indifferent | dislikes (−0.8) | loves (+0.9) |
| Two-wheel moments | mildly dislikes | hates (−1) | enjoys (+0.7) |
| Collisions | ×1.2 | ×2.5 | ×1.0 |
| Pedestrian danger | ×1.0 (negative) | ×2.0 (strongly negative) | ×1.0 (negative, never positive) |
| Preferred speed | 55 ± 15 km/h | 30 ± 8 km/h | 60 ± 15 km/h |
| "On time" average | 32 km/h | 26 km/h | 30 km/h |
| Typical lines | "Can we go a bit faster? I'm late!" | "Please slow down!" / "Careful! That was far too close!" | "That was close! Again!" / "Through the gap! Yes!" |
| Status | ✅ waits, boards, rides, completes, pays | ✅ | ✅ |

# RIDE LIFECYCLE

`NO_RIDE → OFFER_SELECTED → EN_ROUTE_TO_PICKUP → BOARDING → ACTIVE → ARRIVED → COMPLETED → EXITING → RETURN_TO_IDLE → NO_RIDE`. An active ride can also go to FAILED and then EXITING.

- **Pickup:** within 9 m of the passenger at 5 km/h or less.
- **Arrival:** within 12 m of the destination at 5 km/h or less.
- **Cancel:** the offer is cancelled if the tuk drives more than 90 m away before pickup.
- **Boarding:** reverts if the tuk leaves.
- **Failure:** a pedestrian impact always fails the ride. A confirmed rollover fails it too; that was chosen for clean prototype behaviour and is configurable. Ordinary collisions only lower the rating.

Details are in `docs/ride_system.md`.

# SATISFACTION MODEL

There are four shared subscores (0–100) computed from profile-neutral telemetry:
- **TIME:** actual vs target time; ≤ 0.75 of target = 100, on time = 80, 1.3× = 50, 2× = 8.
- **SAFETY:** collisions, rollover, vehicle risk scaled by (1 − risk tolerance), pedestrian danger and impacts.
- **COMFORT:** hard braking, two-wheel time, extreme roll, collisions, time over the preferred speed, and near misses for people who dislike them.
- **EXCITEMENT:** vehicle events only (close calls, tight gaps, controlled two-wheel moments, time above 45 km/h, combo peak), scaled by the profile's appetite.

The final score is the profile-weighted sum minus severe penalties: per collision, per pedestrian danger, and pedestrian impact. Details are in `docs/passenger_satisfaction.md`.

# SAME-DRIVE DIFFERENT-PASSENGER TEST

Identical telemetry on a 500 m route (`tests/unit/test_passenger_satisfaction.gd`):

| Drive | Late Executive | Careful Aunty | Thrill Seeker | Expected | Result |
|---|---|---|---|---|---|
| 1 Fast + risky | 80.8 | 13.0 | 98.5 | thrill high, rushed good/high, careful low | ✅ |
| 2 Safe + smooth + moderately fast | 76.8 | 99.1 | 41.8 | careful high, rushed good, thrill lower | ✅ |
| 3 Slow + safe | 42.4 | 93.3 | 32.5 | careful acceptable/high, rushed low, thrill low | ✅ |
| 4 Collision-heavy | 5.2 | 0.0 | 0.0 | all poor | ✅ |
| 5 Drive 2 + 2 pedestrian dangers | 51.8 (−25) | 27.5 (−72) | 20.4 (−21) | nobody gains; careful strongly negative | ✅ |
| 5 Drive 1 + 2 pedestrian dangers | 55.8 (−25) | 0.0 | 77.1 (−21) | thrill never positive | ✅ |

The fuzz check found that, across 300 random rides, adding pedestrian danger never increases satisfaction for any profile.

# FARE SYSTEM

- **Base fare:** Rs 100 pickup + Rs 90 per km, rounded to Rs 10.
- **Adjustment:** base × (rating − 60%) × 0.5%, between −50% and +40%, rounded to Rs 10.
- **Failed ride:** no fare.

The result card shows the base fare, rating, adjustment and final fare. Fares in the scenario tests:
- Market 414 m: Rs 140 + 20 = Rs 160.
- South Junction 400 m: Rs 140 + 30 = Rs 170.
- Temple Road 361 m: Rs 130 − 10 = Rs 120.

There is no spending or economy; `prototype_fares_total` is a saved statistic only.

# PEDESTRIAN COLLISION HANDLING

An impact is the person's footprint overlapping the tuk at over 3 km/h. It leads to:
- `EventBus.pedestrian_impact`;
- the person removed immediately (non-graphic) and returned to the pool;
- combo reset ("COMBO LOST");
- an active ride FAILED with no fare and satisfaction ≈ 0;
- an "UNSAFE DRIVING" notice;
- the `pedestrian_impacts` save counter.

With no ride active, it's recorded as an unsafe-driving incident and driving continues. People are not physics obstacles, so they never shove the tuk.

# SAVE MIGRATION

Schema 1 → 2 (`SaveStore._migrate_1_to_2`). It adds `rides_completed`, `rides_failed`, `best_passenger_satisfaction`, `pedestrian_impacts`, `prototype_fares_total` and `passenger_type_completions{rushed, careful, thrill_seeker}`. Nested counters are type-normalised.

Tested:
- a v1 file loads as v2 with every v1 value and setting preserved;
- the migrated file survives a save/load round trip;
- v0 → v2 still works;
- future schemas are still refused.

# LOCALISATION

47 new keys (UI, priorities, destinations, styles, reactions) were added to `en.po`, `si.po` and `ta.po`. English is complete; Sinhala and Tamil keys exist with empty strings, which fall back to English (tested per catalogue). Passenger names are now "Late Executive", "Careful Aunty" and "Thrill Seeker". All new player-facing text goes through `tr()`; F1/F4 debug text is the only exception.

# PERFORMANCE

Apple M2, windowed, game only (`--perf`):

| | v0.01a | v0.02 |
|---|---|---|
| FPS (vsync) | 60 | 60 (p5 59.9) |
| Gameplay CPU (scripts + Jolt) per frame | 1.34 ms mean / 4.0 ms max | **1.74 ms mean / 4.3 ms max** |
| Human AI tick | — | **0.04–0.10 ms mean**, 0.86 ms max windowed |
| Draw calls | 117–150 | 118 |

Pedestrian route search (graph search when a person picks a destination) averages 73 µs, 263 µs at worst. Headless soak runs show rare multi-millisecond wall-clock spikes in the human tick; instrumentation traced these to OS preemption of the uncapped headless loop, not to any code path. Traffic architecture is unchanged and every traffic soak protection still passes.

# ANDROID BASELINE

**BLOCKED — tooling not configured.** There are no Godot export templates (the templates folder is empty), no Android SDK (`~/Library/Android/sdk` is missing), no JDK and no adb. Nothing was installed. This doesn't block v0.02.

# AUTOMATED TEST RESULTS

`tools/run_tests.sh`: **ALL TEST STAGES PASSED**

| Stage | Result |
|---|---|
| Unit | 61 tests, 545 assertions, 0 failures |
| Vehicle handling (v0.01) | PASS, unchanged numbers (0–40 km/h 5.75 s, top 68.0 km/h) |
| Vehicle dynamics (v0.01a) | PASS (swerves, rollover, recovery) |
| Scoring scenarios | 9/9 |
| **Human world + passengers (new)** | **PASS**: path completion; crossing waits, then crosses; reaction to the tuk; people can't score CLOSE CALL/TIGHT GAP; impact event + combo reset + removal; full ride loop ×3 passengers (offer card, accept, boarding states, telemetry, completion + fare, exit, return to pool, offer respawn); drive-by pickup refused at 30 km/h; impact fails an active ride; 0 invalid transitions; pool intact |
| Input smoke | PASS |
| Traffic + humans soak, driving (6 min) | PASS |
| Traffic + humans soak, junction (6 min) | PASS |

How the required test list (items 1–26) maps to these stages:
1. State transitions: unit.
2. Pool doesn't leak: soak, plus the human-world test.
3. Sidewalk path completion: human-world test.
4. Crossing waits when unsafe: human-world test.
5. Crossing proceeds when safe: human-world test.
6. Reaction to the player: human-world test.
7. People can't trigger CLOSE CALL: human-world test.
8. People can't trigger TIGHT GAP: human-world test.
9. Impact event: human-world test.
10. Impact fails the ride: human-world test.
11. Offer lifecycle: human-world test.
12. Low-speed pickup required: human-world test.
13. Boarding transition: human-world test.
14. Ride activation: human-world test.
15. Destination completion: human-world test.
16. Exiting transition: human-world test.
17. Telemetry aggregation: unit test plus human-world test.
18. Satisfaction calculations: unit.
19. Same-drive differentiation: unit.
20. Pedestrian danger never positive: unit (scenario 5 plus fuzz).
21. Fare: unit.
22. Save migration: unit.
23. Human pool bounded: soak.
24. Traffic soak: soak.
25. Vehicle dynamics: dynamics stage.
26. Scoring: scoring stage.

# SOAK TEST

6 simulated minutes each, with traffic, ambient people, crossing people and waiting passengers:

| | Driving | Junction stress |
|---|---|---|
| Human pool violations / max active | 0 / 12 | 0 / 11 |
| Invalid human transitions | 0 | 0 |
| Crossings started / completed / abandoned | 6 / 6 / 0 | 22 / 21 / 3 |
| Longest wait to cross | 10.1 s | 25.1 s (designed give-up) |
| People stranded while walking | none (0.0 s) | none |
| Accidental skill events from people | 0 | 0 |
| Traffic: leaks / teleports / overlaps / visible spawns | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| Junction | 27 grants, longest red wait 21 s | 106 grants (66/40), longest red wait 19 s |
| Node growth | 0 | 0 |

# MANUAL TEST OBSERVATIONS

- **Windowed autopilot runs:** I reviewed screenshots. Paved sidewalks run behind the black/white kerbs on both sides, the zebra crossing is visible ahead, and the shop front with its yellow awning and the bus shelter render. Pedestrians walk along the right-hand sidewalk. The Late Executive's blue beacon is visible 40 m from spawn and the Careful Aunty's magenta beacon is across the road. The figures are small at distance but readable as people.
- **Ride loop:** exercised end to end in the real scene by the scripted test, not by a human at a keyboard. Pickup, boarding, completion, the result card, exit and respawn all work.
- **Not yet done:** a human playtest of feel, and a keyboard-driven full ride (the result card and reaction bubbles haven't been judged by eye).

# KNOWN ISSUES

1. **Route estimates can start with a U-turn.** Routes snap to the nearest lane in either direction, so a destination "behind" the pickup may imply a U-turn.
2. **Human density is uneven.** The east side and the corners of the loop have no sidewalks, so few people appear there (around 3 active while driving those sections). That's intentional for a test track, but uneven.
3. **Passengers are hidden while riding** (seat marker only), as the brief allowed.
4. **Placeholder figures with no animation.** Movement is legless translation plus a bob; people are small at distance.
5. **Traffic yields only to an occupied crossing.** It doesn't stop for people waiting at a zebra; the pedestrians wait for gaps instead.
6. **Pedestrian danger detection uses simple thresholds** (1.2 m at 20 km/h, sidewalk driving, forced hurry). Fairness needs playtesting.
7. **The live "passenger mood" % during a ride** uses elapsed vs full-route target time, so it's optimistic early in a ride.
8. **The autopilot never threatens people,** so the soak shows 0 danger events; danger handling is covered by the deterministic tests.
9. **Sinhala and Tamil strings for v0.02 are empty** (English fallback), and there's still no font for those scripts.
10. **Android baseline blocked;** performance figures are M2 only.
11. **Headless soak wall-clock timings include OS preemption spikes;** use windowed `--perf` figures.

# HUMAN PLAYTEST QUESTIONS

Please drive for 15 minutes or more: watch the sidewalks and crossings, do one ride with each passenger (try the same aggressive driving with all three), and approach a pedestrian dangerously once. Then answer in your own words:

1. Does the road feel more alive with pedestrians?
2. Do pedestrians feel believable enough, or too robotic?
3. Are road crossings readable and fair?
4. Is it obvious which people are available passengers?
5. Does passenger pickup feel smooth?
6. Can you FEEL the difference between the three passengers without studying numbers?
7. Does the Late Executive make you naturally hurry?
8. Does the Careful Aunty actually make you drive differently?
9. Is the Thrill Seeker fun without encouraging risk toward pedestrians?
10. Does the ride-result screen make you want to try another passenger?

Controls: drive WASD/arrows · **E** accept ride · R reset · Esc pause · F1 telemetry (ride state, satisfaction breakdown, humans) · F4 human debug (states, walkways, crossings).

# RECOMMENDED NEXT STEP

**Owner playtest of v0.02, then a focused v0.02a passenger-feel calibration.** The calibration would tune satisfaction weights, reaction frequency, pickup flow and pedestrian density, guided by the 10 answers above. Alongside that, configure the Android toolchain once and capture a mid-range device baseline (FPS, frame time, human/traffic cost).

This step has not been started.
