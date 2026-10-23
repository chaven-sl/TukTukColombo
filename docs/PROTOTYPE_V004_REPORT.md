# Prototype v0.04 — Core Progression Loop

## STATUS

**PASS.**

The game now has a persistent sense of forward progress:

**HIRE → DRIVE → DROP OFF → EARN → GARAGE → UPGRADE → RETURN TO STREET → BETTER / HARDER HIRES.**

- **Results:** all 22 test stages pass (19 existing + economy simulation, career flow, upgrade dynamics); Android: street 58.3 FPS avg / 57.9 p5, garage ≈ 58.9 FPS.
- **Locked systems unchanged:**
  - the Fort–Pettah map;
  - base vehicle physics (upgrades are a modifier layer on a copy);
  - touch controls;
  - the traffic and human architectures;
  - GPS;
  - passenger personalities, near misses, incidents, damage/recovery and pedestrian safety;
  - the Android graphics profile and render scale/FSR.

## CORE LOOP

1. **Boot → HOME / GARAGE**
   - The first screen shows the hero tuk, cash, reputation, career level, the four upgrades and DRIVE.
   - A device perf test still boots straight to the street, so the benchmark is unchanged.
2. **DRIVE → Fort–Pettah.**
   - Hires work as before.
   - The hire card now shows the job tier and an estimated pay, e.g. `0.4 km · ≈ Rs. 650` with FAST and EXPRESS chips.
   - A wallet line (`Rs. 3,150   ★ 160`) sits by the score.
3. **Drop off → the result card explains the money:**
   - base fare and passenger rating;
   - clean ride, smooth ride, fast fare and skill bonuses;
   - collision deductions and the job/level bonus;
   - **TOTAL**, **+★**, and career progress (`TRUSTED TUK ★ 171 / 350`).
   - Cash and reputation are credited and saved immediately.
4. **Optional return to the garage**
   - It's in the pause menu, under RETURN TO GARAGE.
   - It's offered only when no hire is active and the tuk has stopped; otherwise it shows "Finish the hire and stop first".
   - It never teleports you out of an active hire.
   - Nothing forces a garage visit: keep taking jobs as long as you like.
5. **Garage**
   - A session summary is shown once: cash earned, rides completed, reputation earned, best combo, collisions, pedestrian incidents.
   - Then buy upgrades and DRIVE again: the tuk drives with its upgrades.
6. **Close and reopen:** all progression is in the save. This is tested by reloading the file from disk.

## CURRENCIES

Two only. No gems, energy, fuel timers or tokens.

| Currency | Shown as | Spendable | Purpose |
|---|---|---|---|
| **CASH** | `Rs. 1,250` | yes | upgrades (later: cosmetics) |
| **REPUTATION** | `★ 120` | no | career level, job tiers, future unlock hooks |

**Start:** Rs. 1,500 and ★ 0, owning exactly one tuk. Invariants (enforced and tested):
- cash never goes below 0;
- reputation is never deducted;
- a tampered save is clamped.

## FARE / BONUSES

`RidePayout` builds on the **existing fare architecture**, which is unchanged in code: base fare = pickup fee + per-km, plus the existing satisfaction adjustment. The fare values in `ride_config.tres` were scaled for the progression loop (see Balance simulation).

