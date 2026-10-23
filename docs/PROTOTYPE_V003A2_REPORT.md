# Prototype v0.03A2 — World Containment + Crash Consequences + Pedestrian Evasion + HUD Safe Areas

## STATUS

**PARTIAL.** All three owner-feedback items are built and pass the full automated suite: **17/17 stages in one run**. The v0.03A2 debug APK exports.

**No Android device was connected** (`adb devices` was empty at the start and again before export), so on-phone validation and the short device performance check are **PENDING**.

Unchanged:
- vehicle physics (steering, engine, brakes, grip, suspension, centre of mass, rollover);
- camera;
- traffic behaviour;
- passenger satisfaction formulas.

## OWNER FEEDBACK ADDRESSED

| Feedback | Fix |
|---|---|
| HUD too close to / off the left edge | `HudSafeArea` root for every HUD layer (safe rect + 24-unit margin, shared with the touch controls). `NotificationPresenter` for all banners. Width-capped, wrapping cards. 2,793-check layout matrix |
| Tuk can drive off the road forever | Physical district envelope: a ring of grey-box buildings and walls, shopfronts behind the pavements, solid shop and shelter dressing. Hard crashes damage or disable the tuk and reset it to a sensible road position. A VOID failsafe as bug protection. No invisible walls beside roads |
| Pedestrians don't react to a tuk on the pavement | The tuk's path is projected ahead; people EVADE (8–20 km/h) or DIVE aside (above 20 km/h) before contact, choosing escape directions away from traffic lanes and structures. This applies to pedestrians, waiting passengers and arguing drivers |

## SAFE-AREA HUD

Every HUD layer (PrototypeHud, RideHud, NotificationPresenter) builds under `HudSafeArea`:
- The display safe area (cutouts, rounded corners, gesture bars) is converted to logical units and inset by 24.
- The touch controls use the same safe rect, so pause, score, hire card, speed and steering pad share one left edge. A screenshot with a simulated 56-unit left cutout shows all of them aligned at the same x.
- Score and speed positions in touch mode come from the actual pause and steering-pad rects, not fixed offsets.
- All cards wrap words (`AUTOWRAP_WORD_SMART`) with line caps: hire card 7 lines, ride card 8, banners 2, passenger line 2. Long Sinhala or Tamil strings will wrap, not overflow.
- `-- --simulate-safe-area=L,T,R,B` simulates cutouts for screenshots.
- Details are in `docs/hud_safe_area.md`.

## NOTIFICATION LAYOUT

`NotificationPresenter` is now the only way banners appear:
- **Position:** a centre column between the side cards, below the GPS line and combo meter.
- **Slots and priority:** 2 slots, priority NORMAL < HIGH < CRITICAL; a higher priority replaces a lower one, and NORMAL notices are dropped while a CRITICAL one shows.
- **CRITICAL:** pedestrian impact, TUK DISABLED, RESETTING TO ROAD, ride failed.
- **HIGH:** passenger on board, major traffic incident, TUK DAMAGED.
- **Score popups:** suppressed while a CRITICAL banner is up.
- **Other zones:** the result card takes the right column after a ride (the ride card is gone by then); the passenger line sits bottom-centre between the steering pad and the pedals.
- **Retired:** RideHud's centred "unsafe driving" label.

## WORLD SURFACE MODEL

`WorldSurface` (`scripts/world/`) types: ROAD, SIDEWALK, FORECOURT, KERB, BUILDING, WALL, PROP, VOID.

- Every static body is tagged at build time:
  - road edges → KERB (jersey barriers → WALL);
  - ground → FORECOURT;
  - scenery blocks and shopfronts → BUILDING;
  - trees, lamp posts and shelter posts → PROP;
  - tunnels → WALL;
  - the district ring → BUILDING / WALL.
- `classify_point()` gives ROAD / SIDEWALK / FORECOURT / VOID for any position.
- **TukController's only change:** `CollisionEvent` now carries `other_body` plus approach speed and frontality. The controller stays map-agnostic, and the world layer classifies what was hit.

## BUILDING / SHOP COLLISION

