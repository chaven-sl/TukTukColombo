class_name StreetKit
extends RefCounted
## Fort–Pettah street props (v0.03B), written straight into DistrictChunks
## builders so repeated clutter costs no extra draw calls. Big readable
## pieces go into the shadow-casting Arch surfaces; small clutter and wires
## go into the no-shadow Detail mesh (aggressively distance-culled).
## Every piece is original procedural geometry.

const POLE_GREY := Color(0.55, 0.55, 0.53)
const WOOD := Color(0.45, 0.32, 0.2)
const SACK := Color(0.82, 0.76, 0.6)
const CARDBOARD := Color(0.66, 0.5, 0.32)


static func umbrella(c: DistrictChunks.Builders, pos: Vector3, color: Color, r: float = 1.25) -> void:
	var I := Transform3D.IDENTITY
	c.detail.cylinder(I, pos + Vector3(0, 1.1, 0), 0.025, 2.2, 5, Color(0.85, 0.85, 0.85))
	# 8 alternating panels (white + colour) — the classic market umbrella.
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		var tip := pos + Vector3(0, 2.55, 0)
		var p0 := pos + Vector3(cos(a0) * r, 2.15, sin(a0) * r)
		var p1 := pos + Vector3(cos(a1) * r, 2.15, sin(a1) * r)
		var col := color if k % 2 == 0 else ArtPalette.OFF_WHITE
		c.fabric.tri(tip, p1, p0, col)
		c.fabric.tri(tip, p0, p1, col.darkened(0.3))


static func stall(c: DistrictChunks.Builders, xf: Transform3D, goods: int, rng: RandomNumberGenerator) -> void:
	c.plaster.box(xf, Vector3(0, 0.45, 0), Vector3(1.8, 0.9, 0.8), WOOD)
	c.plaster.box(xf, Vector3(0, 0.92, 0), Vector3(1.9, 0.05, 0.9), WOOD.lightened(0.15))
	match goods:
		0:  # fruit & vegetable heaps
			for k in 9:
				var col: Color = [Color(0.95, 0.65, 0.1), Color(0.3, 0.6, 0.2), Color(0.85, 0.2, 0.15), Color(0.95, 0.85, 0.3)][k % 4]
				c.detail.sphere(xf, Vector3(-0.7 + (k % 5) * 0.35, 1.05, -0.2 + (k / 5) * 0.35), Vector3(0.16, 0.12, 0.16), col, 6, 3)
		1:  # textile rolls
			for k in 7:
				var col := ArtPalette.pick(ArtPalette.CLOTH, rng)
				c.detail.cylinder(xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.75 + k * 0.25, 1.1, 0)), Vector3.ZERO, 0.11, 0.8, 6, col)
		_:  # boxed goods
			for k in 4:
				c.detail.box(xf, Vector3(-0.6 + k * 0.4, 1.12, 0), Vector3(0.35, 0.35, 0.5), ArtPalette.pick(ArtPalette.ACCENTS, rng))
	umbrella(c, xf * Vector3(0, 0, 0.2), ArtPalette.pick(ArtPalette.ACCENTS, rng), 1.3)