| Line | Rule |
|---|---|
| Base fare | Rs. 320 + Rs. 600/km (rounded to Rs. 10) |
| Passenger rating | existing −50 % … +40 % from satisfaction |
| Clean ride | no collisions and no pedestrian danger; Rs. 110 × (0.5 + passenger's safety weight), so it matters most to a Careful Aunty |
| Smooth ride | no hard brakes or collisions; Rs. 55 × (0.5 + comfort weight) |
| Fast fare | time score ≥ 85; Rs. 90 × (0.5 + time weight), so it matters most to a Late Executive |
| Driving skill | close calls, tight gaps and combo × the passenger's **positive** close-call preference: a Thrill Seeker pays for it, a **Careful Aunty never does**; capped at Rs. 280 |
| Collisions | −Rs. 70 each, major −Rs. 140; the total is never below 0 |
| Job & level bonus | ×1.35 EXPRESS, ×1.6 PREMIUM; +5 % per career level above 1 |

**Pedestrian danger never pays:**
- any pedestrian danger or impact cancels every skill and clean bonus (tested);
- satisfaction falls as before;
- a pedestrian impact earns 0 ★.

**Failed rides** earn Rs. 0 and 0 ★.

## REPUTATION

Reputation is earned from the passenger rating on completed rides:

| Ride | Rating | ★ |
|---|---|---|
| Poor | < 40 % | 1–2 |
| Average | 40–65 % | 3–5 |
| Good | 65–85 % | 6–8 |
| Excellent | ≥ 85 % | 9–12 |
| Failed / major safety failure | — | 0 |

EXPRESS adds +1 ★ and PREMIUM +2 ★, capped at 12 per ride. Reputation is never deducted.

## CAREER TIERS

| Level | Name (prototype copy) | ★ |
|---|---|---|
| 1 | STREET ROOKIE | 0 |
| 2 | CITY DRIVER | 50 |
| 3 | TRUSTED TUK | 150 |
| 4 | COLOMBO REGULAR | 350 |
| 5 | STREET LEGEND | 700 |

**What the career level controls:**
- **Job tiers:** EXPRESS from level 2, PREMIUM from level 3, more frequent at higher levels.
- **Payouts:** +5 % fare per level.
- **Difficulty:** tighter EXPRESS timing; PREMIUM expectations.
- **Notification:** a level-up message appears in the street.

Unlock hooks for future districts and tuk tiers exist (the level is cached in the save). **Fort–Pettah remains the only district.**

## JOB TIERS

Job tiers are labels on ordinary hires, not a mission system. The passenger's **personality stays separate**: a tier applies a copy of their profile with tier expectations layered on, through the existing single satisfaction model.

| Tier | Expectation | Pays |
|---|---|---|
| STANDARD | normal | base |
| EXPRESS | expects 25 % faster progress; time matters more | ×1.35 cash, +1 ★ |
| PREMIUM | collisions hurt 35 % more; comfort matters more | ×1.6 cash, +2 ★ |

## GARAGE

`scenes/garage/garage.tscn`, built cheaply in code. The scene:
- a dim, warm workshop impression: corrugated walls, workbench, tool board, tyre stack, oil drum, a work light, and a fictional *PERERA TUK WORKS* sign;
- the hero tuk, using the same `HeroTukVisual` with no physics body, on a slowly turning platform.

The UI:
- **Top bar:** cash, reputation, career level with a progress bar.
- **Left:** four upgrade cards (level pips, LV x/5, next cost).
- **Right:** the selected upgrade — description, CURRENT, NEXT, IMPROVEMENT, COST, and **[UPGRADE — Rs. X]**.
  - With too little cash, the button is disabled and shows **NEED Rs. X MORE**.
  - At level 5 it shows MAX LEVEL.
- **Bottom left:** relative **SPEED / BRAKING / HANDLING / SUSPENSION** bars. No physics numbers.
- **Bottom right:** **DRIVE**.
- **Debug builds only:** a small balancing line (average Rs./ride, rides to the next upgrade).

**Purchase feedback** (no loot-box spectacle):
- a procedural ratchet, clunk and chime sound (`upgrade_clunk`, generated);
- a mechanical pulse of the tuk;
- the new stat segment flashing in.

Screenshots: `docs/screens_v004/` (garage, purchase, session summary, hire card, ride result).

## UPGRADES

`UpgradeDefinition` resources live in `resources/economy/upgrade_*.tres`. Each holds an id, display key, five costs, the affected tuning fields, per-level amounts and a human-readable improvement.

**`EffectiveVehicleConfig.build(base, levels)`** returns a **copy** of the base `VehicleTuning` with the effects applied:
- The base resource is never mutated (tested), and `TukController` code is unchanged.
- The driving scene keeps the base and assigns the effective copy.

**Protected fields** that no upgrade may touch (tested): mass, centre of mass, inertia, body size, tyre grip, maximum steer angle, all roll-assist and roll-cutoff values, and the inside-wheel-light threshold. This keeps **body roll, two-wheel behaviour and rollover** intact.

| Upgrade | Per level | Level 5 vs stock (measured on the real tuk) |
|---|---|---|
| ENGINE | +2.5 km/h top speed, +4 % drive force, +6 % power | 0→50 km/h **8.5 → 6.3 s**; top speed **68 → 78.7 km/h** |
| BRAKES | +7 % brake force, +4 % handbrake | 50→0 km/h **13.2 → 11.6 m (−12 %)** |
| HANDLING | +5 % steering response, +3 % cornering stiffness, +6 % yaw damping | sharper, steadier, and **still rolls over** in a hard 62 km/h turn |
| SUSPENSION | +5 % damping, +6 % bump-stop stiffness (travel unchanged) | calmer over kerbs and landings; not an off-roader |

**Cost per level (all four):** Rs. 2,500 → 4,300 → 7,000 → 10,200 → 14,400. That is Rs. 38,400 per category and Rs. 153,600 for everything.

## BALANCE SIMULATION

`tests/sim/economy_sim.gd`:
- offline and deterministic;
- runs the real `PassengerSatisfaction`, fare, `RidePayout`, `JobTiers` and `CareerProfile` code;
- 500 rides for each of four player skills, with a buy-cheapest-affordable policy;
- pacing measured as **medians over 200 seeded careers**.

The full table is in `docs/economy_simulation.md`. It is a test stage, so a broken curve fails CI.

| Player | Rs./ride | ★/ride | median 1st upgrade | median rides to 2nd | Level 2 | Level 3 | Level 5 | All 20 levels |
|---|---|---|---|---|---|---|---|---|
| poor | 406 | 3.4 | ride 5 | +10 | 27 | 64 | 246 | 446 |
| average | 724 | 6.3 | **ride 3** | **+5** | 11 | 29 | 120 | 229 |
| good | 934 | 7.6 | **ride 2** | **+4** | 9 | 22 | 98 | 182 |
| excellent | 1,077 | 8.7 | ride 2 | +4 | 6 | 20 | 83 | 150 |

Every target passes:
- the first upgrade comes within 2–4 rides, and the second within another 3–5 (average and good players);
- better driving earns monotonically more;
- nobody maxes everything within 100 rides;
- a poor driver still progresses;
- level 2 arrives around ride 11 for an average driver;
- STREET LEGEND is a long-term goal (83+ rides).

**Why the rupee scale is higher than the brief's examples.** The brief's sample (start Rs. 1,500, Level 1 Rs. 800) would allow an upgrade *before the first ride*. Its pacing targets need roughly **start ÷ earnings per early ride ≤ 3**. With the start fixed at Rs. 1,500, early rides must earn around Rs. 500, so fares were scaled up and Level 1 set to Rs. 2,500.

An average ride now pays about Rs. 700. That is well above real Colombo tuk fares (owner question 8). Lowering everything together is a one-file change if you prefer realism over this pacing.

## SAVE MIGRATION

**Schema v2 → v3** adds a `career` section: cash, reputation, career level (cached), upgrade levels, total, successful and failed rides, total earned and spent, upgrades bought, best ride payout, express and premium completions.
- Every v2 value is kept.
- The existing tmp → verify → backup → promote write, temp/backup recovery and corrupt-file quarantine are unchanged.
- **Normalisation clamps tampered values:** negative cash or reputation becomes 0, and upgrade levels are held to 0–5.

**Purchases** are atomic: cash and level change together or not at all. Each is saved immediately. A purchase names the level it expects, so a rapid second tap is rejected as stale.

**Rides** credit the career and save at once (not on the 20 s autosave).

**Automated runs** use their own save slot, so tests never touch the player's progression. `-- --save-slot=NAME` selects a slot explicitly.

## TESTS

`tools/run_tests.sh`: **all 22 stages pass (unit: 124 tests / 1,083 assertions)**.

**New in v0.04:**
- **Economy (unit, 14 tests):**
  - cash and reputation rewards, failed rides, no pedestrian reward;
  - personality-aware skill bonus (Thrill Seeker pays, Aunty doesn't);
  - collisions never push the total below 0;
  - job tiers pay more, tier availability by level, tier profiles never edit shared resources;
  - career levels;
  - purchase success, insufficient funds, max level, no double purchase, no negative cash, career credit.
- **Upgrades (unit, 7 tests):**
  - level 0 equals base, and the base resource is never mutated;
  - engine, brake, handling and suspension effects and bounds;
  - protected roll and rollover fields;
  - well-formed definitions.
- **Save (unit, 5 new tests):** clean new save, v2→v3 migration, cash/reputation/upgrade persistence, corrupt primary recovered from backup, tamper clamping.
- **Economy simulation (stage):** the pacing targets above.
- **Career flow (stage, real scenes):**
  - garage → DRIVE → 2 hires credited, with every rupee explained;
  - return to the garage (safe-moment check), with the summary shown;
  - buy ENGINE 1, with the rapid second tap rejected;
  - DRIVE again at 72.5 km/h top speed;
  - the save reopened from disk retains cash, reputation, upgrades and stats.
- **Upgrade dynamics (stage, real TukController):** 0–50 km/h time, top speed, braking distance, and a level-5 tuk that still rolls over.
- **HUD safe-area matrix:** now renders the worst-case result card (every payout line, PREMIUM); 2,793 checks pass.

The 19 v0.03B1.1 stages remain and pass.

## ANDROID

APK exported (debug, 0.0.3b code 6, 87.4 MB) and installed on the reference phone (A142, Mali-G610 MC4).

- **Boot:** the existing v2 save on the phone loaded and migrated to v3 (`LOADED_PRIMARY`), giving a clean career.
- **Flow:** boot shows the garage. A perf-test launch still boots straight to the street.
- **Garage frame rate:** about **58.9 FPS** from Android's SurfaceFlinger, sampled over 8 s.

## PERFORMANCE

Street driving: deterministic 180 s device test, Fort–Pettah, medium tier 0.67 + FSR (unchanged).

| Metric | v0.03B1.1 (approved) | **v0.04** | Target |
|---|---|---|---|
| FPS avg | 58.3 | **58.3** | ≥ 55 |
| FPS p5 | 57.9 | **57.9** | ≥ 48 |
| Slowest 1 s | 51.9 | **53.0** | — |
| Seconds below 50 FPS | 0 | **0** | — |
| GPU mean / p95 | 12.68 / 14.20 ms | 12.50 / 14.24 ms | — |
| Draw calls | 138 | 141 | < 280 |
| Static memory | 140.0 MB | 146.2 MB | < 220 MB |

**No regression.** The economy code runs only at ride end and in the garage. The only new per-frame string is the HUD wallet line.

## KNOWN ISSUES

**Economy scale:**
- Fares were scaled to meet the pacing targets from a Rs. 1,500 start; an average ride is about Rs. 700, above real tuk fares.

**Garage:**
- No touch-specific layout pass beyond the shared safe-area root; the buttons are large.
- The garage UI is built in code, like the HUD.

**Upgrades:**
- The suspension upgrade is the subtlest to *feel*: it changes damping and bump stops, not travel.

**Job tiers:**
- Tiers apply to whichever passenger spawns, so a PREMIUM Thrill Seeker is possible: personality and tier are deliberately independent.

**Localisation:**
- Sinhala and Tamil strings for the new UI are empty and fall back to English. They need translation.

**Analytics:**
- Balancing data is local only: `[Economy]` log lines, save stats, and the garage debug line in debug builds. No analytics SDK.

## OWNER PLAYTEST QUESTIONS

1. Do earnings feel satisfying after a ride?
2. Do you understand why you earned that amount?
3. Does reputation feel meaningful?
4. Do you want to do another hire?
5. Is returning to the garage intuitive?
6. Is purchasing an upgrade satisfying?
7. Can you actually feel the upgrade while driving?
8. Is progression too fast or too slow, and is the rupee scale acceptable?
9. Does the garage feel clean rather than menu-heavy?
10. Would you naturally keep playing to unlock the next upgrade?

## RECOMMENDED NEXT STEP

**STOP for the owner playtest.**

To play:
1. Install the APK.
2. Boot into the garage.
3. Drive, do 3–5 hires, return, upgrade, and drive again.
4. Close and reopen the app.

Then answer the 10 questions.

Likely follow-ups, depending on the answers:
- the rupee scale versus pacing;
- a touch layout pass for the garage;
- Sinhala and Tamil copy;
- tuning the per-level upgrade feel.

Not started: another district, monetisation, ads, IAP, skins, police, multiplayer.
