# Scoring: near misses, tight gaps, combos

Config: `resources/scoring/scoring_config.tres` (`data/scoring/scoring_config.gd`). PROTOTYPE BASELINE.

## NearMissDetector (detection only)

Runs after vehicle and traffic each physics tick. Per active agent within a 14 m broad phase it computes the exact **edge-to-edge clearance between oriented rectangles** (player collision box 1.3 × 2.6 m vs agent footprint; `OrientedRect`, allocation-free), relative velocity, and the agent's position in the player frame. State per agent lives in fixed-size packed arrays indexed by `agent_id`.

1. **IDLE → TRACKING** when clearance ≤ 2.0 m, player ≥ 15 km/h, relative speed ≥ 4.5 m/s (75 % of the threshold) and the agent's 2.5 s cooldown has elapsed.
2. **TRACKING**: keeps the minimum clearance and the side at that moment. Expires if clearance grows past 2.6 m, if it stays *alongside at low relative speed* (< 60 % of threshold) for > 0.8 s, or after 5 s. Contact with the agent rejects it (and suppresses it until it leaves proximity).
3. **CROSS**: the agent's centre crosses the plane through the player's centre perpendicular to its heading → CONFIRMING.
4. **CONFIRM** after the agent is fully past or 0.35 s: no contact since the candidate started →
   - **CLOSE_CALL** if 0.15 m ≤ min clearance ≤ 0.85 m and relative speed at the crossing ≥ 6 m/s.
   - A pass with clearance ≤ 1.2 m and relative speed ≥ 4 m/s is a **threat**. Two threats on **opposite sides** by different agents with crossings within 0.7 s → **TIGHT_GAP** (replaces the second close call; the first may already have scored).
   - `is_oncoming` is recorded (ONCOMING type is architected, not scored).

Bug found during testing: the first version expired candidates after 1.6 s of total tracking. Legitimately overtaking a car at the minimum relative speed takes ~1.8 s inside proximity (bus: ~2.3 s), so valid passes expired. Expiry now only counts *low relative speed alongside* time.

## ComboManager (pure rules)

- Each skill event: `chain += 1`, timer refreshed to **3.0 s**, award = base × `clamp(chain, 1, 5)`.
- Timeout → chain 0. Any collision (MINOR or MAJOR, configurable) → chain 0.
- Base points: CLOSE_CALL 25, TIGHT_GAP 50 (ONCOMING 35 reserved). Example: third event TIGHT_GAP → 50 × 3 = 150.

## ScoringSystem

Subscribes to `EventBus.skill_event` / `collision_event`, owns the ComboManager, updates `GameState` (score, session counts, best chain), emits `score_awarded` and `combo_changed`, and a local `combo_lost(reason)` used by the HUD for "COMBO LOST".

## Feedback (HUD)

Restrained: one popup label per event (pool of 4) with a short scale punch and fade; TIGHT GAP larger and orange; combo label pulses on change with a timeout bar; "COMBO LOST" on collision reset. No particles, no shake (the camera impulse is collision-only).

## Verified

`tests/scenarios/scoring_scenarios_test.tscn` (deterministic, parked cars at exact clearances, tuk at 50 km/h):
- 0.5 m pass → 1 CLOSE_CALL (+25 ×1)
- 1.4 m pass → nothing (clearance rejection)
- 18 km/h pass → nothing (relative-speed rejection)
- between two cars at 0.5/0.55 m → CLOSE CALL +25 then **TIGHT GAP ×2 +100**
- three passes → ×1, ×2, ×3 (25, 50, 75)
- side-swipe → collision, no award for that car, combo reset

Unit tests cover multiplier progression/cap, timeout, refresh and reset.