## Hand-pulled Pettah cart: two big spoked wheels, timber bed, long shafts.
static func handcart(c: DistrictChunks.Builders, xf: Transform3D, cargo: int, rng: RandomNumberGenerator) -> void:
	var I := xf
	c.plaster.box(I, Vector3(0, 0.75, 0), Vector3(1.1, 0.08, 2.2), WOOD)
	for sx: float in [-1.0, 1.0]:
		c.plaster.box(I, Vector3(sx * 0.53, 0.88, 0), Vector3(0.06, 0.22, 2.2), WOOD.darkened(0.1))
		c.plaster.box(I, Vector3(sx * 0.42, 0.72, -1.75), Vector3(0.07, 0.07, 1.6), WOOD)  # shafts
		var wxf := I * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * 0.62, 0.55, 0.15))
		c.plaster.cylinder(wxf, Vector3.ZERO, 0.55, 0.07, 14, Color(0.18, 0.15, 0.12), false)
		c.metal.cylinder(wxf, Vector3.ZERO, 0.08, 0.12, 6, POLE_GREY)
		for k in 4:  # spokes
			c.detail.box(wxf * Transform3D(Basis(Vector3.UP, PI * k / 4.0), Vector3.ZERO), Vector3.ZERO, Vector3(1.0, 0.03, 0.03), WOOD)
	c.plaster.box(I, Vector3(0, 0.35, 0.95), Vector3(0.06, 0.7, 0.06), WOOD)  # stand
	match cargo:
		1:
			for k in 6:
				c.plaster.bevel_box(I, Vector3(-0.25 + (k % 2) * 0.5, 0.98 + (k / 4) * 0.35, -0.6 + (k % 3) * 0.6), Vector3(0.48, 0.38, 0.55), 0.12, ArtPalette.vary(SACK, rng, 0.06))
		2:
			for k in 5:
				c.plaster.box(I, Vector3(-0.22 + (k % 2) * 0.44, 1.0 + (k / 3) * 0.45, -0.55 + (k % 3) * 0.55), Vector3(0.42, 0.42, 0.5), ArtPalette.vary(CARDBOARD, rng, 0.06))


static func sacks(c: DistrictChunks.Builders, xf: Transform3D, n: int, rng: RandomNumberGenerator) -> void:
	for k in n:
		c.plaster.bevel_box(xf, Vector3((k % 3) * 0.55 - 0.55, 0.22 + (k / 3) * 0.38, (k % 2) * 0.1), Vector3(0.5, 0.42, 0.6), 0.13, ArtPalette.vary(SACK, rng, 0.07))


static func boxes(c: DistrictChunks.Builders, xf: Transform3D, n: int, rng: RandomNumberGenerator) -> void:
	for k in n:
		var s := rng.randf_range(0.35, 0.55)
		c.detail.box(xf, Vector3((k % 2) * 0.55 - 0.27, s * 0.5 + (k / 2) * 0.45, rng.randf_range(-0.1, 0.1)), Vector3(s, s * 0.9, s), ArtPalette.vary(CARDBOARD, rng, 0.08))


static func stools(c: DistrictChunks.Builders, xf: Transform3D, n: int, color: Color) -> void:
	for k in n:
		var p := Vector3(k * 0.55, 0, (k % 2) * 0.4)
		c.detail.cylinder(xf, p + Vector3(0, 0.22, 0), 0.17, 0.44, 7, color, true, 0.15)


static func hanging_goods(c: DistrictChunks.Builders, xf: Transform3D, w: float, rng: RandomNumberGenerator) -> void:
	c.detail.box(xf, Vector3(0, 2.75, -0.4), Vector3(w, 0.03, 0.03), POLE_GREY)
	var n := int(w / 0.35)
	for k in n:
		var drop := rng.randf_range(0.5, 1.1)
		c.detail.box(xf, Vector3(-w * 0.5 + (k + 0.5) * w / n, 2.73 - drop * 0.5, -0.4), Vector3(0.22, drop, 0.04), ArtPalette.pick(ArtPalette.CLOTH, rng))


static func bollard(c: DistrictChunks.Builders, pos: Vector3, striped: bool) -> void:
	c.plaster.cylinder(Transform3D.IDENTITY, pos + Vector3(0, 0.45, 0), 0.09, 0.9, 6, Color(0.95, 0.95, 0.92))
	if striped:
		c.plaster.cylinder(Transform3D.IDENTITY, pos + Vector3(0, 0.62, 0), 0.093, 0.18, 6, Color(0.1, 0.1, 0.1))


