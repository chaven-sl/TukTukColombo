# GPS route guidance (v0.03A1)

Owner playtest: accepting a hire was confusing — who, where, how to get there,
where next. v0.03A1 answers all four.

## Hire flow

1. **Hire offered.** The nearest waiting passenger within
   `RideConfig.hire_offer_radius` (220 m) is offered. The top-left card says
   HIRE AVAILABLE · passenger type · Pickup · Destination · Trip (route km) ·
   Priority. Its world beacon is emphasised (×1.8); other waiting passengers
   keep a normal beacon.
2. **ACCEPT HIRE** (E / touch button) accepts *that* hire
   (`RideManager.request_accept()`, unchanged path).
3. **Selected passenger dominant.** Its beacon goes ×3; every other offer's
   beacon and marker is hidden; an overhead label follows them:
   `PICK UP / LATE EXECUTIVE / 320 m` (route distance).
4. **GPS to pickup** — ribbon + top-centre instruction. Near the passenger:
   `STOP TO PICK UP`.
5. **Boarding** — route removed.
6. **Active ride** — destination route appears automatically (no button).
   Ride panel: destination, remaining route distance, mood, time.
7. **Arrived / failed / cancelled / reset** — route cleared.

Cancellation: an accepted hire is cancelled if the tuk ends up
`cancel_extra_distance` (140 m) farther from the passenger than when it
accepted (and at least `cancel_distance`).

## Architecture

| Piece | Role |
|---|---|
| `RoadNetwork.route_path(from, to, heading)` | same direction-aware Dijkstra as `route()` (no U-turn starts, kerb-lane ends, lap allowed), plus path reconstruction → `RoutePlan`. Prefers the lane the tuk is in and the destination kerb lane (lateral-offset cost). |
| `RoutePlan` (pure) | polyline + cumulative distance, turns at junction connectors with ≥ 35° heading change (gentle bends/lane wiggles never become instructions), windowed projection, `next_instruction()` |
| `RouteGuidance` (node) | follows RideManager state, caches one plan, tracks progress every 0.1 s, off-route detection, rate-limited recalculation |
| `RouteRibbon` | road-hugging mesh (1.5 m steps, 7 cm above the road) built only when the route changes; shader hides the driven part (uniform), solid core + animated chevrons; unshaded, no shadows |
| `RideHud` | hire card, GPS line, pickup marker, beacons |

Instructions: `LEFT — 80 m` / `RIGHT — 120 m` when the next junction turn is
within 250 m, `STRAIGHT — 240 m` when it is farther, `PICKUP — 35 m` /
`DESTINATION — 50 m` after the last turn, `STOP TO PICK UP` / `STOP HERE` in
the stop radius. Distances rounded to 10 m (≥ 100 m) or 5 m.

## Off-route

Off-route = more than 9 m from the route line for 1.2 s, or driving against
the route direction (> 8 km/h) for 2.5 s. Then the route is recalculated
from the tuk's position and heading — at most once per 3 s
(`recalc_cooldown`); extra requests are counted as suppressed. Accepting,
boarding and player reset force an immediate recalculation.

## Performance

Route search runs only on accept / boarding / reset / off-route (≤ 1 per 3 s).
Per-tick cost is a windowed projection over ~70 segments every 0.1 s. The
ribbon mesh is rebuilt only with the route (≈ 2 triangles per 1.5 m).
