# Fort–Pettah Gateway — Art & Performance Budget (v0.03B1)

Reference device: a mid-range Android phone with a Mali-G610 MC4 GPU and a 2412×1084 panel.

Medium tier renders 3D at **render_scale 0.75**, which is 1809×813 on this phone. The UI stays at native resolution.

**Why (v0.03B1 device profiling):**
- The game is GPU-bound and pixel-bound at native resolution.
- More triangles barely cost anything: hiding all district art cut primitives from 73k to 25k but saved only 0.3 ms of GPU time.
- Per-pixel work is what costs.

**Rule:** spend on geometry and silhouettes, not on per-pixel effects (transparency, extra texture samples, post-processing).

## Frame targets

| Metric | v0.03A2 baseline (greybox) | v0.03B target |
|---|---|---|
| FPS average | 58.6 | 55–60 (prefer about 60) |
| FPS 5th percentile | 54.5 | ≥ 48 |
| Memory | 108.5 MB | < 220 MB |
| Draw calls | 176.8 | < 280 |

Measured results are in `docs/PROTOTYPE_V003B_REPORT.md`.

## Asset budgets (triangles)

| Asset | Budget | Built |
|---|---|---|
| Hero tuk v2 (body, fork, wheels, handlebar, lights) | ≤ 25–30k | about 7.8k, plus the driver (about 2.2k) |
| Bus (public red or private) | ≤ 10k | about 3.7k |
| Car | ≤ 6–8k | about 3.1k |
| Van | ≤ 6–8k | about 2.7k |
| Traffic tuk (with driver) | ≤ 6k | about 2.4k |
| Motorcycle with rider | ≤ 4k | about 1.8k |
| Person (CharacterRig, animated) | 2–4k | about 2.2k |
| Background crowd figure (static, baked) | — | about 700 |
| Whole dressed district | — | about 440k in 144 batched meshes (Detail layer only drawn within 55 m) |

## Texture budgets

- **No 4K textures. No atlas larger than 1024².**
- Colour is in vertex colours (atlas-equivalent); materials are shared.
- **SignAtlas:** one 1024² texture holding every sign (station, shop boards, portals, bus stops, junction gantry). It is rendered once through a SubViewport, then baked to a mipmapped ImageTexture. About 90 % is used.
- **Road detail:** one 256² seamless noise texture, used triplanar for asphalt, kerb and ground grain.
- **Fonts** (Noto, 3 files) total 3.4 MB.
- **Audio:** 23 mono 22.05 kHz WAVs totalling 2.3 MB.

## Material set (`scripts/art/art_materials.gd`)

v0.03B1 adds:
- **Vehicles:** chrome, rubber, vinyl, glass_clear (the only transparent material, used for the hero windscreen).
- **Clutter:** wood and cardboard.
- **Paint:** vehicle paint is glossier.
- **Chrome:** stays semi-metallic and bright, because there are no sky reflections on mobile.

| Material | Use |
|---|---|
| plaster | walls, station, kerbs on buildings |
| paint | vehicles, shutters, railings |
| metal | poles, rails, chrome |
| glass | windows (dark, mildly reflective) |
| fabric | awnings, umbrellas, canopy, clothing |
| skin | characters |
| emissive | lamps, brake lights, headlights |
| wire | utility wires |

Plus three road materials:
- asphalt (neutral charcoal, triplanar grain);
- kerb (painted white and black on the slice);
- markings (faded).

There are 11 materials in total, all shared.

## Batching / instancing policy

- **District art** is merged per 48 m cell into a few meshes per material class (Arch, Detail, Lights, Signs) by `DistrictChunks`. Each mesh is re-centred on its cell so visibility ranges measure from the right place. The slice has 125 art meshes in total.
- **Traffic** shares one cached mesh per class and colour (`TrafficArt.mesh_for`).
- **People** share one cached mesh per outfit; each person owns only an 11-bone skeleton.
- **Parked vehicles** reuse the traffic meshes.
- No per-prop nodes for clutter: props are merged into the Detail meshes; their collision is simple box proxies.

## LOD policy

| Layer | Visible to | Shadows |
|---|---|---|
| Arch (façades, station, structure) | 170 m | yes |
| Detail (clutter, props, wires, stalls, background crowd) | 55 m | no |
| Signs | about 100 m | no |
| Skyline / boundary façades (far chunks) | 700 m | no |
| Parked vehicles | 110 m | no |
| Character animation | 55 m (beyond: frozen pose) | yes (shadow tier) |

## Shadow policy

- One DirectionalLight (the sun).
- Medium tier: shadow distance 28 m (v0.03A2: 60). Reduced during the v0.03B device pass; on its own it made no measurable difference.
- Ambient light is a flat colour and sky reflections are off. Sampling sky radiance on every pixel was the GPU cost that broke the vsync budget on the Mali-G610.
- Shadow casters:
  - casting: the Arch layer, the hero tuk, traffic bodies and people;
  - never casting: clutter, signs, the skyline and wires.

## Degradation order (if a device drops below target)

1. Clutter (Detail layer range from 55 to 40 m; already reduced from 80).
2. Shadows (Arch layer stops casting beyond 20 m, or off on low tier).
3. Props (thin `_market_spill`).
4. Materials (no triplanar road detail).
5. Far pedestrians (animation distance from 55 to 35 m).
6. Background (skyline range from 700 to 400 m).

Gameplay density (traffic, people) is governed separately by `AdaptiveTrafficBudget`.