## Concrete utility pole with crossarm; optional transformer box. Returns the
## crossarm attachment points for wires.
static func utility_pole(c: DistrictChunks.Builders, pos: Vector3, along: Vector3, transformer: bool) -> PackedVector3Array:
	var I := Transform3D.IDENTITY
	c.plaster.cylinder(I, pos + Vector3(0, 4.5, 0), 0.13, 9.0, 6, POLE_GREY, true, 0.09)
	var side := along.cross(Vector3.UP).normalized()
	var arm := Transform3D(MathUtil.basis_from_forward(along), pos + Vector3(0, 8.4, 0))
	c.detail.box(arm, Vector3.ZERO, Vector3(1.6, 0.1, 0.1), POLE_GREY.darkened(0.2))
	if transformer:
		c.metal.box(Transform3D.IDENTITY, pos + Vector3(0, 6.2, 0) + side * 0.35, Vector3(0.6, 0.9, 0.5), Color(0.45, 0.5, 0.47))
	c.detail.box(I, pos + Vector3(0, 3.2, 0) + side * 0.16, Vector3(0.22, 0.5, 0.12), Color(0.2, 0.2, 0.22))  # junction box
	return PackedVector3Array([pos + Vector3(0, 8.45, 0) + side * 0.7, pos + Vector3(0, 8.45, 0) - side * 0.7, pos + Vector3(0, 7.4, 0)])


static func wires(c: DistrictChunks.Builders, a: PackedVector3Array, b: PackedVector3Array) -> void:
	for i in mini(a.size(), b.size()):
		c.detail.wire(a[i], b[i], 0.6 + 0.15 * i, 0.03, Color(0.05, 0.05, 0.05), 6)
	# A cable bundle hanging lower (the Colombo tangle).
	if a.size() > 2 and b.size() > 2:
		c.detail.wire(a[2], b[2], 1.1, 0.06, Color(0.08, 0.08, 0.08), 6)


static func street_lamp(c: DistrictChunks.Builders, pos: Vector3, to_road: Vector3) -> void:
	c.metal.cylinder(Transform3D.IDENTITY, pos + Vector3(0, 3.6, 0), 0.07, 7.2, 6, POLE_GREY)
	var arm := pos + Vector3(0, 7.1, 0) + to_road * 0.9
	c.detail.box(Transform3D(MathUtil.basis_from_forward(to_road), (pos + Vector3(0, 7.1, 0) + arm) * 0.5), Vector3.ZERO, Vector3(0.06, 0.06, 1.8), POLE_GREY)
	c.lights.box(Transform3D(MathUtil.basis_from_forward(to_road), arm), Vector3.ZERO, Vector3(0.25, 0.1, 0.5), Color(0.6, 0.6, 0.55))


static func railing(c: DistrictChunks.Builders, a: Vector3, b: Vector3, color: Color) -> void:
	var dir := (b - a)
	var n := maxi(1, int(dir.length() / 1.5))
	for k in n + 1:
		c.detail.box(Transform3D.IDENTITY, a.lerp(b, float(k) / n) + Vector3(0, 0.5, 0), Vector3(0.05, 1.0, 0.05), color)
	var xf := Transform3D(MathUtil.basis_from_forward(dir.normalized()), (a + b) * 0.5)
	c.detail.box(xf, Vector3(0, 0.98, 0), Vector3(0.05, 0.05, dir.length()), color)
	c.detail.box(xf, Vector3(0, 0.55, 0), Vector3(0.04, 0.04, dir.length()), color)


static func bus_shelter(c: DistrictChunks.Builders, xf: Transform3D) -> void:
	c.metal.box(xf, Vector3(0, 2.6, 0), Vector3(5.0, 0.1, 2.0), Color(0.75, 0.15, 0.12))
	for sx: float in [-2.3, 2.3]:
		c.metal.cylinder(xf, Vector3(sx, 1.3, 0.7), 0.05, 2.6, 6, POLE_GREY)
	c.plaster.box(xf, Vector3(0, 1.4, 0.95), Vector3(4.8, 1.6, 0.05), Color(0.82, 0.85, 0.85))
	c.plaster.box(xf, Vector3(0, 0.5, 0.6), Vector3(4.0, 0.08, 0.4), POLE_GREY)


