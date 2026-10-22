# Graphics profiles (foundation, v0.03A)

`GraphicsProfile` Resources (`data/platform/graphics_profile.gd`, instances in
`resources/platform/`). Applied once by `prototype_main.apply_graphics_tier()`;
no in-game menu yet.

| Tier | Sun shadows | Shadow distance | 3D render scale | MSAA | FPS cap | Fog |
|---|---|---|---|---|---|---|
| LOW | off | — | 0.85 | off | 30 | on |
| MEDIUM | on | 60 m | 1.0 | off | 60 | on |
| HIGH | on | 60 m | 1.0 | off | uncapped | on |

Default: MEDIUM on mobile, HIGH on desktop (HIGH = exactly the v0.02 look).
Choosing LOW/MEDIUM per device (from the perf test result, or a settings
option) is v0.03B+ work. Art direction is unchanged; profiles only scale
rendering cost.
