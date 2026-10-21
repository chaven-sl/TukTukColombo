# Performance budget

Targets: mid-range Android at 60 FPS where possible; **stable 30 FPS floor** on supported low-end devices. Renderer: Mobile (Vulkan). Physics: Jolt, 60 Hz, physics interpolation on.

## Budgets (v0.01 working numbers — validate on device)

| Item | Budget | v0.01 actual |
|---|---|---|
| Dynamic rigid bodies | 1 | 1 (player) |
| Active traffic agents | 8–20 (adaptive), design 14 | ≤ 14 |
| Pooled agents | 24 | 24, never instantiated at runtime |
| Draw calls (typical view) | ≤ 250 | 148–154 (M2 capture) |
| Lights | 1 directional (+ shadow) | 1; shadows 60 m, orthogonal |
| Shadow casters | player + signals | traffic, road, scenery: off |
| Transparent materials | none | none |
| Post-processing | none (no SSR/SSAO/volumetrics/glow) | fog only |
| Per-frame allocations | none in gameplay loops | none (debug overlay throttled to 5 Hz) |
| Gameplay CPU (scripts + physics) per frame | ≤ 6 ms on mid-range | ~2.6 ms mean, 8 ms max on M2 (windowed, `--perf`) |

## Measured (Apple M2, macOS, 1280×720 window)

- Windowed soak with autopilot: **60 FPS vsync-locked** (p5 ≈ 58–59). One early run reported a 146 FPS mean, consistent with a higher-refresh/uncapped display state — treat desktop FPS as non-indicative.
- Physics + gameplay scripts: **2.6 ms mean / 8.2 ms max** per frame (windowed `--perf`); headless 3.6 ms physics + 2.1 ms process.
- 2 simulated minutes run in ~5 s headless.
- **No Android measurement yet.** Rough expectation: mid-range ARM CPU 3–5× slower than M2 single-core ⇒ ~8–13 ms gameplay CPU — inside a 33 ms frame, tight for 60 FPS. First device capture is the next recommended step.

## Rules in code

- Cached references only; no `get_nodes_in_group` / tree searches per frame.
- Squared-distance broad phases (spawn, despawn, near-miss).
- Fixed-size packed arrays for per-agent state; RefCounted `Lane`s with typed arrays.
- One traffic update loop; agents have no `_physics_process`.
- MultiMesh for scenery (3–4 draw calls); shared BoxMesh/material caches for traffic.
- Static collision is boxes + one trimesh per road segment edge.
- Debug drawing (ImmediateMesh) only when F2/F3 is on.

## Adaptive budget

See traffic_system.md. Desktop never triggers reductions; the hysteresis behaviour is covered by unit tests (`tests/unit/test_adaptive_budget.gd`) with synthetic frame times.

## Risks

- Physics CPU on low-end ARM (Jolt + 300 static shapes from scenery) — consider merging scenery colliders or dropping tree/lamp colliders.
- Mobile Vulkan driver variance; ETC2/ASTC import is enabled.
- Shadow cost on low-end — candidate to disable via a quality setting.