- **Already solid:** scenery buildings, trees and lamp posts had box colliders.
- **Newly solid:** the spot dressing (the shopfront block and bus-shelter posts) was drive-through and now collides.
- **Shopfront row:** behind every pavement, buildings now stand 1.2–3.5 m back (a forecourt) instead of 5–10 m.
- **Cost:** all simple boxes, no mesh colliders for decoration.
- **Tested:** wall, boundary building and shopfront each block the tuk and report the right surface.

## PAVEMENT ACCESS

There is no invisible wall: the chamfered 15 cm kerb is real physics. Tested at 25 km/h and a 25° angle, the tuk climbs onto the pavement, scrubbing speed from 27 to 22 km/h. There is no teleport, and the kerb never damages the tuk. Pavement driving immediately raises pedestrian awareness (see evasion).

Pre-existing: the long straight's west side has no raised pavement, only flush ground.

## WORLD CONTAINMENT

`DistrictBoundary` encloses the road network's footprint (+38 m) with a continuous ring:
- grey-box buildings 6–18 m tall, plus compound walls;
- one MultiMesh and one box-collider body.

The open lots between the roads and the ring stay drivable. Tested: full throttle in four directions from the centre for 25 s each never leaves the district, and the failsafe is never needed.

## VEHICLE DAMAGE STATES

`VehicleDamageState` is pure logic; `VehicleDamageManager` applies it in the input layer at physics priority −5, between the input sources and the tuk. Physics are untouched.

Impact = velocity change in km/h. Measured head-on into a building, the tuk stops dead, so the change ≈ the approach speed: 15/22/30/40 km/h in → 15/22/30/40 out; 50 → 48.

| Tier | Impact | Result |
|---|---|---|
| LIGHT | < 16 km/h | dust, keep driving |
| HARD | 16–33 km/h | **DAMAGED**: engine cut 1.2 s, then limp at 60% throttle for 8 s, with smoke. A tested 25 km/h hit gave a 29.5 km/h impact |
| DISABLING | ≥ 33 km/h, or a HARD hit while damaged | **DISABLED**: engine off. A tested 45 km/h hit gave a 45.8 km/h impact |

- Only solid structures cause damage; kerbs, ground and traffic never do (traffic stays with the v0.03A1 incident system).
- Effects are pooled CPU particles: dust burst, sparks on hard hits, lingering smoke. No fire, no explosions.
- Hooks: `world_impact`, `vehicle_damage_changed`.

## CRASH RECOVERY

Sequence: DISABLED → the tuk comes to rest → "TUK DISABLED" + "RESETTING TO ROAD" banners → reset after about 2 s (tested: 2.0 s) → HEALTHY.

`WorldRecoveryManager` now owns the reset pose for every reset (R, tipped auto-recover, disabled, failsafe):
- **Where:** the nearest legal lane, 10 m *behind* the crash point if clear (then −18, −4, −26, +6, +14 m), upright and facing the lane direction.
- **Clear of:** traffic (9 m), people (5 m) and junction boxes.
- **Never** the world origin.
- **After a reset:** the camera snaps back (tested 6.8 m from the tuk).
- **No reset loops:** a 1.5 s grace after any reset (tested: exactly one reset per disabling crash).

**Failsafe**, bug protection only: below y −4, or more than 3 m outside the district, triggers recovery. Tested by teleporting outside and below the world; it never triggers during driving.

## RIDE FAILURE FROM DISABLING CRASH

An active ride fails when the tuk becomes DISABLED: new `RideResult.FailReason.VEHICLE_DISABLED`, no fare, the passenger's profile-specific collision line, and the result card says "The tuk was disabled in a crash". GPS clears.

HARD crashes keep the ride; the existing collision penalties and reactions apply.

## IMPACT PROPS

`ImpactPropManager`:
- **What:** 16 pieces of light street clutter on the pavement back edges (signs, box stacks, cones, stall boards, shop displays).
- **Deliberately not physics bodies:** they never stop the tuk.
- **Hit detection:** a cheap footprint test, only near the player.
- **Reaction:** below 6 km/h a prop wobbles; above, it's knocked with a ballistic tumble, and box stacks and displays shed pooled debris (≤ 18 pieces).
- **Afterwards:** the prop settles, shrinks away and respawns out of view after 25 s.
- **Hook:** `prop_knocked`.
- Building walls are not destructible.
- **Tested:** knocked at 25 km/h without stopping the tuk; settled and cleared, with debris back to 0.

