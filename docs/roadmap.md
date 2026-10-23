# Roadmap

Each phase ends with a human playtest gate. Do not start the next phase without it.

| Phase | Goal | Scope |
|---|---|---|
| **v0.01** (done) | Driving through traffic is enjoyable for 5 minutes | tuk controller, camera, lanes, junction, pooled traffic, close calls, tight gaps, combo, save/locale/platform foundations, passenger data stub, tests |
| v0.01a (done) | High agility + high consequence handling | steering/grip/rollover calibration, two physics defects fixed, roll-state telemetry |
| **v0.02** (done) | Same tuk, different passenger | HumanAgent foundation, pedestrians (sidewalks, crossings, reactions), 3 physical passengers, ride loop, systemic satisfaction, prototype fare, pedestrian safety rules, save v2 |
| **v0.03A** (done, awaiting device playtest) | Android + touch + production readiness | Android toolchain, debug APK export (min 28 / target 35, arm64), touch controls (analog steer pad, GO/BRAKE, horn, accept, pause), Back/focus lifecycle, safe-area layout, performance monitor + 5-min device perf test, graphics profile foundation, qualitative passenger mood, pickup U-turn fix |
| **v0.03A1** (done, awaiting device playtest) | Owner Android feedback | floating-origin touch steering (no drift), hire card + ACCEPT HIRE + selected-passenger marker, GPS ribbon + turn instructions + off-route recalculation, traffic altercations (tiers × driver temperaments, driver gets out/argues/returns), passenger collision lines, audio hooks |
| **v0.03A2** (done, awaiting device playtest) | World + crash consequences | safe-area HUD + notification presenter, surface model, district ring, shopfront rows, physical dressing, damage states + recovery, ride failure on disabling crash, impact props, pedestrian emergency evasion |
| **v0.03B** (done, awaiting owner visual/playtest approval) | Fort–Pettah Gateway: first production-quality art + audio slice | new ~940 m district (station frontage, Olcott-style bus corridor, Pettah market, signalised junction, service connector), procedural modular building/street kits, hero tuk + driver, traffic fleet art, stylised animated people, seated passenger, trilingual signage (Noto, OFL), tropical late-morning lighting, procedural audio layer, UI/GPS polish |
| **v0.03B1** (done, awaiting owner approval) | Performance recovery + visual quality | device A/B root cause (GPU pixel-bound), medium 0.67 + FSR, hero tuk v2, traffic art v2, Fort Station v2, Pettah density (deep shops, static crowd, layered spill), humans v2, materials/lighting, compact HUD |
| v0.04 | District vertical slice | first Colombo-flavoured road set built from `RoadSegment` chains, traffic lane changes, denser street life (LOD people) |
| later | Progression and content | upgrades, customisation, districts, weather/day-night, then (only with explicit approval) platform services behind `PlatformServices` |

Out of scope until explicitly approved: ads, analytics SDKs, IAP, accounts, cloud save, leaderboards, live ops, loot boxes, fuel timers, multiplayer.