static func barrier(c: DistrictChunks.Builders, xf: Transform3D, w: float) -> void:
	var n := maxi(1, int(w / 2.0))
	for k in n:
		var x := -w * 0.5 + (k + 0.5) * w / n
		for j in 3:
			c.plaster.box(xf, Vector3(x, 0.35 + j * 0.25, 0), Vector3(w / n - 0.1, 0.18, 0.12), Color(0.95, 0.9, 0.85) if (j + k) % 2 == 0 else Color(0.85, 0.15, 0.12))
		c.metal.box(xf, Vector3(x - w / n * 0.45, 0.5, 0), Vector3(0.06, 1.0, 0.3), POLE_GREY)


static func construction(c: DistrictChunks.Builders, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	barrier(c, xf, 6.0)
	c.plaster.box(xf, Vector3(-1.2, 0.4, 2.0), Vector3(2.0, 0.8, 1.5), Color(0.72, 0.62, 0.45))  # sand heap
	c.plaster.box(xf, Vector3(1.5, 0.6, 2.5), Vector3(1.2, 1.2, 1.2), ArtPalette.CONCRETE)
	for k in 3:
		c.detail.cylinder(xf, Vector3(-2.5 + k * 0.6, 0.45, 1.2), 0.2, 0.9, 6, Color(0.95, 0.5, 0.1))


static func shade_tree(c: DistrictChunks.Builders, pos: Vector3, rng: RandomNumberGenerator) -> void:
	c.plaster.cylinder(Transform3D.IDENTITY, pos + Vector3(0, 1.6, 0), 0.22, 3.2, 6, Color(0.36, 0.28, 0.2), true, 0.16)
	for k in 3:
		var off := Vector3(rng.randf_range(-1.2, 1.2), 4.0 + rng.randf_range(0, 0.8), rng.randf_range(-1.2, 1.2))
		c.plaster.sphere(Transform3D.IDENTITY, pos + off, Vector3(2.2, 1.3, 2.2) * rng.randf_range(0.8, 1.1), ArtPalette.vary(ArtPalette.LEAF, rng, 0.05), 8, 4)
	c.plaster.box(Transform3D.IDENTITY, pos + Vector3(0, 0.08, 0), Vector3(1.2, 0.16, 1.2), ArtPalette.CONCRETE)  # tree surround


static func palm(c: DistrictChunks.Builders, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(8.0, 11.0)
	c.plaster.cylinder(Transform3D.IDENTITY, pos + Vector3(0, h * 0.5, 0), 0.2, h, 5, Color(0.45, 0.4, 0.33), true, 0.15)
	for k in 7:
		var a := TAU * k / 7.0
		var dir := Vector3(cos(a), -0.35, sin(a))
		var tip := pos + Vector3(0, h, 0) + dir * 2.6
		var side := dir.cross(Vector3.UP).normalized() * 0.35
		c.fabric.tri(pos + Vector3(0, h, 0), tip + side, tip - side, ArtPalette.LEAF.lightened(0.1))


## Kerb-side drain channel with grates (Colombo storm drains).
static func drain(c: DistrictChunks.Builders, a: Vector3, b: Vector3) -> void:
	var dir := (b - a)
	var xf := Transform3D(MathUtil.basis_from_forward(dir.normalized()), (a + b) * 0.5)
	c.detail.box(xf, Vector3(0, 0.155, 0), Vector3(0.45, 0.01, dir.length()), Color(0.2, 0.2, 0.2))
	for k in int(dir.length() / 3.0):
		c.detail.box(xf, Vector3(0, 0.16, -dir.length() * 0.5 + 1.5 + k * 3.0), Vector3(0.42, 0.01, 0.5), Color(0.35, 0.35, 0.36))


## Patched asphalt / utility cover lying on the road surface.
static func road_patch(c: DistrictChunks.Builders, xf: Transform3D, size: Vector2, kind: int) -> void:
	match kind:
		0:
			c.plaster.box(xf, Vector3(0, 0.012, 0), Vector3(size.x, 0.006, size.y), Color(0.2, 0.2, 0.21), 4)
		1:
			c.plaster.cylinder(xf, Vector3(0, 0.014, 0), 0.38, 0.006, 10, Color(0.32, 0.32, 0.33))
		_:
			c.plaster.box(xf, Vector3(0, 0.012, 0), Vector3(size.x, 0.006, size.y), Color(0.3, 0.29, 0.28), 4)
