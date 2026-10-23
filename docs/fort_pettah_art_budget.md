# Fort–Pettah Gateway — Art & Performance Budget (v0.03B)

Reference device: a mid-range Android phone with a Mali-G610 MC4 GPU at 1602×720 internal resolution (medium tier).

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
| Hero tuk (body, wheels, handlebar, lights) | ≤ 25–30k | about 1.5k plus driver (about 0.6k) |
| Bus (public red or private) | ≤ 10k | about 0.8k |
| Car, van | ≤ 6–8k | about 0.5k |
| Traffic tuk (with driver silhouette) | ≤ 6k | about 0.6k |
| Motorcycle with rider | ≤ 4k | about 0.45k |
| Person (CharacterRig) | 2–4k | about 0.5–0.65k |
| Whole dressed district | — | about 140k in 125 batched meshes |

The headroom is deliberate. It is the budget for a later hand-modelled pass if the owner wants more fidelity.

## Texture budgets

- **No 4K textures. No atlas larger than 1024².**
- Colour is in vertex colours (atlas-equivalent); materials are shared.
- **SignAtlas:** one 1024² texture holding every sign (station, shop boards, portals, bus stops, junction gantry). It is rendered once through a SubViewport, then baked to a mipmapped ImageTexture. About 90 % is used.
- **Road detail:** one 256² seamless noise texture, used triplanar for asphalt, kerb and ground grain.
- **Fonts** (Noto, 3 files) total 3.4 MB.
- **Audio:** 23 mono 22.05 kHz WAVs totalling 2.3 MB.

## Material set (`scripts/art/art_materials.gd`)

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
| Detail (clutter, props, wires, stalls) | 55 m | no |
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
