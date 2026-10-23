# Prototype v0.03B1.1 — Pettah Compression Gate

## STATUS

**PASS.**

The Pettah market core is now **one 2.85 m lane each way**, between deep, dense shop fronts:
- the lane reduction happens at a new signalised **Market Gate** junction;
- the road widens again toward the existing Pettah Junction;
- deliberate kerbside loading and parking line the street;
- buses keep to the arterials.

Results:
- **Tests:** all 19 stages pass (the 18 existing + the new market stage).
- **Soak:** the 6-minute Fort–Pettah soak passes.
- **Gate B:** re-shot on the narrow road.
- **Android:** Android holds the approved v0.03B1 performance: 58.3 FPS average, 57.9 p5.

All locked systems are untouched:
- hero tuk, station, traffic and character art;
- HUD, GPS presentation, lighting and materials;
- physics, scoring, the TrafficManager/HumanAgent architectures, and render scale/FSR.

## ROAD CHANGE

The market section of `scenes/districts/fort_pettah/fort_pettah_track.tscn` was rebuilt. The loop stays closed: the market straight lost exactly the junction's 16 m.

| Order | Element | Lanes each way | Lane width | Shoulder | Notes |
|---|---|---|---|---|---|
| … | Olcott Corridor / Olcott Corner | 2 | 3.6 / 2.9 m | 2.6 / 0.4 m | broad arterial (unchanged; corner zone now "olcott") |
| 1 | **MarketGate** (new signalised junction, 16 m) | 2 → 1 | — | — | the lane reduction; plus **Spice Lane**, a 56 m single-lane side street ending in a gateway building |
| 2 | MarketCoreA (34 m) | **1** | **2.85 m** | 0.35 m | zebra crossing; straight lane arrows |
| 3 | MarketBayIn (6 m) | 1 | 2.85 m | 0.35 → 2.4 m | bay taper |
| 4 | **MarketBay** (22 m) | 1 | 2.85 m | **2.4 m loading bays** | loading van, boxes, handcart / parked tuk, motorcycle row |
| 5 | MarketBayOut (6 m) | 1 | 2.85 m | 2.4 → 0.35 m | bay taper |
| 6 | MarketCoreB (38 m) | **1** | **2.85 m** | 0.35 m | crossing; straight lane arrows |
| 7 | MarketTaperOut (15 m) | 1 | 2.85 → 3.2 m | 0.35 → 1.6 m | widening again |
| 8 | MarketLower (55 m) | 1 | 3.2 m | 1.6 m | tuk stand / roadworks pen on the shoulders |
| 9 | MarketCorner, JunctionApproach | 1 | 3.3 m | 0.8 / 1.2 m | to the existing Pettah Junction |
| 10 | Pettah Junction → Service Connector | 1 → 2 | — | — | back to the two-lane loop |

**Why the lane count changes only at junctions:**
- Traffic links lanes by coincident endpoints and has no lane-change or merge logic.
- A mid-road 2→1 taper would create an unarbitrated merge.
- At an `IntersectionController`, the two corridor lanes feed the single market lane through straight connectors that **always conflict** with each other and are granted one at a time. Tested.
- Leaving the market, the single lane maps to the inner corridor lane.

**Other changes:**
- **Transition cues:** painted merge arrows on Olcott Corner's kerb lanes into the gate, straight arrows in the single-lane core, the signal heads, kerb-edge clutter, and bays.
- **Spots moved onto the new pavements:**
  - *Market Lane* pickup now sits at the loading bay, so the tuk can pull in;
  - market drop-off;
  - shop wait spot;
  - Pettah Junction drop-off.

## BEFORE / AFTER MARKET WIDTH

| Measure (market core) | v0.03B1 | v0.03B1.1 |
|---|---|---|
| Lanes | 2 + 2 | **1 + 1** |
| Lane width | 2.9 m | **2.85 m** |
| Lane-marked carriageway | 11.8 m | **5.85 m** |
| Kerb to kerb | 12.6 m | **6.55 m** (10.7 m at the loading bays) |
| Shop line to shop line (3 m pavements) | ≈ 19.3 m | **≈ 13.2 m** |
| Olcott corridor carriageway, for comparison | 15.4 m | 15.4 m (unchanged) |

## TRAFFIC MIX

