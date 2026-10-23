class_name BuildingKit
extends RefCounted
## Fort–Pettah modular building kit (v0.03B). Parametric façades written into
## shared chunk builders (see DistrictChunks): narrow 2–4 storey shops, corner
## blocks, colonial arcade sections, warehouses, the station modules, rear
## façades and background blocks. Variation by paint, signs, awning, windows,
## shutters, balconies, roofline and grime — not by unique meshes.
##
## Module space: the street façade lies in the local plane z = 0 facing −Z
## (towards the road); the building extends into +Z; x is along the street,
## centred. Returns sign slots (local transforms + size) for the sign atlas.

const STOREY := 3.2

enum Ground { SHOP_OPEN, SHUTTERED, HALF_SHUTTER, GLAZED, WALL, LOADING }
enum Roof { PARAPET, PITCHED_TILE, PITCHED_SHEET, STEPPED }


## One narrow shop-house (2–4 storeys). `p` keys (all optional):
## width, depth, storeys, wall, trim, ground, awning (Color or null),
## awning_stripe (Color or null), balcony, roof, grime, windows (int per storey), shade_cloth
static func shop_house(c: DistrictChunks.Builders, xf: Transform3D, p: Dictionary, rng: RandomNumberGenerator) -> Array:
	var w: float = p.get("width", 6.0)
	var d: float = p.get("depth", 9.0)
	var storeys: int = p.get("storeys", 3)
	var wall: Color = p.get("wall", ArtPalette.CREAM)
	var trim: Color = p.get("trim", wall.lightened(0.18))
	var grime: float = p.get("grime", 0.15)
	var ground: int = p.get("ground", Ground.SHOP_OPEN)
	var roof: int = p.get("roof", Roof.PARAPET)
	var h := storeys * STOREY
	var hw := w * 0.5
	var signs: Array = []
	var wall_up := ArtPalette.weather(wall, grime * 0.6)
	var wall_low := ArtPalette.weather(wall, grime)
	# --- body: back/sides as one box (seen from the street at angles) ---
	c.plaster.box(xf, Vector3(0, h * 0.5, d * 0.5), Vector3(w - 0.02, h, d), wall_up, 63 & ~32)
	# --- ground floor façade (recessed shop opening between piers) ---
	var gh := STOREY + 0.2
	c.plaster.box(xf, Vector3(-hw + 0.3, gh * 0.5, 0.15), Vector3(0.6, gh, 0.3), wall_low)
	c.plaster.box(xf, Vector3(hw - 0.3, gh * 0.5, 0.15), Vector3(0.6, gh, 0.3), wall_low)
	var ow := w - 1.2
	match ground:
		Ground.SHOP_OPEN, Ground.HALF_SHUTTER:
			# Dark interior + goods shelves suggestion + roller shutter box.
			c.plaster.box(xf, Vector3(0, 1.45, 0.9), Vector3(ow, 2.9, 0.1), Color(0.14, 0.12, 0.11))
			for k in 3:
				c.plaster.box(xf, Vector3(0, 0.6 + k * 0.7, 0.75), Vector3(ow * 0.9, 0.08, 0.3), ArtPalette.pick(ArtPalette.ACCENTS, rng).darkened(0.25))
			c.metal.box(xf, Vector3(0, 3.0, 0.2), Vector3(ow, 0.28, 0.25), ArtPalette.SHUTTER)
			if ground == Ground.HALF_SHUTTER:
				_shutter(c, xf, Vector3(0, 2.3, 0.3), Vector2(ow, 1.2))
		Ground.SHUTTERED:
			_shutter(c, xf, Vector3(0, 1.5, 0.3), Vector2(ow, 2.9))
		Ground.GLAZED:
			c.glass.box(xf, Vector3(0, 1.4, 0.35), Vector3(ow, 2.6, 0.05), ArtPalette.GLASS)
			c.metal.box(xf, Vector3(0, 1.4, 0.32), Vector3(0.08, 2.6, 0.08), ArtPalette.METAL_DARK)
		Ground.LOADING:
			_shutter(c, xf, Vector3(0, 1.8, 0.3), Vector2(ow, 3.5))
		_:
			c.plaster.box(xf, Vector3(0, 1.5, 0.15), Vector3(ow, 3.0, 0.3), wall_low)
	c.plaster.box(xf, Vector3(0, 0.08, 0.3), Vector3(w, 0.16, 0.6), ArtPalette.CONCRETE)  # threshold step
	# Upper façade wall (the body box omits its street face so the shop opening stays recessed).
	if h > gh:
		c.plaster.box(xf, Vector3(0, (gh + h) * 0.5, 0.05), Vector3(w, h - gh, 0.1), wall_up, 63 & ~16)
	# --- fascia + sign band over the shop ---
	c.plaster.box(xf, Vector3(0, gh + 0.25, 0.12), Vector3(w, 0.5, 0.24), trim)
	if p.get("sign", true):
		signs.append({"xf": xf * Transform3D(Basis.IDENTITY, Vector3(0, gh + 0.25, -0.01)), "size": Vector2(w - 0.5, 0.62)})
	# --- awning over the pavement ---
	var aw = p.get("awning", null)
	if aw != null:
		var ac: Color = aw
		var depth := 1.6 + rng.randf() * 0.6
		var tilt := Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(0, gh - 0.15, 0))
		for k in 6:
			var stripe: Color = ac if (k % 2 == 0 or p.get("awning_stripe", null) == null) else p["awning_stripe"]
			c.fabric.box(xf * tilt, Vector3(-hw + w * (k + 0.5) / 6.0, 0, -depth * 0.5), Vector3(w / 6.0 + 0.01, 0.04, depth), stripe)
		c.fabric.box(xf * tilt, Vector3(0, -0.15, -depth), Vector3(w, 0.3, 0.03), ac.darkened(0.15))  # valance
	# --- upper storeys: windows, sills, balconies, ledges ---
	var win_n: int = p.get("windows", maxi(1, int(w / 2.4)))
	for st in range(1, storeys):
		var y0 := st * STOREY + 0.2
		c.plaster.box(xf, Vector3(0, y0 - 0.1, 0.05), Vector3(w + 0.1, 0.18, 0.2), trim)  # floor ledge
		var bal: bool = p.get("balcony", false) and st == 1
		for k in win_n:
			var x := -hw + w * (k + 0.5) / win_n
			var ww := minf(1.15, w / win_n - 0.6)
			c.plaster.box(xf, Vector3(x, y0 + 1.25, -0.03), Vector3(ww + 0.22, 1.85, 0.06), trim)  # frame
			c.glass.box(xf, Vector3(x, y0 + 1.25, -0.065), Vector3(ww, 1.6, 0.02), ArtPalette.WINDOW_DARK)
			if rng.randf() < 0.5:  # timber/louvre shutters half open
				c.plaster.box(xf, Vector3(x - ww * 0.55, y0 + 1.25, -0.09), Vector3(ww * 0.45, 1.6, 0.03), ArtPalette.vary(ArtPalette.TURQUOISE.darkened(0.25), rng, 0.08))
			c.plaster.box(xf, Vector3(x, y0 + 0.38, -0.1), Vector3(ww + 0.35, 0.08, 0.2), trim.darkened(0.08))  # sill
			if rng.randf() < 0.3:  # AC unit / clutter
				c.metal.box(xf, Vector3(x + ww * 0.3, y0 + 0.25, -0.25), Vector3(0.7, 0.45, 0.35), Color(0.85, 0.85, 0.82))
		if bal:
			c.plaster.box(xf, Vector3(0, y0 + 0.05, -0.55), Vector3(w * 0.85, 0.12, 1.1), trim)
			for k in int(w * 2.0):
				c.metal.box(xf, Vector3(-w * 0.42 + k * 0.5, y0 + 0.55, -1.08), Vector3(0.04, 0.9, 0.04), ArtPalette.METAL_DARK)
			c.metal.box(xf, Vector3(0, y0 + 1.0, -1.08), Vector3(w * 0.85, 0.05, 0.05), ArtPalette.METAL_DARK)
	# --- roofline ---
	match roof:
		Roof.PARAPET:
			c.plaster.box(xf, Vector3(0, h + 0.45, 0.1), Vector3(w + 0.1, 0.9, 0.2), trim)
			c.plaster.box(xf, Vector3(0, h + 0.05, d * 0.5), Vector3(w, 0.1, d), ArtPalette.CONCRETE_DARK)
			if rng.randf() < 0.45:  # water tank on the roof (very Colombo)
				c.plaster.cylinder(xf, Vector3(rng.randf_range(-hw * 0.5, hw * 0.5), h + 0.75, d * 0.6), 0.55, 1.3, 8, Color(0.15, 0.15, 0.17))
		Roof.PITCHED_TILE, Roof.PITCHED_SHEET:
			var rc := ArtPalette.ROOF_TERRACOTTA if roof == Roof.PITCHED_TILE else Color(0.55, 0.55, 0.56)
			var ridge := 1.6
			var a := xf * Vector3(-hw - 0.2, h, -0.5)
			var b := xf * Vector3(hw + 0.2, h, -0.5)
			var cc := xf * Vector3(hw + 0.2, h + ridge, d * 0.5)
			var dd := xf * Vector3(-hw - 0.2, h + ridge, d * 0.5)
			c.plaster.quad(a, b, cc, dd, rc)
			c.plaster.quad(dd, cc, xf * Vector3(hw + 0.2, h, d + 0.3), xf * Vector3(-hw - 0.2, h, d + 0.3), rc.darkened(0.1))
		Roof.STEPPED:
			c.plaster.box(xf, Vector3(0, h + 0.35, 0.1), Vector3(w + 0.1, 0.7, 0.2), trim)
			c.plaster.box(xf, Vector3(0, h + 1.1, 0.1), Vector3(w * 0.4, 0.8, 0.2), trim)
	# Grime streaks under ledges.
	if grime > 0.2:
		for k in 2:
			c.plaster.box(xf, Vector3(rng.randf_range(-hw * 0.7, hw * 0.7), h - 1.6, -0.005), Vector3(0.35, 2.4, 0.01), ArtPalette.weather(wall, 0.55))
	return signs


