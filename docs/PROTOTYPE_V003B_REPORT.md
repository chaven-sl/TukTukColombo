# Prototype v0.03B — Fort–Pettah Gateway

## STATUS

**PARTIAL.**
- The first production-quality Colombo art and audio vertical slice is built and is now the game's start scene.
- The full automated suite passes: **18/18 stages in one run**, including the new Fort–Pettah slice test and a 6-minute Fort–Pettah soak.
- All four screenshot gates render the dressed district, not greybox.
- The debug APK was exported, installed and measured on the reference phone with `tools/android_perf_test.sh 180`.

**Why PARTIAL:**
- The art, audio, tests, soak and screenshot gates are complete.
- On the reference phone, the 5th-percentile frame rate meets its target (54.0 FPS, target ≥ 48).
- Memory (123 MB) and draw calls (103) are well inside budget.
- The **average frame rate is 53.6 FPS, just under the 55–60 target** (v0.03A2 managed 58.6).
- The final measurement was taken while the phone reported a throttled thermal state (Thermal Status 2) after about 3 hours of continuous testing.
- The owner should confirm the frame rate on a cool phone.

Locked systems are unchanged:
- vehicle physics, engine, steering, brakes, grip, suspension, centre of mass and rollover;
- touch steering;
- near-miss, combo and satisfaction formulas;
- GPS and traffic architecture;
- human architecture;
- damage and recovery.

The handling, dynamics, scoring, GPS, incident, evasion and containment suites pass unchanged.

One pre-existing physics-side **defect** was fixed (not a tuning change):
- **Before:** the road edge trimesh was one-sided under Jolt, so left-hand kerbs and pavements had no collision from above.
- **After:** `backface_collision = true` (`scripts/road/road_segment.gd`) makes both sides of the kerb and pavement solid, as the v0.03A2 design intended.
- The handling suites are unaffected.

## DISTRICT OVERVIEW

`res://scenes/districts/fort_pettah/fort_pettah_slice.tscn`:
- It inherits `prototype_main.tscn`, so every gameplay system is the same.
- It swaps in a new road network (`fort_pettah_track.tscn`) and adds the `DistrictArt` dresser and `DistrictAudio`.
- `bootstrap.gd` now boots into it.
- The greybox test track stays for regression tests.

The route is a closed loop of about **940 m** (15 segments, 70 lanes, 1 signalised junction), plus two side arms that end in gateway buildings:

| Beat | Segment(s) | Character |
|---|---|---|
| A. Fort Station frontage | StationFrontage 180 m | white arcaded station, forecourt, tuk rank, wide pavements, 2 zebra crossings |
| B. Olcott transport corridor | OlcottCorridor 110 m (+ tapers) | median, wide shoulders, bus bays and shelters, railings, the most bus traffic |
| C. Pettah market approach | MarketApproach 122 m, MarketLower 55 m | narrow lanes (2.9 m), densest people (×2.0), market spill, buses rare (×0.15) |
| D. Pettah junction | JunctionApproach + Junction | signalised; overhead direction gantry |
| E. Service connector | ServiceConnector 68 m | warehouses, walls, loading clutter |

**Implied city:**
- There are 11 side streets.
- Each ends in a believable stub with a façade, wall or parked vehicle; there are no invisible walls and no voids.
- Two traffic arms disappear under gateway buildings with signs (PETTAH MARKET ARCADE, CENTRAL BUS STAND).
- A skyline of background blocks rings the district.

**Dressing:**
- 204 buildings, 149 prop groups, 192 signs, 18 parked vehicles.
- 125 batched art meshes, about 140k triangles.
- 388 box collision proxies.

## FORT–PETTAH REFERENCE

See `docs/fort_pettah_reference.md`. Text notes only, no photographs in the repository.
- The geography is compressed and fictionalised.
- The shop names are invented.

## VISUAL ART DIRECTION

See `docs/art_bible.md`.
- **Style:** stylised Colombo realism, about 65/35 real/stylised.
- **Palette:** controlled and sun-faded (`ArtPalette`).
- **Saturation:** confined to awnings, umbrellas, signs and clothing.
- **Readability:** readability first.

