# Prototype v0.03B1 — Performance Recovery + Visual Quality

## STATUS

**PARTIAL.**

**Phase A (performance): PASS.**
- The root cause was found by device A/B, not guessed.
- Android frame rate is fully recovered *with* the heavier v0.03B1 art.
- Final 180 s device result: **58.7 FPS average, 58.4 FPS p5, 51.0 FPS slowest second, 0 seconds below 50 FPS.**

**Phase B (art): substantially done; one gate still short.**
- **Done:** hero tuk v2, traffic art v2, Fort Station v2, humans v2, material and lighting pass, compact HUD, softer GPS ribbon.
- **Short:** Gate B (market chaos) is much denser but does not yet feel like *squeezing through* Pettah. The market carriageway is four lanes wide, and that road geometry is locked gameplay. See Known issues.

All automated suites pass; see Automated tests.

Locked systems are unchanged:
- vehicle physics, steering, traffic logic;
- HumanAgent logic, GPS routing;
- damage and recovery;
- satisfaction and scoring.

## PERFORMANCE ROOT CAUSE

**GPU-bound at native resolution.** It was not CPU, not a 30 FPS cap, and no single v0.03B feature.

- **3D render size:** the medium tier rendered 3D at the panel's full **2412×1084** (`render_3d=2412x1084` in the new runtime log).
  - The v0.03B report's "1602×720" was the logical UI viewport, not the 3D render size. That was a reporting error.
- **The budget:** v0.03B's per-pixel cost (district materials, lighting and sky, more surfaces on screen) put the GPU at **14.4 ms mean / 15.4 ms p95** of the 16.7 ms budget.
- **The symptom:** normal frame-to-frame variance pushed about 11 % of frames over budget, and vsync turned each one into a 33 ms frame. That is why p5 sat at about 30 FPS while the per-second average stayed at about 53 FPS.
- **Not geometry:** hiding all district art cut primitives from 73k to 25k but saved only 0.3 ms of GPU time.
- **Not CPU:** every instrumented game system *together* costs about 2.8 ms per frame. Character presentation is 0.19–0.23 ms; audio is 0.13 ms.

**About the "29.9 FPS / CPU process 25.62 ms" figures quoted in the brief:**
- **29.9 FPS:** that was a run I had already excluded. The phone was thermally throttled and the system capped it at 30 FPS for the whole run (0 budget changes, 119 of 120 s below 50).
- **25.62 ms:** that is Godot's `TIME_PROCESS` monitor. On this setup it includes the vsync wait (it read 40 ms inside a 17 ms frame on desktop), so it is not CPU work. The new section profiler and the RenderingServer CPU/GPU timings replace it.

**About the "shadow distance 60 m" discrepancy in the brief:**
- The repository (`resources/platform/graphics_medium.tres`) held **28 m** at the v0.03B commit (09f58e6).
- The scene loads that file (`prototype_main.tscn` → `graphics_profiles`).
- The device log confirms it at runtime: `profile_shadow_distance=28 … shadow_distance=28`.
- A new unit test (`test_graphics_runtime.gd`) now fails if `docs/fort_pettah_art_budget.md` ever quotes a different value from the `.tres`.

## ANDROID RUNTIME SETTINGS

From the new `[GraphicsRuntime]` startup line on the reference phone (final build):

```
tier=MEDIUM profile_shadow_distance=28 max_fps=60 render_scale=0.67 scaling_mode=FSR shadow_distance=28
sun_shadows=true fog=true sky=true ambient=COLOR reflections=DISABLED viewport=1602x720 render_3d=1616x726
window=2412x1084 screen_refresh_hz=60.0 vsync=ENABLED renderer=mobile physics_ticks=60 process_mode=0 effective_cap=60
```

- The phone runs the MEDIUM tier, 60 FPS cap, vsync on, 60 Hz physics.
- The panel reported 60 Hz in these runs. One earlier session showed 90 Hz; the OS changes it.

## A/B PERFORMANCE RESULTS

Reference phone (A142, Mali-G610 MC4), deterministic autopilot, 90 s per run, all at native resolution with the v0.03B art.

**How the runs were driven:** A/B switches are passed through the perf flag file:

```bash
tools/android_perf_test.sh 90 audio_off
```

**Measurement rule:** a run only counts if the phone was unlocked and awake. A locked screen pauses the game and the run times out; those runs were re-done.

| Config | FPS avg | FPS p5 | GPU ms mean / p95 | Draw calls | Primitives |
|---|---|---|---|---|---|
| Baseline (all v0.03B on) | 53.4–53.5 | 29.8–29.9 | 14.4 / 15.4 | 100 | 73k |
| A. district audio off | 53.8 | 29.8 | 14.4 / 15.4 | 100 | — |
| B. character animation static | 53.8 | 29.8 | 14.5 / 15.4 | 99 | — |
| C. human presentation hidden | 53.6 | 30.0 | 14.0 / 15.4 | 97 | 70k |
| D. traffic presentation hidden | 53.1 | 29.9 | 14.4 / 15.4 | 90 | 67k |
| E. hero tuk art hidden | 53.9 | 30.1 | 14.5 / 15.4 | 93 | 68k |
| F. GPS ribbon hidden | 53.6 | 29.9 | 14.4 / 15.4 | 96 | 73k |
| G. signs hidden | 53.0 | 29.7 | 14.3 / 15.3 | 100 | 76k |
| H. shadows off | 53.6 | 29.8 | 14.1 / 15.2 | 87 | 53k |
| I. fog off | 53.3 | 29.7 | 14.2 / 15.4 | 100 | 73k |
| sky off (flat background) | 53.0 | 29.6 | 14.2 / 15.4 | 100 | 73k |
| J. district art hidden | 53.2 | 29.9 | 14.1 / 15.3 | 71 | 25k |
| **K. all v0.03B presentation off** | **59.8** | **60.0** | **10.3 / 11.9** | 46 | 13k |
| render scale 0.85 | 55.4 | 30.0 | 13.7 / 15.0 | 99 | — |
| **render scale 0.75** | **58.5** | **57.7** | **12.7 / 14.0** | 100 | — |

**Section profiler (debug-only `PerfSections`), means per frame on device:**

| Section | Mean ms |
|---|---|
| human logic | 0.55–0.64 (presentation 0.19–0.23 of it) |
| traffic | 0.46–0.53 per call (2 calls per frame) |
| HUD | 0.20–0.23 |
| player physics | 0.16–0.19 |
| hero visual | 0.13 |
| audio | 0.13 |
| camera | 0.09 |
| props | 0.07 |
| GPS, incidents, notifications, damage/recovery | < 0.02 each |

**Render CPU** (RenderingServer frame setup + viewport) is 1.4–1.6 ms.

## FIXES APPLIED

**1. Medium-tier 3D render resolution: render_scale 0.67 with FSR 1.0 upscaling.**
- This gives 1616×726 internal on the 2412×1084 panel. The UI stays native.
- Sequence: Phase A shipped at 0.75 (58.1 / 57.7 over 180 s). The heavier Phase B art then pushed 0.75 back over the edge (55.9–56.9 avg, p5 30–32), so the final setting is 0.67 + FSR.
- FSR costs the same as bilinear here (58.9 vs 58.8) and is sharper.
- A `scaling_mode` field was added to `GraphicsProfile`. Desktop HIGH stays at 1.0.

**2. Per-frame waste removed (CPU; no visible change).**
- `CharacterRig`: an array literal was allocated on every pose.
- `DistrictAudio`: a bed-name array was allocated every frame.
- `RideHud`: rebuilt its text every frame; it now refreshes at 10 Hz.

**3. Interior shop stock kept off the shadow pass.** The Phase B shelves and goods moved into the Detail layer, which casts no shadows and draws out to 55 m.

**4. Parked vehicles baked into district chunks.** No per-vehicle instances or extra draw calls.

**5. Instrumentation (debug/perf only).**
- `PerfSections` (microsecond timers, fixed rings, a no-op unless a perf run enables it).
- RenderingServer CPU/GPU frame timings.
- Objects, primitives and video memory.
- A seconds-below-50 count.
- The `[GraphicsRuntime]` and `[Startup]` log lines.
- A 3 s warm-up before recording.
- Perf A/B options.
- A keep-awake key in `tools/android_perf_test.sh`.

