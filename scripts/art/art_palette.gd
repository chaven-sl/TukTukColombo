class_name ArtPalette
extends RefCounted
## Fort–Pettah colour palette (docs/art_bible.md). Colourful, sun-faded,
## never candy. All art pulls colours from here so the district stays
## cohesive; vary with `vary()` rather than inventing new hues.

const OFF_WHITE := Color(0.93, 0.91, 0.85)
const CREAM := Color(0.91, 0.85, 0.7)
const STATION_WHITE := Color(0.95, 0.94, 0.9)
const CONCRETE := Color(0.62, 0.61, 0.58)
const CONCRETE_DARK := Color(0.45, 0.45, 0.43)
const ASPHALT := Color(0.24, 0.24, 0.25)
const TURQUOISE := Color(0.32, 0.62, 0.62)
const FADED_BLUE := Color(0.42, 0.56, 0.7)
const OCHRE := Color(0.82, 0.62, 0.3)
const CORAL := Color(0.86, 0.48, 0.4)
const BRICK := Color(0.62, 0.3, 0.24)
const BUS_RED := Color(0.72, 0.1, 0.09)
const AWNING_YELLOW := Color(0.95, 0.76, 0.2)
const MINT := Color(0.62, 0.78, 0.66)
const PINK := Color(0.88, 0.62, 0.66)
const LEAF := Color(0.24, 0.42, 0.2)
const ROOF_DARK := Color(0.33, 0.27, 0.25)
const ROOF_TERRACOTTA := Color(0.62, 0.34, 0.24)
const SHUTTER := Color(0.55, 0.57, 0.58)
const METAL_DARK := Color(0.16, 0.16, 0.17)
const GLASS := Color(0.18, 0.24, 0.28)
const WINDOW_DARK := Color(0.12, 0.13, 0.15)

## Building wall paints (sun-faded). v0.03B1 hierarchy: mostly neutral,
## weathered bases (off-white, cream, stone, concrete, faded ochre); only a
## few walls carry real colour — saturation belongs to awnings, signs,
## umbrellas, buses and tuks, so the street reads as a hierarchy.
const WALLS := [
	Color(0.9, 0.88, 0.82), Color(0.88, 0.82, 0.68), Color(0.78, 0.76, 0.7), Color(0.84, 0.8, 0.72),
	Color(0.7, 0.69, 0.66), Color(0.86, 0.76, 0.58), Color(0.8, 0.72, 0.62), Color(0.92, 0.9, 0.86),
	Color(0.62, 0.62, 0.6), Color(0.46, 0.64, 0.64), Color(0.82, 0.6, 0.44), Color(0.58, 0.68, 0.78),
]
## Awnings / umbrellas / signs (saturated but natural).
const ACCENTS := [
	Color(0.95, 0.76, 0.2), Color(0.85, 0.22, 0.18), Color(0.16, 0.5, 0.75), Color(0.2, 0.6, 0.35),
	Color(0.92, 0.45, 0.15), Color(0.6, 0.25, 0.55), Color(0.95, 0.92, 0.88),
]
## Human skin tones (Sri Lankan range) and clothing.
const SKIN := [Color(0.55, 0.38, 0.26), Color(0.45, 0.3, 0.2), Color(0.63, 0.45, 0.32), Color(0.38, 0.26, 0.18), Color(0.5, 0.35, 0.24)]
const CLOTH := [
	Color(0.95, 0.95, 0.93), Color(0.62, 0.75, 0.88), Color(0.25, 0.32, 0.48), Color(0.75, 0.25, 0.22),
	Color(0.35, 0.55, 0.4), Color(0.92, 0.78, 0.35), Color(0.55, 0.35, 0.55), Color(0.85, 0.5, 0.55),
	Color(0.3, 0.3, 0.32), Color(0.6, 0.52, 0.42), Color(0.2, 0.55, 0.6),
]


static func vary(c: Color, rng: RandomNumberGenerator, amount: float = 0.05) -> Color:
	var v := rng.randf_range(-amount, amount)
	return Color(clampf(c.r + v, 0, 1), clampf(c.g + v, 0, 1), clampf(c.b + v * 0.8, 0, 1), c.a)


## Sun-fade / grime: blends towards a dusty grey-brown.
static func weather(c: Color, amount: float) -> Color:
	return c.lerp(Color(0.5, 0.46, 0.4), clampf(amount, 0.0, 1.0))


static func pick(list: Array, rng: RandomNumberGenerator) -> Color:
	return list[rng.randi() % list.size()]