static func _shutter(c: DistrictChunks.Builders, xf: Transform3D, centre: Vector3, size: Vector2) -> void:
	c.metal.box(xf, centre, Vector3(size.x, size.y, 0.05), ArtPalette.SHUTTER)
	var n := int(size.y / 0.12)
	for k in n:
		c.metal.box(xf, centre + Vector3(0, -size.y * 0.5 + (k + 0.5) * size.y / n, -0.03), Vector3(size.x, 0.02, 0.01), ArtPalette.SHUTTER.darkened(0.18))


## Colonial arcade section (Fort): ground-floor arches with a shaded walkway,
## upper floor with tall windows, cornice. Used along the Fort frontage.
static func arcade(c: DistrictChunks.Builders, xf: Transform3D, w: float, bays: int, wall: Color, storeys: int, rng: RandomNumberGenerator) -> Array:
	var h := storeys * STOREY + 0.6
	var d := 10.0
	c.plaster.box(xf, Vector3(0, h * 0.5, d * 0.5 + 2.4), Vector3(w, h, d), wall, 63 & ~32)
	var bay := w / bays
	for k in bays:
		var x := -w * 0.5 + bay * (k + 0.5)
		c.plaster.arch_panel(xf * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)), bay, STOREY + 0.6, bay * 0.62, 2.2, wall)
		c.plaster.box(xf, Vector3(x, 1.5, 2.4), Vector3(bay * 0.62, 3.0, 0.1), Color(0.2, 0.18, 0.16))  # shaded walkway back wall
		for st in range(1, storeys):
			var y := st * STOREY + 0.6
			c.plaster.box(xf, Vector3(x, y + 1.3, -0.03), Vector3(1.2, 2.2, 0.06), wall.lightened(0.15))
			c.glass.box(xf, Vector3(x, y + 1.3, -0.065), Vector3(0.95, 1.95, 0.02), ArtPalette.WINDOW_DARK)
			c.plaster.box(xf, Vector3(x, y + 2.55, -0.1), Vector3(1.4, 0.18, 0.2), wall.lightened(0.15))  # hood moulding
	c.plaster.box(xf, Vector3(0, STOREY + 0.6, 1.2), Vector3(w, 0.25, 2.6), wall.darkened(0.04))  # arcade ceiling slab
	c.plaster.box(xf, Vector3(0, (STOREY + 0.6 + h) * 0.5, 0.05), Vector3(w, h - STOREY - 0.6, 0.1), wall)  # upper façade
	c.plaster.box(xf, Vector3(0, h + 0.25, 0.0), Vector3(w + 0.2, 0.5, 0.4), wall.lightened(0.1))  # cornice
	c.plaster.box(xf, Vector3(0, h, d * 0.5 + 2.4), Vector3(w, 0.2, d), ArtPalette.CONCRETE_DARK)
	return []