Nothing was deleted to get here: no buildings, people, traffic, shadows or materials were removed.

## FPS RECOVERY

| | FPS avg | FPS p5 | Slowest 1 s | Seconds < 50 |
|---|---|---|---|---|
| v0.03B (valid run, native) | 53.6 | 29.8–30.0 | 49.9 | 1 |
| v0.03B1 Phase A (0.75, v0.03B art) | 58.1 | 57.7 | 52.1 | 0 |
| **v0.03B1 final (0.67 + FSR, v0.03B1 art)** | **58.7** | **58.4** | **51.0** | **0** |

There is no persistent half-rate lock. The frame time p95 is 17.1 ms.

## HERO TUK V2

`scripts/art/hero_tuk_visual.gd` is rebuilt on new smooth-shaded `ArtMesh` primitives: `shell`, `sweep`, `lathe` and `grid`, with averaged normals. The flat boxes were a big part of the "procedural" look.

- **Triangles:** 7.8k, plus the driver (2.2k). Ceiling 25–30k; the brief asked not to chase triangles.

**Body:**
- tall flat-faced front cowl with a yellow chevron band and a deep-teal hood;
- chrome headlamp bucket with a glass lens (the headlight hook);
- indicators on stalks;
- framed see-through windscreen (the only transparent surface) with a wiper;
- dashboard with a speedo;
- cabin sills with chrome grab rails;
- rounded rear tub with a rear engine hump, wraparound yellow belt and black rub strip;
- rear mudguards and mudflaps;
- chrome-bezelled tail lamps (the brake hook);
- framed rear plate with reflectors;
- chrome rear grab bar.

**Seats and canopy:**
- vinyl bench, two backrest cushions with piping, driver saddle, partition rail;
- domed near-black canopy with a down-curled front visor, accent valance, edge piping and six chrome supports;
- rolled side curtains with straps;
- rolled rear canvas (open back, so the passenger stays visible).

**Running gear:**
- front fork and teal mudguard **mounted on `FrontSteer`, so they turn with the wheel**;
- lathe tyres with rounded sidewalls and tread;
- painted rims, chrome hubcaps with lug detail;
- handlebar with grips, levers and stalk mirrors.

**Materials:** glossy paint, matte fabric, rubber, chrome, clear glass, vinyl, emissive head and brake lamps. The tested set is paint, chrome, rubber, fabric, vinyl, glass_clear, lamp_head and lamp_brake.

**Physics untouched:** no colliders, mass and centre of mass unchanged (tested). There is no badge and no copied manufacturer body.

## TRAFFIC ART V2

`scripts/art/traffic_art.gd` is rebuilt on the same primitives:
- six shared surfaces per vehicle: paint, trim, glass, chrome, rubber, lamps;
- emissive head and tail lamps;
- wheel arches with outboard wheels, so the tyre face sits in the arch;
- bumpers, grilles, mirrors and plates.

| Vehicle | Triangles (budget) | Silhouette |
|---|---|---|
| Red public-bus-inspired bus | 3.7k (≤ 10k) | tall rounded body; split windscreen; destination board; cream band; deep-window rhythm; rain gutter; roof vents; two kerb-side doors with grab rails; large arched wheels; grille and round lamps; rear window and engine grille |
| Private bus | 3.7k | as above, plus roof rack, rear ladder, decorative stripes |
| Car | 3.1k (≤ 8k) | sedan proportions, domed bonnet and boot, glass greenhouse, pillars, chrome belt line |
| Van | 2.7k (≤ 8k) | tall body, short sloping nose, sliding-door rail, grille |
| Traffic tuk | 2.4k (≤ 6k) | the hero family at lower detail, with driver |
| Motorcycle with rider | 1.8k (≤ 4k) | tank, side covers, seat, exhaust, fork, nacelle lamp; rider with helmet and visor |

The public-bus red was deepened so it no longer reads salmon in the sun. No logos or real liveries.

## FORT STATION V2