**Pipeline:**
- Blender is not installed and was not installed.
- All art is reproducible procedural GDScript with fixed seeds:
  - `ArtMesh` (primitives, lofts, arc shells, wires);
  - `BuildingKit`, `StreetKit` and `DistrictChunks` for batching;
  - `SignAtlas`;
  - `TrafficArt`, `CharacterBuilder`/`CharacterRig` and `HeroTukVisual`.

## HERO TUK

`Visual/HeroArt` (`HeroTukVisual`) replaces the placeholder boxes:
- **Body:** a lofted nose cowl, a rounded rear tub, an arc canopy, a rolled rear canvas (so the passenger is visible) and a low backrest.
- **Paint:** deep teal and turquoise with yellow accents and chrome.
- **Design:** original, not a manufacturer copy, with no badges.

Physics hooks:
- **Wheels:** the hero wheels sit under the physics wheel nodes, so steering, spin and suspension come from the existing rig.
- **Handlebar:** copies the steering angle (−35.5° at full lock in the test).
- **Brake lights:** emission 2.6 when braking.
- **Headlight:** material hook.
- **Driver:** a stylised character in DRIVE pose.

About 1.5k triangles, against a 25–30k budget. There are no colliders in the art, and mass and centre of mass are unchanged (430 kg; checked by `fort_pettah_test`).

## TRAFFIC VEHICLES

`TrafficArt` builds one cached mesh per class and paint (no logos, no real liveries):

| Class | Variants | Triangles (budget) |
|---|---|---|
| Bus | red public with cream band; private blue/white, multicolour, with roof rack and stripe (5) | about 780 (≤ 10k) |
| Car | 6 paints | about 544 (≤ 8k) |
| Van (new class, pool 3) | 5 paints | about 492 (≤ 8k) |
| Tuk | teal, black, green, red, blue, cream, with driver silhouette (6) | about 574 (≤ 6k) |
| Motorcycle with rider | 5 | about 440 (≤ 4k) |

Changes to the traffic set-up:
- The traffic pool is still 24; the car pool went from 12 to 9 to make room for vans.
- Zone mix uses `bus_spawn_scale`, so buses are rare in the market lanes.

## HUMAN PRESENTATION

`CharacterRig` replaces the capsules:
- **Build:** rigid-skinned 11-bone characters, 500–650 triangles each, with 12 outfit and skin combinations (shirts and trousers, sarongs, saris and long skirts, school whites, office wear, vendor caps).
- **Animation:** procedural poses for idle, walk, hurry, run, EVADE, DIVE, wait, seated, board, argue and drive.
- **Animation LOD:** animation stops beyond 55 m.
- **Logic:** the HumanAgent logic is unchanged; the presentation reads its state.

Density by zone:
- `pedestrian_density` weights ambient spawns: station 1.3, market 2.0.

## PASSENGER IN-TUK PRESENTATION

- **Boarding:** the passenger walks to the tuk, slides in, and their presentation attaches to `SeatMarker`.
- **Riding:** they stay visible and seated for the whole ride.
- **Reacting:** each passenger reaction plays a seated arm gesture and a vocal sound.
- **Exit and cancel:** they detach on exit or cancel.

The gameplay position and state machine are unchanged. Tested in `human_world_test`: visible, attached to SeatMarker, rig SEATED, detached on exit.

## FORT STATION

- **Building:** a white colonial arcaded frontage, end pavilions, a central pavilion with pediment, and a canopy.
- **Signage:** the trilingual sign COLOMBO FORT / කොළඹ කොටුව / கொழும்பு கோட்டை, plus TICKETS signs.
- **Platform depth:** carriages and a platform glimpsed through the arcade.
- **Forecourt:** a plaza with a tuk rank (3 parked tuks) and a vendor stall.
- **Sound:** rail clatter and periodic train horns come from behind the station.

## PETTAH MARKET

