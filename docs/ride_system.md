# Ride system

`RideManager` (`scripts/rides/ride_manager.gd`) is a focused node. It is not part of GameState, and there is no giant manager.

## Hire offer (v0.03A1)

The nearest waiting passenger within `RideConfig.hire_offer_radius` (220 m) is
offered as a hire (card: type, pickup, destination, trip, priority). ACCEPT
HIRE → GPS to the pickup → boarding → GPS to the destination (see
`gps_route_guidance.md`). The v0.02 12 m `accept_radius` is kept only as
reference. Collision/incident passenger lines are profile data
(`collision_reaction_key`, `incident_reaction_key`; see `traffic_incidents.md`).

## Lifecycle

```
NO_RIDE ──accept──▶ OFFER_SELECTED ─▶ EN_ROUTE_TO_PICKUP ──stop ≤5 km/h within 9 m──▶ BOARDING
   ▲                                     │ drove >90 m away: cancel               │ tuk left: back to EN_ROUTE
   │                                                                              ▼
RETURN_TO_IDLE ◀─ EXITING ◀─ COMPLETED ◀─ ARRIVED ◀──stop ≤5 km/h within 12 m of destination── ACTIVE
                     ▲                                                                       │
                     └──────────────────────────── FAILED ◀── pedestrian impact / rollover ──┘
```

Transitions are whitelisted in `RideManager.TRANSITIONS`; anything else is rejected and counted (tests assert 0). Pickup is deliberately generous: anywhere within 9 m of the passenger, at 5 km/h or less, upright. A drive-by at 30 km/h never boards (tested).

## During an active ride

- **Telemetry** (`RideTelemetry`, aggregates only):
  - time, distance, average and max speed (km/h), speed histogram;
  - collisions (and major ones), close calls, tight gaps, combo peak;
  - two-wheel events and time, roll above 15° time, rollovers, hard brakes;
  - pedestrian danger and impacts.
- **Distance remaining:** lane-graph route from the tuk to the destination, recomputed once a second.
- **Reactions:** `PassengerReactionSystem` lines in a speech bubble, at most one every 4 s.
- **HUD:** passenger, destination, km remaining, live "passenger mood" %, and a timer. A green beacon marks the destination.

## Failure rules (v0.02 decisions)

| Event | Result |
|---|---|
| PEDESTRIAN_IMPACT | ride FAILS immediately, no fare |
| Rollover (ROLLOVER collision event, after 0.6 s on its side) | ride FAILS. Chosen for clean prototype behaviour: a passenger won't stay in a tuk that went over. Configurable via `RideConfig.fail_on_rollover`. |
| Minor / major collision | ride continues; safety, comfort and severe penalties lower the rating |

Pedestrian impact with no ride active is recorded as an unsafe-driving incident (combo reset, save counter, notice); driving continues.

## Result

The result card shows outcome, passenger, distance, time, average speed (km/h), driving-style summary, passenger rating, base fare, rating adjustment and final fare. It closes after 7 s or on E. The exiting passenger walks away while the card is up, and the offer returns 6 s later. `EventBus.ride_finished` carries the `RideResult`; `GameState` persists the counters.

## Save statistics (schema v2)

`rides_completed`, `rides_failed`, `best_passenger_satisfaction`, `pedestrian_impacts`, `prototype_fares_total`, and `passenger_type_completions{rushed, careful, thrill_seeker}`. v1 saves migrate explicitly (`SaveStore._migrate_1_to_2`) and keep all v1 values.