The central pavilion becomes the landmark:
- **Clock tower** with four clock faces (hands at about 10:45), arched openings, pyramidal roof and finial. This is the silhouette visible down the street.
- **Portico** of paired columns with capitals and bases, under a deep entablature and cornice.
- **Dark recesses:** the entrance falls into deep shadow, with dark flanking arches.
- **Signage:** the trilingual COLOMBO FORT / කොළඹ කොටුව / கொழும்பு கோட்டை sign is on the portico and on the pavilion.
- **Wings:** pilasters with capitals and plinths, dark arcade depth and balustraded parapets.
- **End pavilions:** pediments and pilasters.
- **Steps:** three-step approach.
- **Collision:** the portico columns are collision proxies.

## PETTAH DENSITY V2

Perceived density comes from cheap static composition. The HumanAgent count is unchanged.
- **Deep shop recesses:** 1.7–2.1 m, with dark interiors, shelves packed with stock, hanging goods and strip lights.
- **Background crowd:** 162 static figures stand *inside* those recesses. They are about 700 triangles each, baked into chunks, drawn only within 55 m, with no logic and no collision. A test checks that every figure is inside a building footprint and clear of every lane.
- **Market spill per shop:** a display stall or stepped racks; sacks or crate stacks; hanging stock under the awning; often a second tarp on poles overlapping its neighbours. Pavements are 2.6–3.0 m, so the poles stand at 2.3 m.
- **Canyon:** market upper storeys cantilever 0.7–1.1 m over the pavement, with soffits.
- **Signs:** 105 perpendicular blade signs, double-sided.
- **Parking:** motorcycles parked parallel along the market kerb.
- **Lane guard:** every clutter item and parked vehicle checks that it is clear of all legal lanes, using a hashed lane-centreline index. This caught and fixed a corner case at OlcottCorner.
- **Result:** the market *edges* now read busy and layered. The carriageway itself stays wide (see Known issues).

## HUMANS V2

`scripts/art/character_builder.gd` is rebuilt with smooth shapes:
- tapered torso with shaped shoulders (slimmer and different for blouse/sari outfits);
- lathed tapered limbs with rounded joints;
- a smaller, rounder head with jaw, ears, eyes and fuller hair;
- shaped hands and shoes or sandals;
- flared lathed sarongs and long skirts.

Size and rig:
- About 2.2k triangles each (target 2–4k).
- The same 11-bone rig and 12 outfit combinations, so gameplay and animation hooks are unchanged.

Poses (`CharacterRig`):
- **Walk:** longer stride, knee lift, opposite arm swing with elbow bend, pelvis/chest counter-twist.
- **Run:** stronger, with lean and higher arm drive.
- **Dive:** a low sideways throw, arms out.
- **Argue:** pointing and open-hands gestures, leaning in, head jabbing.
- **Seated passenger:** sitting back, hands on knees, looking around.
- **Idle:** four stances per person (relaxed, hands clasped, hand on hip, arms folded).

## MATERIALS / LIGHTING

**Materials:**
- New shared materials: chrome, rubber, vinyl, clear glass, wood, cardboard.
- Clutter is split by material: carts and tables are wood; sacks and boxes are cardboard; awnings and stock are fabric.
- Shutters, poles and rails are a duller metal.

**Palette:**
- Building walls are now mostly neutral, sun-faded tones.
- Saturation is reserved for awnings, signs, umbrellas, buses and tuks.

**Weathering:**
- grime band at pavement level;
- drainpipes;
- set-back windows, lintels and hood mouldings;
- coped parapets of varied height;
- more AC units.

**Lighting:** less flat fill (ambient 0.46), a stronger sun (1.95), exposure 1.04.

Still no SSAO or bloom (the Mobile renderer, and the measured GPU budget).

## HUD COMPRESSION

The safe-area architecture is unchanged.

**Hire card**, 310 px wide (was up to 400):
- the passenger type as a coloured headline;
- `Pickup → Destination`;
- the distance and a priority chip (SAFE green, FAST orange, EXCITING magenta);
- a small accept hint, keyboard only.

**Ride card:**
- passenger;
- `→ destination`;
- remaining distance and a mood chip (colour by mood);
- a small, secondary timer.

**Readouts:** score is 22 px with a light outline; speed is 54 px (was 64) with a thin outline.