- **Streets:** narrow lanes and dense shop-houses with roller shutters and trilingual boards.
- **Pavement spill:** umbrellas, stalls, sacks, crates, handcarts, hanging goods and stools.
- **Overhead:** wires.
- **Life:** the highest pedestrian density, a market ambience bed and vendor calls.

## STREET PROPS

`StreetKit` provides:
- umbrellas, stalls, handcarts, sacks, boxes, stools and hanging goods;
- bollards, utility poles with sagging wire bundles, transformers and street lamps;
- railings, bus shelters, barriers and a construction corner;
- shade trees and palms (used sparingly);
- drains and covers, asphalt patches, bus-bay paint and zebra crossings.

Construction rules:
- Everything is merged into per-cell meshes.
- Collision is simple boxes.
- Nothing sits on a legal lane: `fort_pettah_test` sampled 945 lane boxes with 0 blocked.

## SIGNAGE / LOCALISATION

Fonts:
- Noto Sans, Noto Sans Sinhala and Noto Sans Tamil, downloaded only from the official `google/fonts` GitHub repository.
- SIL OFL 1.1, with the licences in `assets/fonts/*/OFL.txt`.
- `UiFonts` chains the Sinhala and Tamil fallbacks, so the HUD and signs render all three scripts.

Signs:
- All signs share one 1024² `SignAtlas` (about 90 % used), baked once at load.
- There are 16 fictional shop names in English, Sinhala and Tamil.

Locale keys:
- New place keys `PLACE_*` were added to en, si and ta.
- **The si and ta strings still need native-speaker review.**

## LIGHTING

`DistrictLighting` sets hot tropical late morning (about 10:45):
- **Sun:** high and slightly warm, energy 1.75, with crisp shadows.
- **Sky:** procedural pale blue.
- **Ambient:** a flat warm-neutral colour; no sky reflections (see Android results).
- **Haze:** light humid fog.
- **Grading:** filmic, saturation 1.18, contrast 1.08.
- **Not used:** bloom, day/night.

The greybox scene keeps its old lighting.

## MATERIALS / TEXTURES

- **Materials:** 8 shared art materials plus 3 road materials (Colombo style: neutral asphalt with triplanar grain, white kerbs, faded markings).
- **Textures:** vertex colours instead of texture atlases; one 1024² sign atlas; one 256² noise texture. No 4K textures.
- **Details:** `docs/fort_pettah_art_budget.md`.

## AUDIO

All sounds are **original and procedural**:
- `tools/audiogen/generate_audio.py` (numpy, fixed seed) writes 23 mono 22.05 kHz WAVs totalling 2.3 MB.
- No downloads, no recordings, no music.

Mixing:
- **Buses** (`default_bus_layout.tres`): Vehicle 0 dB, Traffic −3, Ambience −7, UI −2, all into Master.
- **`DistrictAudio`** is presentation only: it reads telemetry and EventBus hooks.

| Layer | Content |
|---|---|
| Player tuk | idle and load engine loops crossfaded and pitched by km/h and throttle, a dip on throttle lift, a tyre loop, the horn |
| Collisions | thud, scrape or crash by severity; a major crash ducks ambience for about 1.6 s |
| Traffic (4 pooled 3D voices + 1 rumble) | bus rumble follows the nearest bus within 35 m; motorcycle passes (cooldown per bike); occasional class-specific horns weighted by zone; incident horns (ANGRY/REPEATED); driver shouts |
| Ambience | city, crowd and market beds crossfaded by zone; rail clatter and train horn behind the station; vendor calls in the market and station zones |
| Passenger | a reaction sound plus the seated gesture |

Priority comes from fixed pools, a 70 m range cut-off and cooldowns:
1. player engine and collisions;
2. passenger;
3. incidents;
4. nearby traffic;
5. ambience.

Voice placeholders are wordless formant buzz, ready to be replaced with real VO later.

## UI

A restrained pass:
- The Noto typography is the theme default for all Controls.
- Ride and notification cards have rounded corners (radius 10) and a teal accent line.
- The pickup beacon is now a translucent pillar and ground ring.