- **Market core:** `bus_spawn_scale = 0`, so buses never spawn there.
- **Buses arriving at the Market Gate:** `TrafficManager.choose_next_lane(lane, heavy)` now weights each option by the exit lane's zone `bus_spawn_scale`.
  - This is a weighting tweak on the existing zone data. The architecture is unchanged.
  - Buses therefore turn into Spice Lane (scale 0.6) instead of entering the core.
- **Elsewhere:** Market Lower allows 0.1, Market Corner and Junction Approach 0.3.
- **Mix in the core:** tuks, motorcycles, cars and vans, from the global class weights.
- **Tested:** no bus was in the core at the end of the live-traffic run.

## LOADING / PARKING

All kerbside obstacles are deliberate and traffic-aware:
- they sit in bays or shoulders;
- they never touch a lane;
- the two directions are never pinched at the same spot.

| Where | Side A | Side B |
|---|---|---|
| MarketBay (2.4 m bays) | loading van + stacked boxes + handcart | parked tuk + 4-motorcycle row nosed to the kerb |
| MarketLower (1.6 m shoulder) | tuk stand (3 tuks), s 8–16 m | roadworks pen (barrier, cones, sand), s 38 m |
| Market core pavements | merchandise sacks and handcarts at the pavement edge, alternating sides every 6–9 m | (alternates) |

**Placement guard:**
- Every parked vehicle passes a footprint check along its length: at least 0.1 m from any lane edge.
- All other clutter keeps 0.3 m clear, using the hashed lane index.
- The full legal-lane collider sweep reports **0 blocked samples**.

**Overhead and edges:**
- utility poles every 18 m in the market, with sagging three-wire bundles across the street;
- festival bunting strung overhead;
- the v0.03B1 deep shops, background crowd, blade signs and spill are retained.

## ROUTING

`market_compression_test` (new stage):
- Every pickup routes to every destination (12 routes).
- Fort → Market is 423 m; Market → Fort is 402 m.
- Resets inside the market land on a legal lane facing its traffic (9/9).
- The Fort–Pettah test still checks station/market/bus-stand routes and that the GPS ribbon sits on the road (43/43).
- Off-route recalculation and the GPS presentation are unchanged and covered by `gps_incident_test`.
- **No illegal U-turn starts:** pickups use the existing legal-direction pickup facing (v0.03A1).
- **No route through obstacles:** obstacles are never on lanes (sweep), and routes follow lanes.

## SKILL OPPORTUNITIES