**GPS ribbon:** narrower (0.85 m), more widely spaced chevrons, opacity 0.7, still fading in ahead of the tuk.

**Safe-area matrix:** 2,793 checks pass. The test now fills the structured fields with worst-case text.

## STARTUP ANALYSIS

From the `[Startup]` marks (ms since engine start) on the device, final build:

| Phase | ms |
|---|---|
| engine + autoloads ready (bootstrap) | 1,342 |
| scene loaded (instantiate prototype + slice) | 2,046 (+704) |
| road network built | 2,519 (+309) |
| traffic pool (art meshes) | 2,604 (+85) |
| district art (procedural meshes + sign atlas) | 3,643 (+1,034) |
| humans pool (character meshes) | 3,730 (+87) |
| audio | 3,751 (+21) |
| **first frame drawn** | **8,408 (+4,656: rendering-pipeline/shader compilation)** |
| 30 frames | 9,136 |

**Real cold start is about 8.4 s** to the first frame, plus about 0.5 s of Android activity launch.

**The "35 s" in the v0.03B report was a measurement artefact:**
- When the perf script launched the app with the phone locked or dozing, Android created and immediately destroyed the surface.
- The game then waited, paused, until the screen was unlocked; one logged case waited about 200 s.
- The script now sends a wake key while waiting, but it cannot unlock a lock screen.

**Largest real cost:** first-frame pipeline compilation, about 4.7 s. A possible later optimisation is a loading screen that warms pipelines. It is not in scope.

## SCREENSHOT GATES

Copies are in `docs/screens_v003b1/` (windowed 1280×720, `fort_pettah_screens.tscn -- --gates`), plus three art previews.

| Gate | File | Verdict |
|---|---|---|
| A. Hero road | `gate_a_hero_road.png` | **pass**: upgraded hero tuk, deep-red public bus, green tuk, motorcycle with rider, people, shop-houses with deep stocked shop fronts, wires, railings, compact hire card |
| B. Market chaos | `gate_b_market_chaos.png` | **partial**: layered, busy edges (stalls, racks, umbrellas, stock-filled shops with people inside, blade signs, wire tangles, a van and tuks); the four-lane carriageway keeps it open in the middle |
| C. Active hire | `gate_c_active_hire.png` | **pass**: seated passenger visible through the open rear, compact ride card with mood chip, softer GPS ribbon, station arcade |
| D. Incident | `gate_d_incident.png` | **pass**: Fort Station portico, columns and COLOMBO FORT sign; v2 car stopped; driver out confronting the tuk; passenger still seated. Framed from a road-side camera because the chase camera hides a driver in front of the tuk (known v0.03A1 issue). The altercation is started through `TrafficIncidentManager` for a deterministic composition. |

Art previews: `v003b1_art_hero_tuk.png`, `v003b1_art_hero_rear.png` (rear three-quarter) and `v003b1_art_characters.png`.

**"Remove all signs and UI — still Colombo?"**
- **Gates A, C, D:** largely yes. Red bus, tuks, shop-houses with deep stocked fronts, wires, and the colonnaded station with its clock tower.
- **Gate B:** reads as a busy South Asian market street, but not yet unmistakably Pettah.

## AUTOMATED TESTS

`tools/run_tests.sh`: **all 18 stages pass** (Apple M2, 2026-10-23). Unit tests: 98 tests, 960 assertions. The Fort–Pettah soak completed 6 of 7 hires (the seventh was still in progress at the end), with a valid GPS plan on every boarded ride.

**New or changed in v0.03B1:**
- `test_graphics_runtime.gd` (unit): tier order and caps; mobile defaults to MEDIUM; **the docs must quote the `.tres` shadow distance**; 60 Hz physics.
- `fort_pettah_test` (now 60 checks), new checks:
  - hero v2 triangle range and material set;
  - fork on `FrontSteer`;
  - background crowd present, never on a lane, and only inside building footprints;
  - blade signs;
  - compact hire and ride cards;
  - the existing all-lane collider sweep, which now covers every new clutter item and parked vehicle;
  - no collision geometry on any visual mesh (hero, rigs, traffic, chunks).
- `hud_safe_area_test`: fills the new structured card fields with worst-case text; 2,793 checks pass.