GPS ribbon presentation:
- softer cyan;
- soft-edged chevrons;
- translucent;
- fades in 2–8 m ahead of the tuk, so it never sits on the bonnet.

The layout and safe-area logic are unchanged; the 2,793-check safe-area matrix passes.

## PERFORMANCE BUDGET

See `docs/fort_pettah_art_budget.md`:
- **LOD:** arch 170 m, detail 55 m, signs about 100 m, skyline 700 m without shadows.
- **Shadows:** the medium-tier shadow distance went from 60 to 28 m; clutter, signs and wires cast no shadows.
- **Degradation order:** clutter, shadows, props, materials, far pedestrians, background.

## AUTOMATED TESTS

`tools/run_tests.sh` passed all **18/18 stages** (Apple M2, 2026-10-23):
- **Unit tests:** 94 tests, 946 assertions.
- **Prior suites, unchanged and passing:** vehicle handling, dynamics (rollover), scoring (pedestrian danger never scores), human world, input smoke, mobile touch (steering unchanged), GPS + hire + incidents, HUD safe-area matrix (2,793 checks), world containment + damage + recovery, and pavement safety (evasion).
- **`human_world_test` updated:** the passenger is visible and attached to SeatMarker while seated (rig SEATED), and detaches on exit.
- **New `fort_pettah_test` (52 checks, all pass):**
  - district length and dressing;
  - place names;
  - the visual tuk exists, is within its triangle budget, has three hero wheels, steers, and the handlebar follows;
  - no collider in the art; mass and centre of mass unchanged;
  - traffic paint variants assigned, with per-class triangle budgets;
  - the human presentation swaps;
  - collision proxies are separate from visuals and correctly tagged;
  - **no collider on any legal lane (945 samples), the player spawn or any pedestrian spot**;
  - station → market, market → station and bus stand → station routes are valid;
  - the GPS ribbon sits 0–0.2 m above the new road (43/43 samples);
  - the audio buses exist, and the horn, collision and engine-load hooks respond.
- **A real defect the new test found and fixed:** the Pettah Junction drop-off spot was inside a shop-house proxy. It was moved onto the pavement.

## SOAK RESULTS

New stage: `traffic_soak_test -- --duration=360 --fort-pettah`, 6 simulated minutes on the slice with hires, incidents and off-road episodes interleaved. Result: **PASS.**

| | |
|---|---|
| Hires | 7 attempted, 7 accepted and boarded, **6 completed, 1 failed** (an off-road crash during the ride), 0 aborted; every ride had a valid GPS plan |
| Incidents | 34 injected; 22 altercations, 14 driver exits, ≤ 1 driver out, ≤ 1 vehicle held (max 7.3 s), 0 timeouts, no driver leak |
| Off-road | 19 episodes: 5 pavement charges (15 dives), 5 prop strikes (4 knocked and respawning), 5 shop-house crashes (5 disabled → recovered, max disabled 2.0 s), 4 wall hits; 0 failsafe; GPS never corrupted |
| Traffic | pool 24 never leaked, max active 14, no visible spawns, no teleports, no self-overlap, junction serving both axes, signal waits < 45 s |
| People | max 13 active, no pool leak, no invalid transitions, no crossing deadlock, AI 0.09 ms mean |
| Leaks | node count −17 over the run (no growth) |

Two rate thresholds are scaled for this mode only, because hires share the clock:
- off-road episodes: ≥ duration/20 (greybox: duration/14);
- incidents: ≥ duration/14 (greybox: duration/7), because pickups and drop-offs often have no traffic within 35 m.

The 6-minute greybox drive soak, the junction soak, the incidents soak and the off-road soak still pass with their original thresholds.

## SCREENSHOT GATES

These are windowed at 1280×720 (`fort_pettah_screens.tscn -- --gates`) and saved to `user://test_results/screens/` (macOS: `~/Library/Application Support/Godot/app_userdata/TukTuk Colombo/test_results/screens/`):

