# TukTuk Colombo — Art Bible (v0.03B)

The first production-quality look for the game, established in the Fort–Pettah Gateway slice. Every later district follows these rules unless the owner approves a change.

## Visual direction

**Stylised Colombo realism, about 65 % real / 35 % stylised.**
- Real: proportions, street layout, materials, the order of things on a Colombo street (road, kerb, drain, pavement, shopfront, upper floors, wires).
- Stylised: simplified shapes, clean bevels, vertex-coloured surfaces instead of photo textures, slightly richer colour, readable silhouettes at phone size.
- It should read as **Colombo at a glance**, not as "generic Asian city" or "generic tropical town".

Readability comes first. On a 6-inch phone at 50 km/h the player must read:
1. the road and lane edges;
2. traffic and people;
3. the GPS ribbon;
4. the destination.

Only then the decoration.

## Light: hot tropical late morning (10:30–11:00)

These values live in `scripts/art/district_lighting.gd`:
- **Sun:** high (about 58°) from the east-south-east, slightly warm `(1.0, 0.94, 0.82)`, energy 1.75; strong, crisp contact shadows.
- **Sky:** procedural, pale tropical blue overhead, hazy pale horizon.
- **Ambient:** a flat warm-neutral fill `(0.78, 0.78, 0.76)` at 0.55; no sky reflections (a mobile GPU budget decision, measured on device).
- **Haze:** light depth fog (density 0.0016), slightly desaturating the distance; this is what sells the humidity.
- **Grading:** filmic tone map, exposure 1.08, saturation 1.18, contrast 1.08.
- **Forbidden:** heavy bloom, orange sunset clichés, and a day/night cycle (not in scope).

## Colour palette

Source of truth: `scripts/art/art_palette.gd`. Use `ArtPalette.vary()` and `weather()` to vary colours; never invent new hues inline.

| Role | Colours |
|---|---|
| Base | warm off-white, sun-faded cream, station white, weathered concrete grey, dusty asphalt charcoal |
| Walls (sun-faded) | turquoise, faded blue, ochre, coral, mint, dusty pink, pale yellow, brick red |
| Transport | bus red; private buses blue/white or multicolour stripes; tuks in teal, black, green, red, blue, cream |
| Accents | awning yellow, market-umbrella red, blue, green and orange, purple cloth |
| Nature | tropical leaf green, used sparingly |

Rule: **colourful, never candy-coloured.**
- Saturated colour belongs to small things: awnings, umbrellas, signs and clothing.
- Big surfaces stay faded.

## Construction rules

**Collision and visual geometry are separate.**
- **Buildings:** visual chunks plus simple `StaticBody3D` box proxies (`BuildingProxies`, `PropProxies`, `ForecourtProxies`, each tagged with a `WorldSurface`).
- **Vehicles:** the physics root (`TukController`, kinematic `TrafficAgent`) plus a visual root (`Visual/HeroArt`, `Body`).
- **Humans:** `HumanAgent` logic plus a `CharacterRig` presentation.
- Any art can be replaced later without touching gameplay.

**Art follows physics.**
- The hero tuk's visual wheels sit under the physics wheel hooks (`FrontSteer/Spin`, `RearLeft/Spin`, `RearRight/Spin`).
- The handlebar copies the steer angle.
- No art node carries a collider or changes mass or centre of mass. This is checked by `fort_pettah_test`.

**No asset downloads.**
- All meshes are generated in Godot from code: `ArtMesh`, `BuildingKit`, `StreetKit`, `TrafficArt`, `CharacterBuilder`, `HeroTukVisual`. They are deterministic (fixed seeds) and reproducible.
- Blender is not installed and was not installed.
- Fonts are Noto Sans, Noto Sans Sinhala and Noto Sans Tamil, from the official Google Fonts repository under the SIL OFL 1.1; licences are in `assets/fonts/*/OFL.txt`.
- Audio is synthesised by `tools/audiogen/generate_audio.py`.

## District cues (what makes it Fort–Pettah)

1. **The white colonial railway station:**
   - arcaded frontage, pediment, clock-tower pavilion;
   - the trilingual sign COLOMBO FORT / කොළඹ කොටුව / கொழும்பு கோட்டை;
   - a tuk rank on the forecourt.
2. **Bus traffic:**
   - red public buses with a cream band, plus private buses;
   - bus bays, shelters and railings on the Olcott corridor.
3. **Pettah shop-houses:**
   - two- to four-storey narrow fronts, roller shutters, balconies, AC units;
   - trilingual shop boards (fictional names).
4. **Market spillover onto the pavement:**
   - umbrellas, stalls, sacks, crates, handcarts, hanging goods, stools.
5. **Overhead utility clutter:**
   - concrete poles, sagging wire bundles, transformers, street lamps.
6. **Faded road paint:**
   - zebra crossings, bus-zone markings, asphalt patches, drains and covers.
7. **A busy skyline beyond:**
   - background blocks, towers, and a gateway building over each side street that traffic drives into.

## Prohibited genericisation

Do not use any of the following:
- generic Western, Chinese, Indian or Southeast-Asian city kits as stand-ins;
- palm-lined beach-resort imagery in the city centre;
- clean glass-tower downtown at street level;
- neon or cyberpunk signage;
- English-only signs (shop boards carry English, Sinhala and Tamil where space allows);
- real brand, retailer, bus-operator (SLTB) or manufacturer logos or liveries (no Bajaj copy: the hero tuk is an original design);
- invisible walls at side-street ends;
- open voids behind façades.

## Characters

- Stylised, modular, rigidly skinned (11 bones), 500–650 triangles per person; 12 outfit and skin combinations.
- Clothing draws on everyday Colombo:
  - shirts and trousers, sarongs, saris and long skirts;
  - school-uniform whites, office wear, vendor caps.
- Animation is procedural: idle, walk, hurry, run, evade, dive, wait, seated, board, argue, drive. Seated passengers gesture when they react.
