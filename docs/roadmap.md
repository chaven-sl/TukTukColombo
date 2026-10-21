# Roadmap

Each phase ends with a human playtest gate. Do not start the next phase without it.

| Phase | Goal | Scope |
|---|---|---|
| **v0.01** (done) | Driving through traffic is enjoyable for 5 minutes | tuk controller, camera, lanes, junction, pooled traffic, close calls, tight gaps, combo, save/locale/platform foundations, passenger data stub, tests |
| v0.01a (done) | High agility + high consequence handling | steering/grip/rollover calibration, two physics defects fixed, roll-state telemetry |
| **v0.02** (done) | Same tuk, different passenger | HumanAgent foundation, pedestrians (sidewalks, crossings, reactions), 3 physical passengers, ride loop, systemic satisfaction, prototype fare, pedestrian safety rules, save v2 |
| v0.02 playtest → v0.02a | Passenger-feel calibration | tune satisfaction/reactions/pickup/pedestrian density from owner answers; Android toolchain + device baseline |
| v0.03 | Playable on a phone | touch controls (input source writing `VehicleInputState` + `request_accept()`), quality settings, Android export, audio placeholders |
| v0.04 | District vertical slice | first Colombo-flavoured road set built from `RoadSegment` chains, traffic lane changes, denser street life (LOD people) |
| later | Progression and content | upgrades, customisation, districts, weather/day-night, then (only with explicit approval) platform services behind `PlatformServices` |

Out of scope until explicitly approved: ads, analytics SDKs, IAP, accounts, cloud save, leaderboards, live ops, loot boxes, fuel timers, multiplayer.
