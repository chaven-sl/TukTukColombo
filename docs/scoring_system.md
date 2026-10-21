# Scoring: near misses, tight gaps, combos

Config: `resources/scoring/scoring_config.tres` (`data/scoring/scoring_config.gd`). PROTOTYPE BASELINE v0.01a. All speeds in **km/h** (the detector converts to SI internally).

## NearMissDetector (detection only)

Runs after vehicle and traffic each physics tick. Per active agent within a 14 m broad phase it computes the exact **edge-to-edge clearance between oriented rectangles** (player footprint 1.3 × 2.6 m vs agent footprint; `OrientedRect`, allocation-free), relative velocity, and the agent's position in the player frame. State per agent lives in fixed-size packed arrays indexed by `agent_id`.

1. **IDLE → TRACKING** when clearance ≤ 2.0 m, player ≥ 15 km/h, relative speed ≥ 15.75 km/h (75 % of the close-call threshold) and the agent's 2.5 s cooldown has elapsed.
2. **TRACKING**: keeps the minimum clearance and the side at that moment. Expires if clearance grows past 2.6 m, if it stays *alongside at low relative speed* (< 12.6 km/h) for > 0.8 s, or after 5 s. **Any contact with the agent rejects it** (and suppresses it until it leaves proximity).
3. **CROSS**: the agent's centre crosses the plane through the player's centre perpendicular to its heading → CONFIRMING.
4. **CONFIRM** after the agent is fully past or 0.35 s, with no contact since tracking started →
   - **CLOSE_CALL** if min clearance ≤ **0.95 m** and relative speed at the crossing ≥ **21 km/h**. There is **no minimum clearance**: the collision system alone decides whether contact happened.
   - A pass with clearance ≤ **1.35 m** and relative speed ≥ **16 km/h** is a **threat**. Two threats on **opposite sides** by different agents whose crossings are within **0.9 s** → **TIGHT_GAP** (replaces the second close call; the first may already have scored).
   - `is_oncoming` is recorded (ONCOMING type is architected, not scored).

## v0.01a changes

| Parameter | v0.01 | v0.01a | Reason |
|---|---|---|---|
| Minimum clearance | 0.15 m | **none** | A scrape-free pass closer than 15 cm earned nothing, which felt wrong. Contact detection decides instead. |
| CLOSE CALL max clearance | 0.85 m | **0.95 m** | Slightly more forgiving reading of "close". |
| CLOSE CALL relative speed | 21.6 km/h (6 m/s) | **21 km/h** | Expressed in km/h; marginally lower. Still blocks parking-speed farming. |
| TIGHT GAP window | 0.7 s | **0.9 s** | Real squeezes between staggered vehicles took longer than 0.7 s. |
| TIGHT GAP threat clearance | 1.2 m | **1.35 m** | Deliberate squeezes with ~1.2–1.3 m each side were missed. |
| TIGHT GAP threat relative speed | 14.4 km/h (4 m/s) | **16 km/h** | Within the brief's 14–18 km/h; keeps slow creeping out. |
| Config units | m/s | **km/h** | Unit standard. |

Earlier fix (v0.01): candidates used to expire after 1.6 s of total tracking, which killed legitimate overtakes at the minimum relative speed; expiry now counts only low-relative-speed time alongside.

## ComboManager (pure rules)

- Each skill event: `chain += 1`, timer refreshed to **3.0 s**, award = base × `clamp(chain, 1, 5)`.
- Timeout → chain 0. Any collision (MINOR or MAJOR, configurable) → chain 0.
- Base points: CLOSE_CALL 25, TIGHT_GAP 50 (ONCOMING 35 reserved).

## ScoringSystem and feedback

Unchanged from v0.01: subscribes to `EventBus.skill_event` / `collision_event`, owns the ComboManager, updates `GameState`, emits `score_awarded` / `combo_changed` and local `combo_lost`. The HUD shows restrained popups ("CLOSE CALL +25", "TIGHT GAP ×2 +100"), a pulsing combo label with a timeout bar and "COMBO LOST".

## Verified (`tests/scenarios/scoring_scenarios_test.tscn`, tuk at 50 km/h past parked cars)

| Scenario | Result |
|---|---|
| 0.5 m pass | 1 CLOSE CALL (+25 ×1), no collision |
| **0.08 m non-contact pass** | **1 CLOSE CALL**, no collision |
| 1.4 m pass | nothing |
| **18 km/h pass at 0.3 m** | **nothing** (relative speed below 21 km/h) |
| between two cars at 0.5 / 0.55 m | CLOSE CALL +25 then TIGHT GAP ×2 +100 |
| **looser squeeze: 1.2 / 1.25 m, crossings ~0.6 s apart** | **TIGHT GAP** (+50), no close calls |
| **normal lane spacing: 1.6 m each side** | **nothing** (no tight gap) |
| three passes | ×1, ×2, ×3 (25, 50, 75) |
| side-swipe | collision, no award for that car, combo reset |

In the 6-minute autopilot soak, close calls still occur naturally (6) while TIGHT GAP did not (0): the test autopilot does not deliberately thread two vehicles. Whether tight gaps now feel attainable is a human-playtest question.
