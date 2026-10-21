# Passenger satisfaction

There is one systemic model for every passenger: `scripts/rides/passenger_satisfaction.gd`. All tunables live in `resources/rides/ride_config.tres` (PROTOTYPE BASELINE). Speeds are in km/h.

```
time, safety, comfort, excitement   ← shared subscores, 0–100, from RideTelemetry
weighted = w_time·time + w_safety·safety + w_comfort·comfort + w_excitement·excitement
final    = clamp(weighted − severe penalties, 0, 100)
```

The profile changes only the weights and preference values. `RideTelemetry` is profile-neutral (it keeps a 5 km/h speed histogram rather than profile-specific counters), so exactly the same drive can be scored for every passenger.

## Subscores

**TIME.** The target time is route distance ÷ the profile's "on time" speed. The ratio actual/target maps to a score:

| Ratio | Score |
|---|---|
| ≤ 0.75 | 100 |
| 1.0 | 80 |
| 1.3 | 50 |
| 2.0 | 8 |

Linear between points. Being slightly late isn't fatal; very late is.

**SAFETY.** Starts at 100, minus:
- **Collisions:** minor 12, major 30, × collision multiplier.
- **Rollover:** 60.
- **Vehicle risk:** (close calls + 2 × tight gaps + 3 × two-wheel moments) × 7 × (1 − risk tolerance).
- **Pedestrian danger:** 18 each × pedestrian sensitivity, **independent of risk tolerance**.
- **Pedestrian impact:** 100.

**COMFORT.** Starts at 100, minus:
- **Hard brakes** (over 0.55 g): 4 each.
- **Two-wheel seconds:** 14 each × (1 − two-wheel preference).
- **Roll beyond 15°:** 6 per second × (1 − risk tolerance).
- **Collisions:** 8 each.
- **Overspeed:** the fraction of time above preferred speed + tolerance × 70.
- **Near misses:** close calls and tight gaps × 6 × max(−close-call preference, 0).

**EXCITEMENT** (vehicle events only). Starts at 15, plus:
- **Close calls:** 9 each, × max(close-call preference, 0).
- **Tight gaps:** 16 each, × max(close-call preference, 0).
- **Controlled two-wheel moments** (only if no rollover): 8 each × max(two-wheel preference, 0).
- **Time above 45 km/h:** the fraction of time × 45.
- **Combo peak:** 2 × peak × max(close-call preference, 0).

Pedestrian events are **not inputs** to excitement.

**Severe penalties** (after weighting):
- **Per collision:** 6 for minor, 15 for major, × collision multiplier. This makes crash-heavy rides poor even for the time-focused executive.
- **Per pedestrian danger:** 8 × sensitivity.
- **Pedestrian impact:** −100.

All severe penalties are non-positive by construction.

## Fixed product rule

Pedestrian danger can only ever lower satisfaction, for every profile including the Thrill Seeker. This is enforced in three ways:
- the profile validator requires a positive sensitivity;
- the excitement subscore has no pedestrian inputs;
- penalties are clamped to be non-positive.

Tested by scenario 5 and by a 300-ride fuzz test.

## Same drive, different passenger (500 m route)

| Drive | Late Executive | Careful Aunty | Thrill Seeker |
|---|---|---|---|
| 1 Fast + risky (38 s, ~47 km/h; 5 close calls, 2 tight gaps, 2 two-wheel moments) | **80.8** | **13.0** | **98.5** |
| 2 Safe + smooth (60 s at ~30 km/h, no incidents) | **76.8** | **99.1** | **41.8** |
| 3 Slow + safe (110 s at ~16 km/h) | **42.4** | **93.3** | **32.5** |
| 4 Collision-heavy (4 collisions, 2 major) | **5.2** | **0.0** | **0.0** |
| 5a Drive 2 + 2 pedestrian-danger events | 51.8 (−25) | 27.5 (−72) | 20.4 (−21) |
| 5b Drive 1 + 2 pedestrian-danger events | 55.8 (−25) | 0.0 (−13) | 77.1 (−21) |

## Fare

```
base       = round_to_10(Rs 100 pickup + Rs 90 per km × route km)
adjustment = round_to_10(base × clamp((rating − 60%) × 0.005, −0.5, +0.4))
final      = base + adjustment          (failed ride: no fare)
```

Example, 500 m route (base Rs 150):

| Rating | Adjustment |
|---|---|
| 95% | +Rs 30 |
| 87% | +Rs 20 |
| 60% | Rs 0 |
| 30% | −Rs 20 |

The fare is a prototype readout and a save statistic (`prototype_fares_total`). Nothing spends it.