## Warehouse / service block: big shutters, loading bay, sheet roof, rear façade.
static func warehouse(c: DistrictChunks.Builders, xf: Transform3D, w: float, d: float, h: float, wall: Color, rng: RandomNumberGenerator) -> Array:
	c.plaster.box(xf, Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, d), ArtPalette.weather(wall, 0.3))
	var doors := maxi(1, int(w / 6.0))
	for k in doors:
		var x := -w * 0.5 + w * (k + 0.5) / doors
		_shutter(c, xf, Vector3(x, 1.9, -0.03), Vector2(minf(3.6, w / doors - 1.0), 3.6))
	c.plaster.box(xf, Vector3(0, 0.3, -0.6), Vector3(w, 0.6, 1.2), ArtPalette.CONCRETE)  # loading dock
	var rc := Color(0.5, 0.52, 0.53)
	c.plaster.quad(xf * Vector3(-w * 0.5 - 0.3, h, -0.4), xf * Vector3(w * 0.5 + 0.3, h, -0.4), xf * Vector3(w * 0.5 + 0.3, h + 1.8, d * 0.5), xf * Vector3(-w * 0.5 - 0.3, h + 1.8, d * 0.5), rc)
	c.plaster.quad(xf * Vector3(-w * 0.5 - 0.3, h + 1.8, d * 0.5), xf * Vector3(w * 0.5 + 0.3, h + 1.8, d * 0.5), xf * Vector3(w * 0.5 + 0.3, h, d + 0.4), xf * Vector3(-w * 0.5 - 0.3, h, d + 0.4), rc.darkened(0.1))
	for k in int(w / 3.0):  # high strip windows
		c.glass.box(xf, Vector3(-w * 0.5 + 1.5 + k * 3.0, h - 0.8, -0.03), Vector3(1.6, 0.5, 0.02), ArtPalette.WINDOW_DARK)
	return [{"xf": xf * Transform3D(Basis.IDENTITY, Vector3(0, h - 1.6, -0.02)), "size": Vector2(minf(w - 1.0, 7.0), 0.9)}]