## PEDESTRIAN EMERGENCY EVASION

`HumanManager` checks each nearby person against the tuk's projected straight-line path: miss distance at the closest approach versus the tuk's half-width + 1.3 m, looking 1.4 s ahead on the road and **2.0 s** when the tuk is on a pavement. This is cheap: no pathfinding, and it runs in the existing per-tick safety pass.

| Tuk speed | Reaction |
|---|---|
| < 8 km/h | mild step back (v0.02) |
| 8–20 km/h | **EVADE**: run about 3 m at 16 km/h |
| > 20 km/h, or < 0.6 s to the closest approach | **DIVE**: about 4.2 m at 26 km/h, with a hop and lean (placeholder) |

Escape-target scoring:
- stay on your own side of the path;
- never into a traffic lane (scored −8);
- never through a building, wall or post (physics ray, scored −30);
- never off the district;
- prefer staying near the pedestrian network.

After a 1.2–2 s pause, each role resumes its own behaviour (new `EVADING` state, valid transitions only). People crossing the road keep the v0.02 HURRY, so nobody is sent into a lane.

**Pavement-swerve scenario (tested):** the tuk mounts the pavement at 35 km/h with three people ahead.
- All three recognised it early, 1.22–1.95 s before the closest approach.
- All three dove aside; nobody was hit, and nobody escaped into a traffic lane.
- Everyone was back on the network within 4 s.
- No CLOSE CALL or TIGHT GAP points.

At 15 km/h, a standing person steps 2.4 m sideways (an EVADE, not a dive).

**Note on tests:** three v0.02 rule tests deliberately force an unavoidable contact or near pass, to check that impacts still fail rides and never score. Those steps turn evasion off with a config switch (`PedestrianConfig.emergency_evasion`). With evasion on, people now escape them, which is the intended new behaviour.

## WAITING PASSENGER SAFETY

A waiting hire passenger driven at at 30 km/h jumps aside instead of freezing under the tuk (closest approach 4.9 m), and is not hit. The ride is not accepted. They walk back to their pickup spot (0.2 m away) and wait again. Boarding only starts once they're settled.

## DRIVER SAFETY

An arguing traffic driver (from a v0.03A1 altercation) is a pedestrian too. When the tuk accelerates at them at 20 km/h, they evade (closest 4.4 m) and aren't hit. They then walk back to their car, the altercation ends and the incident resolves. Pedestrian-safety consequences are unchanged.

## GPS AFTER OFF-ROAD / RESET

- **Off-road:** the GPS keeps the legal RoadNetwork route; the v0.03A1 off-route rerouting still applies (more than 9 m for 1.2 s, rate-limited), and never routes through buildings.
- **After any reset:** the existing `player_reset` hook recalculates the route.
- **A disabling crash during a ride:** the ride fails and the route clears (tested).
- **A reset with no ride:** no route (tested).
- **Off-road soak:** zero GPS-corruption ticks.

## AUTOMATED TESTS

`tools/run_tests.sh`: **ALL 17 STAGES PASS** (one full run).

| Stage | Result |
|---|---|
| Unit | **94 tests / 944 assertions** (new: damage tiers and state machine, surface tags, safe-area insets) |
| Vehicle handling / dynamics / scoring | PASS (unchanged) |
| Human world + passengers | PASS |
| Input smoke | PASS |
| Mobile touch ×2 | PASS |
| GPS + hire UX + incidents | PASS |
| **HUD safe-area matrix** (new) | PASS — 5 aspect ratios × 6 safe areas (full, left/right cutout, both, gesture bar, asymmetric), long text: inside the safe rect + margin, clear of every touch control, no card overlaps, result card clear of banners, left column aligned (**2,793 checks**) |
| **World containment + damage + recovery + props** (new) | PASS |
| **Pavement safety / evasion** (new) | PASS |
| Soaks: driving 6 min / incidents 4 min / **off-road 4 min** (new) / junction 6 min | PASS (seeded) |

Screenshots (windowed):
- `world_overview_screens.tscn`: top-down district ring, the pavement and shopfront row, a disabling crash with banners;
- `gps_incident_screens.tscn -- --simulate-safe-area=56,0,0,0`.

