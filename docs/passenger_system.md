# Passenger system

## Profiles (data only: `data/passengers/passenger_profile.gd`)

v0.02 extends the v0.01 schema in a backward-safe way. New fields default to neutral, so old resources still validate and normalise. The new fields:

- `excitement_weight`
- `two_wheel_preference`
- `pedestrian_danger_sensitivity` (must be > 0: pedestrian danger can never be liked)
- `expected_speed_kmh`
- `priority_key`
- `marker_color`

`normalised_weights()` returns `Vector4(time, safety, comfort, excitement)` summing to 1.

| | Late Executive (`rushed`) | Careful Aunty (`careful`) | Thrill Seeker (`thrill_seeker`) |
|---|---|---|---|
| Card priority | FAST | SAFE | EXCITING |
| Weights T / S / C / E | 0.55 / 0.25 / 0.10 / 0.10 | 0.10 / 0.55 / 0.35 / 0 | 0.15 / 0.15 / 0.05 / 0.65 |
| Risk tolerance (vehicles) | 0.6 | 0.1 | 0.95 |
| Close-call preference | 0 (indifferent) | −0.8 (hates) | +0.9 (loves) |
| Two-wheel preference | −0.1 | −1.0 | +0.7 |
| Collision penalty × | 1.2 | 2.5 | 1.0 |
| Pedestrian-danger sensitivity | 1.0 | 2.0 | 1.0 (still always negative) |
| Preferred speed ± tolerance | 55 ± 15 km/h | 30 ± 8 km/h | 60 ± 15 km/h |
| "On time" average speed | 32 km/h | 26 km/h | 30 km/h |
| Marker colour | blue | magenta | orange |

## Physical presence

Each offer owns a real HumanAgent (role PASSENGER), waiting at its PICKUP spot with a spinning coloured marker and a matching beacon pillar. After acceptance they stay put. When the tuk stops alongside, they walk to the tuk's left-side `BoardingPoint` (left-hand traffic, kerb side), board in 0.8 s, then ride hidden at the `SeatMarker`. On completion or failure they reappear beside the tuk, walk to the drop-off (or the nearest sidewalk), and return to the pool.

## Offers (`PassengerOfferManager`)

There is one offer per configured pickup (`profiles[i]` at `pickup_spot_ids[i]`, first sent to `initial_destination_ids[i]`):

| Passenger | Pickup | First destination | Route |
|---|---|---|---|
| Late Executive | long straight, west kerb (40 m ahead of spawn) | Market | ≈ 414 m |
| Careful Aunty | long straight, east kerb | South Junction | ≈ 400 m |
| Thrill Seeker | north street, west kerb | Temple Road | ≈ 361 m |

The offer card appears within 12 m of an available passenger. It shows name, destination, route distance (km) and priority, plus "E — ACCEPT RIDE" (the key label is read from the `interact` InputMap action; touch can call `RideManager.request_accept()`). After a ride, the offer returns 6 s later with a new random destination at least 250 m away, and a new passenger body. It won't pop into view within 60 m.

Route distance is the shortest directed path through the lane graph (`RoadNetwork.route_distance`). Each end snaps to any ordinary lane within 14 m, either direction, so a route may imply a U-turn at pickup.

## Reactions (`PassengerReactionSystem`)

Lines are translation keys chosen from profile data, not per-passenger scripts:
- **Close calls / tight gaps:** positive when close_call_preference > 0.3, negative when < −0.3.
- **Two-wheel moments:** use two_wheel_preference the same way.
- **HURRY_UP / GOOD_SPEED:** only for time-focused profiles.
- **TOO_FAST:** only when safety outweighs time.
- **Collision and pedestrian danger:** every profile reacts negatively.

Rate limits: a 4 s global cooldown, 12 s per line, and priorities (pedestrian danger > collision > two-wheel > near miss > speed moods). Placeholder English only.