**Market laps (new test phase):** the test autopilot drives the market core repeatedly for 120 s at a 38 km/h cruise (the market's natural 20–45 km/h band; mean 36 km/h):
- **15** close calls from real oncoming and same-direction vehicle interactions;
- pedestrian danger never scores (awards ≤ vehicle skill events; 15 score awards for 15 vehicle close calls; 3 pedestrian-danger events, 0 rewards).

**Comparison:** the loop autopilot in the 6-minute soak spends only about 30 s in the market and logged none there. The market creates its opportunities when you actually drive it.

**No changes to scoring:** there is no speed limiter and there are no scripted triggers. Narrow lanes, oncoming traffic, loading activity and the gate signal set the pace.

## TESTS

`tools/run_tests.sh`: **all 19 stages pass (the 18 existing + the new market stage)**.

**New stage, `market_compression_test` (38 checks):**
- **Geometry:** two legal opposing lanes in every core segment; widths 2.8–2.9 m; buses excluded; Olcott and Fort still two lanes each way; market carriageway well under the corridor's.
- **Market Gate:** both corridor lanes feed the single market lane; merging connectors conflict; the market exits straight and to the side street.
- **Routing:** all pickup→destination routes, Fort↔Market, and market resets on a legal lane facing traffic.
- **Pedestrians:** every spot on the pedestrian network; market pavements on both sides; 2 crossings across the core; network connected (122 nodes reachable from the market pickup).
- **Live traffic (150 s, tuk parked in the market):**
  - inbound and outbound traffic through the core (18 / 9 entries);
  - no vehicle stopped more than 25 s (max 21.4 s at the signal);
  - no overlaps or head-on collisions;
  - the gate serves both phase groups;
  - no buses in the core.
- **Market laps:** skill opportunities, and no pedestrian rewards.

**The Fort–Pettah slice test passes**, including the full legal-lane collider sweep (0 blocked).

## SOAK

**6-minute Fort–Pettah soak: PASS.**
- **Hires:** 7 attempted, accepted and boarded; 6 completed; GPS valid on every ride.
- **Incidents:** 23 injected, 14 altercations, 5 driver exits, at most 1 driver out, 0 timeouts.
- **Off-road:** 20 episodes (pavement charges, prop strikes, shop-house crashes, wall hits); recoveries bounded; **0 failsafe**.
- **Traffic and people:** no leaks, no teleports, no overlaps, no deadlock.

**Two soak-*scenario* fixes**, needed because the narrower street changed the geometry the scripted episodes assumed. Gameplay was unaffected.
1. **Building crashes** launched from 16 m in front of a façade, which in the ≈ 13 m market street started *inside the opposite building*. They now launch from the nearest legal lane.
2. **The wall-hit episode** could pick a corner wall piece whose run-up lay outside the new, wider district rectangle. It now only uses run-ups that start inside.

`WorldRecovery` now logs the position whenever the last-resort failsafe fires.

## ANDROID PERFORMANCE

Reference phone (A142, Mali-G610 MC4), medium tier at 0.67 + FSR (unchanged), deterministic autopilot, 180 s, phone unlocked:

| Metric | v0.03B1 (approved) | **v0.03B1.1** | Target |
|---|---|---|---|
| FPS avg | 58.7 | **58.3** | ≥ 55 |
| FPS p5 | 58.4 | **57.9** | ≥ 48 |
| Slowest 1 s | 51.0 | **51.9** | — |
| Seconds below 50 FPS | 0 | **0** | — |
| Frame time mean / p95 | 17.04 / 17.13 ms | 17.14 / 17.29 ms | — |
| GPU mean / p95 | 12.53 / 14.15 ms | 12.68 / 14.20 ms | — |
| Render CPU | 1.60 ms | 1.75 ms | — |
| Game scripts per frame | 2.77 ms | 2.79 ms | — |
| Draw calls | 112 | 138 | < 280 |
| Static memory | 138.4 MB | 140.0 MB | < 220 MB |

**Why draw calls rose (+26):**
- the second signalised junction;
- the Spice Lane portal and street;
- denser market chunks.

There is still a large margin against the 280 limit. No render-scale or lighting changes were made.

## SCREENSHOT

`docs/screens_v003b11/gate_b_market_compressed.png` (1280×720, `fort_pettah_screens.tscn -- --gates`). It shows:
- the hero tuk in its narrow single lane;
- an oncoming motorcycle and tuk, a van and tuks ahead;
- the loading bay ahead;
- deep stocked shops with people inside;
- stalls, umbrellas and racks;
- kerb-edge carts and sacks;
- blade signs;
- sagging wire bundles and festival bunting overhead;
- pedestrians on both pavements.

**Acceptance question:** with all UI and place-name signs removed, does this read as a compressed, chaotic Pettah market street?

**Yes:**
- The road is now barely two vehicles wide, between stocked shop fronts and spill.
- Wires and bunting close the sky.
- Oncoming traffic fills the view.

**Honest limits:**
- The shop-house geometry is still procedural.
- Pedestrian *numbers* are unchanged (no extra HumanAgents), so the pavements are busy rather than packed.

## KNOWN ISSUES

**Traffic:**
- **Kerb lane after the market:** leaving the market at Pettah Junction, the single lane continues only into the inner corridor lane; the kerb lane fills from turns and spawns. This follows the existing lane rules.
- **Signal waits:** the Market Gate adds a signal stop to the loop. The longest wait in the core was 21 s, at the signal.

**Market pavements:**
- With only about 3 m of pavement, pedestrians can pass close to kerb-edge clutter. They have no physics, so there is visual overlap at worst.

**Measurement:**
- The loop autopilot rarely lingers in the market. Market skill opportunities are measured by the dedicated market-laps phase.

**Localisation:**
- Spice Lane gateway sign: the Sinhala and Tamil text needs native review, like all slice signage.

**Device testing:**
- Device runs need the phone unlocked: a lock screen pauses the game before the run starts.

## STOP CONDITION

v0.03B1.1 is complete. **STOP.**

Not started:
- v0.04;
- economy, progression or garage;
- another district.

Waiting for the owner's approval.