| Gate | File | Shows | Verdict |
|---|---|---|---|
| A. Hero road | `v003b_gate_a_hero_road.png` | hero tuk in the kerb lane of the bus corridor; red public bus, a green tuk, a motorcycle with rider; people on the pavement; shop-houses with boards, wires, railings | **pass**: reads as a Colombo bus road, not greybox |
| B. Market chaos | `v003b_gate_b_market_chaos.png` | narrow market lane; pedestrians on both pavements; awnings, umbrellas, stalls and sacks; tuks, a van and a bike ahead; wire bundles | **pass, weakest gate**: busy, but not yet the crush of real Pettah (see Known issues) |
| C. Active hire | `v003b_gate_c_active_hire.png` | seated passenger visible in the tuk, GPS ribbon ahead, ride HUD (destination, remaining, mood), "Passenger on board" banner, station sign | **pass** |
| D. Incident | `v003b_gate_d_incident.png` | car stopped ahead, angry driver out beside the tuk with a shout bubble, passenger still seated, station sign and tuk rank behind | **pass**; framed from a road-side camera because the chase camera hides a driver in front of the tuk (known v0.03A1 issue) |

Gates A, B and D place traffic and people around the tuk for composition. The art, lighting and HUD are the real game.

## ANDROID RESULTS

| APK | |
|---|---|
| Path | `builds/android/tuktukcolombo-debug.apk` (git-ignored) |
| Version | 0.0.3b (code 6); installs over v0.03A2 |
| Manifest | `com.chavensl.tuktukcolombo`, minSdk 28, targetSdk 35, arm64-v8a, debug-signed |
| Device | A142, Mali-G610 MC4, Android 16, 2412×1084 (internal 1602×720, medium tier) |

The APK was exported, installed and launched, and boots into the Fort–Pettah slice.

**Cold start:** about 35 s, mostly engine and pipeline start-up; the district build takes about 0.5 s.

**How the regression was found** (device runs of 120–180 s with the deterministic autopilot):

| Run | FPS avg | FPS p5 | Notes |
|---|---|---|---|
| v0.03B first build | 53.7 | 29.8 | about 11 % of frames missed vsync (33 ms) |
| shadow distance 40 → 28 m, clutter range 80 → 55 m | 53.8 | 31.6 | no effect |
| without triplanar road detail, fog or colour grading | 53.4 | 29.8 | no effect (reverted) |
| without the district art at all | 54.0 | 29.8 | no effect |
| without audio, without UI theme, without lighting, rigs frozen (each alone or together) | 53.8–54.6 | 29.8–33.0 | no effect |
| **v0.03A2 control build, same day** | 58.7 | 58.6 | the device was fine |
| current code on the greybox scene | 57.8 | 57.1 | the shared changes (hero tuk, rigs, traffic art) are fine |
| bare Fort–Pettah track (no art, lighting, audio or theme) | 59.2 | 60.0 | the track and systems are fine |
| **fix: flat ambient + no sky reflections** | **53.6** | **54.0** | vsync misses gone |

**Root cause:** GPU time.
- Sampling the procedural sky's radiance for ambient light and reflections on every lit pixel, added to the district art, pushed frames just past the 16.6 ms budget.
- Removing any single feature didn't get back under the budget, so single-feature tests showed no change.
- The sky remains as the visible background. The visual difference is negligible (gates re-rendered).

**Measurement fix:**
- `DevicePerfTest` now records after a 3 s warm-up. The first-frame sign-atlas bake and pipeline compile used to stall about 5.8 s inside the measurement window and skew the average.
- The new field `seconds_below_50fps` separates sustained slow stretches from isolated misses.
- v0.03A2 figures include their (shorter) warm-up.

**Device caveats:**
- The phone sat on USB power throughout.
- Late runs were thermally throttled. One run was capped at 30 FPS by the system and is excluded.

## PERFORMANCE COMPARISON VS v0.03A2

Reference phone (Mali-G610 MC4, medium tier, 1602×720), deterministic autopilot:

| Metric | v0.03A2 (baseline, 120 s) | v0.03B (180 s) | Target | Result |
|---|---|---|---|---|
| FPS average | 58.6 | **53.6** | 55–60 | **miss (−1.4)** |
| FPS 5th percentile | 54.5 | **54.0** | ≥ 48 | pass |
| Slowest 1 s | 47.4 | 49.1 | — | better |
| Frame time p95 | 18.4 ms | 18.5 ms | — | same |
| Draw calls | 176.8 | **103.4** | < 280 | pass (−42 %, thanks to batching) |
| Memory (static peak) | 108.5 MB | **123.4 MB** | < 220 MB | pass (+15 MB) |
| Active traffic / people | 11–14 / 3–11 | 6–14 / 9–12 | — | denser streets |

**Next levers** (in the brief's degradation order, not yet applied because each costs visible quality):
1. Thin the market-spill props.
2. Turn shadows off for the Arch layer beyond 20 m.
3. Shorten the far-pedestrian animation range from 55 to 35 m.
4. Shorten the skyline range from 700 to 400 m.

The occasional long frames (up to about 80 ms) that pull the average below the 5th-percentile figure should be profiled on a cool phone first.

## KNOWN ISSUES

**Art:**
- First-pass procedural geometry with vertex colour; no hand-modelled or textured assets yet.
- Shop shutters and back walls read a little flat.
- Shop boards are small at chase-camera distance.

**Market density:**
- Gate B is busy but not chaotic enough.
- More people would mean raising the ambient human budget, which the brief locks; it is a later density/LOD-people task (roadmap v0.04).

**Characters:**
- Rigid skinning shows no cloth deformation.
- Animation is procedural poses only; the dive is a lean and hop.

**Chase camera:**
- It can hide a driver standing in front of the tuk (unchanged from v0.03A1).

**Audio:**
- All sounds are synthesised placeholders: the engine is believable, but voices are wordless buzz and the horns are clean synth tones.
- Real Sri Lankan recordings and VO are needed for production.
- Volume balance has not been judged on a phone speaker.

**Localisation and fonts:**
- Sinhala and Tamil strings and signs need native-speaker review.
- Some combined lines on the portal signs use a smaller font size.

**Station:**
- It is a stylised interpretation, not an architectural survey; the clock tower is simplified.

**Device frame rate:**
- 53.6 FPS average, against a 55 target; see the performance comparison.

**Start-up:**
- Cold start on the phone is about 35 s, mostly engine/shader start-up. The district build itself is about 0.5 s.

**Coverage:**
- The perf monitor does not count visible building modules or props separately; draw calls and memory cover them.

## OWNER PLAYTEST QUESTIONS

1. At first glance, does the Fort–Pettah slice feel like Colombo, specifically Fort and Pettah, rather than a generic city?
2. Is the station frontage recognisable and impressive enough as the opening view?
3. Does the hero tuk look like a tuk you would want to drive, and does the teal and yellow design work?
4. Is the seated passenger clearly visible and does it add to the ride?
5. Do the buses, tuks, motorcycles and vans read correctly at a glance while driving?
6. Does the market approach feel busy enough, and what is missing (people, stalls, noise)?
7. Are the road, kerbs, traffic and GPS ribbon still easy to read at speed on your phone screen?
8. Does the late-morning light feel hot and tropical, or too bright or too flat?
9. Does the engine sound respond believably to throttle and speed, and is the horn, ambience and incident mix balanced on the phone speaker?
10. Did the frame rate feel smooth throughout, especially in the market and at the station?

## RECOMMENDED NEXT STEP

**STOP here for owner visual and playtest approval.** Install the v0.03B debug APK, drive the full loop with and without a hire, and answer the 10 questions.

Depending on the answers, the follow-ups are:
- market density and LOD people;
- a sign readability pass;
- replacing the synthesised audio with real recordings and VO;
- art-detail upgrades within the budget headroom.

Economy, garage, progression, map expansion, monetisation and v0.04 are **not** started.