## SOAK RESULTS

**Off-road soak** (`--offroad`, 240 s): 19 episodes rotating 5 pavement charges at people, 5 prop strikes, 5 building crashes and 4 hard wall hits, with the autopilot driving in between.

- **People:** 11 dives, **0 pedestrian impacts**.
- **Props:** 4 knocked, 3 respawned; 0 debris at the end.
- **Damage:** 5 disabling crashes → **5 resets** (one each). Longest DISABLED period 2.0 s.
- **Recovery:** 5 recoveries, 0 failsafe, no endless reset, never left disabled.
- **GPS:** 0 corruption ticks.
- **No leaks:** no human pool leak, no node growth, no invalid transitions.
- **Traffic:** junction and signal checks pass.

The other soaks are unchanged and pass. They are now seeded for people, offers and incidents, as traffic already was.

## ANDROID RESULTS

**PENDING — no adb device connected.**

| APK | |
|---|---|
| Path | `builds/android/tuktukcolombo-debug.apk` (git-ignored) |
| Version | 0.0.3a2 (code 5); installs over v0.03A1 |
| Size | 80 MB (84 309 145 bytes) |
| SHA-256 | `2dce0a99e10ba9e5f2c1ebeb161ec48153d095898db71ae3c05f05d45c6d1bad` |
| Manifest | `com.chavensl.tuktukcolombo`, minSdk 28, targetSdk 35, arm64-v8a, debug-signed |

Owner steps:

```bash
tools/install_android_debug.sh
tools/android_perf_test.sh 120
```

Then check:
- **HUD:** left and right edges, hire card, warnings.
- **Off-road:** mount the pavement; drive at people; hit a building; watch the reset.
- **GPS:** follow it after leaving the road and after a reset.
- **Incidents:** confirm the v0.03A1 traffic altercations still work.

## PERFORMANCE

Windowed 60 s soak (`--perf`, Apple M2), same machine, same session:

| Build | FPS mean / p5 | gameplay CPU (physics) mean | human AI mean | draw calls |
|---|---|---|---|---|
| v0.03A1 HEAD | 60.1 / 60.0 | 2.05 ms (yesterday 2.18–2.68 ms) | 0.153 ms | 188 |
| **v0.03A2** | 60.1 / 59.4, 60.1 / 60.0 | 2.33, 2.13 ms | 0.155–0.171 ms | 189–217 |

A second v0.03A1 run is excluded because the window lost vsync (111 FPS).

**No measurable regression.** New per-tick work:
- the evasion corridor test inside the existing human loop;
- one footprint test per nearby prop;
- a 0.25 s recovery check.

The ring adds one draw call and props add up to 16. Particles are pooled and the colliders are boxes.

The device check (target about 60 FPS) is pending.

## KNOWN ISSUES

- **Not yet on a phone:** HUD, off-road behaviour and crashes.
- **Long straight:** the west side has no raised pavement (flush ground). That's existing geometry, untouched.
- **Open lots:** the area inside the loop is large and empty, contained but bland. That's for the art pass.
- **Evasion placeholders:** evade and dive are a hop and lean with no animation. A dive on a crowded pavement can overlap another person (people have no mutual avoidance).
- **Props:** not physics objects (by design), and only 16 of them; debris is simple cubes.
- **No permanent damage:** no visible deformation; damage is a state only.
- **HARD-crash smoke** attaches behind the tuk; with the low camera it can be hard to see.
- **Failsafe** recovers to the nearest lane (by design), which may be far from where the tuk was.
- **Long cards** are capped by line count, so an extremely long translated hire card can lose its last line (priority). Needs a native Sinhala and Tamil review later.

## OWNER PLAYTEST QUESTIONS

1. Are all messages/cards now comfortably inside the phone screen?
2. Does the HUD feel consistently aligned?
3. Can you still mount the pavement naturally?
4. When you drive toward pedestrians on the pavement, do they react early and convincingly?
5. Does their evasive movement feel urgent enough?
6. Does crashing into a building/shop now feel like a real crash rather than driving through empty world?
7. Is the damage/reset consequence clear without being frustrating?
8. Does the road reset place you somewhere sensible?
9. Does GPS recover correctly afterwards?
10. Can you still find any location where you can drive endlessly outside the playable world?