**Locked-system suites unchanged and passing:** handling, dynamics/rollover, scoring, human world (passenger on SeatMarker), input, touch, GPS + hire + incidents, containment + damage, pavement evasion, and all soaks (including the Fort–Pettah soak).

## ANDROID RESULTS

| APK | |
|---|---|
| Path | `builds/android/tuktukcolombo-debug.apk` (git-ignored) |
| Version | 0.0.3b (code 6) |
| Device | A142, Mali-G610 MC4, Android 16, 2412×1084 |

Final 180 s perf test:

| Metric | Value |
|---|---|
| FPS avg / p5 / slowest 1 s | 58.7 / 58.4 / 51.0 |
| Frame time mean / p95 | 17.04 / 17.13 ms |
| Render CPU mean / p95 | 1.60 / 2.11 ms |
| GPU mean / p95 | 12.53 / 14.15 ms |
| Draw calls | 112 |
| Objects | 182 |
| Primitives | 149k |
| Static memory | 138.4 MB |
| Video memory | 143.5 MB |
| Traffic / people active | 4–14 / 8–12 |

**Test conditions:** the phone sat on USB power, and its thermal HAL reported a frozen "Status 2" throughout.

## PERFORMANCE COMPARISON

| | v0.03A2 | v0.03B (valid run) | **v0.03B1** | Target |
|---|---|---|---|---|
| FPS avg | 58.6 | 53.6 | **58.7** | ≥ 55 (58–60 preferred) |
| FPS p5 | 54.5 | 29.8–30.0 | **58.4** | ≥ 48 |
| Slowest 1 s | 47.4 | 49.9 | **51.0** | ≥ 45 |
| Script CPU per frame | — | about 2.8 ms | **about 2.8 ms** | — |
| GPU per frame | — | 14.4 ms | **12.5 ms** | — |
| Draw calls | 176.8 | 100 | **112** | < 280 |
| Static memory | 108.5 MB | 123.4 MB | **138.4 MB** | < 220 MB |
| 3D render resolution | native | native | **0.67 + FSR** | — |

## KNOWN ISSUES

**Market (Gate B):**
- The market street is a four-lane, 2.9 m-lane carriageway. That is locked gameplay geometry and is not changed by an art pass.
- The pavements and shop fronts are dense, but the middle stays open.
- Real "squeezing through" needs a narrower market road, which is a map and gameplay change for owner approval, or a decision to allow traffic-safe kerb-side parking and loading on the road edge.

**Render scale:** 0.67 is visibly a little softer than native. FSR keeps edges sharp, but distant signs blur sooner. GPU headroom is still only about 2 ms, so heavier per-pixel effects (SSAO, bloom, more transparency) are off the table on this device.

**Startup:** about 4.7 s of first-frame pipeline compilation.

**Phone thermals:** the thermal HAL reads frozen values; long consecutive device runs may be throttled without it showing.

**Characters:** still procedural rigid skinning; no facial animation or cloth. The background crowd is a static rest pose.

**Chase camera:** it can still hide a driver standing in front of the tuk.

**Audio:** unchanged procedural placeholders. Sinhala and Tamil text still need native review.

**Art:** remains procedural (no hand-modelled assets). The quality ceiling of this pipeline is close; the next step up is hand-authored models, which would need an owner decision on Blender.

## OWNER PLAYTEST QUESTIONS

1. Does the game now feel smooth on your phone throughout, and is the slightly softer 3D image (0.67 render scale) acceptable?
2. Does the hero tuk v2 look like a tuk you are proud to drive, especially from the rear three-quarter chase view?
3. Do the red public bus and the private buses read as Sri Lankan at a glance?
4. Is Fort Station (clock tower, portico) recognisable as the landmark?
5. Does the market feel busy enough, or should we narrow the market road (a gameplay change) to get the "squeezing through" feel?
6. Do the people look less like mannequins? Which poses still look stiff?
7. Is the compact hire card readable at a glance while driving?
8. Is the GPS ribbon now subtle enough but still easy to follow?
9. Does the lighting feel like hot late morning, with enough depth?
10. Is about 8–9 s of cold start acceptable for now, or should a loading or warm-up screen be the next small task?
