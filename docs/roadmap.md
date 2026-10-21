# Roadmap

Each phase ends with a human playtest gate. Do not start the next phase without it.

| Phase | Goal | Scope |
|---|---|---|
| **v0.01** (done) | Driving through traffic is enjoyable for 5 minutes | tuk controller, camera, lanes, junction, pooled traffic, close calls, tight gaps, combo, save/locale/platform foundations, passenger data stub, tests |
| v0.01 playtest | Validate feel; tune | human sessions with the tuning variables in the report; Android mid-range device performance capture |
| v0.02 | Playable on a phone | touch controls (a new input source writing `VehicleInputState`), quality settings (shadows on/off), Android export pipeline, audio placeholders (engine, horn, near-miss) |
| v0.03 | First passenger loop | pickup/drop-off using `PassengerProfile`, satisfaction from skill/collision events, fare reward (no economy yet) |
| v0.04 | District vertical slice | first Colombo-flavoured road set built from `RoadSegment` chains, traffic lane changes, pedestrians decision |
| later | Progression and content | upgrades, customisation, districts, weather/day-night, then (only with explicit approval) platform services behind `PlatformServices` |

Out of scope until explicitly approved: ads, analytics SDKs, IAP, accounts, cloud save, leaderboards, live ops, loot boxes, fuel timers, multiplayer.