## Distant / boundary block: cheap massing with window bands (skyline layers).
static func background_block(c: DistrictChunks.Builders, xf: Transform3D, w: float, d: float, h: float, wall: Color) -> void:
	c.plaster.box(xf, Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, d), wall)
	var floors := int(h / STOREY)
	for f in range(1, floors):
		c.plaster.box(xf, Vector3(0, f * STOREY + 1.2, -0.02), Vector3(w * 0.9, 1.1, 0.02), wall.darkened(0.35))
	c.plaster.box(xf, Vector3(0, h + 0.3, 0), Vector3(w, 0.6, 0.3), wall.lightened(0.08))


## Rear / side wall with service clutter (service connector, alley mouths).
static func boundary_wall(c: DistrictChunks.Builders, xf: Transform3D, w: float, h: float, wall: Color, gate: bool) -> void:
	c.plaster.box(xf, Vector3(0, h * 0.5, 0.15), Vector3(w, h, 0.3), ArtPalette.weather(wall, 0.35))
	c.plaster.box(xf, Vector3(0, h + 0.06, 0.15), Vector3(w + 0.05, 0.12, 0.4), ArtPalette.CONCRETE)
	if gate:
		c.metal.box(xf, Vector3(0, 1.1, -0.02), Vector3(3.2, 2.2, 0.05), ArtPalette.METAL_DARK.lightened(0.15))
		for k in 8:
			c.metal.box(xf, Vector3(-1.4 + k * 0.4, 1.1, -0.05), Vector3(0.04, 2.2, 0.04), ArtPalette.METAL_DARK)
