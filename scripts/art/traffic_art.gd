class_name TrafficArt
extends RefCounted
## Sri Lankan traffic fleet art (v0.03B): public-bus-inspired red bus,
## private bus (blue/white or decorated multicolour), Japanese-proportioned
## compact sedan, urban delivery/passenger van, commuter motorcycle with rider,
## and three-wheelers in the usual colours. All fictional — no manufacturer
## badges, no SLTB logos or real liveries.
##
## One mesh per (kind, paint) with 2–3 shared-material surfaces → 2–3 draw
## calls per vehicle. Front is −Z (TrafficAgent forward). Footprints match
## the TrafficVehicleClass sizes exactly (collision is a separate box).

static var _cache: Dictionary = {}

const DARK := Color(0.08, 0.08, 0.09)
const TYRE := Color(0.05, 0.05, 0.055)
const RIM := Color(0.62, 0.63, 0.65)
const GLASS := Color(0.22, 0.3, 0.36)
const LAMP := Color(1.0, 0.95, 0.8)
const TAIL := Color(0.75, 0.06, 0.05)
const CREAM := Color(0.94, 0.9, 0.8)


static func mesh_for(cls: TrafficVehicleClass, color_index: int) -> ArrayMesh:
	var paint := cls.body_colors[posmod(color_index, cls.body_colors.size())]
	var key := "%s_%d" % [cls.id, posmod(color_index, cls.body_colors.size())]
	if _cache.has(key):
		return _cache[key]
	var p := ArtMesh.new()   # paint
	var d := ArtMesh.new()   # dark / rubber / trim / lamps
	var g := ArtMesh.new()   # glass
	match cls.kind:
		TrafficVehicleClass.Kind.BUS:
			_bus(p, d, g, cls, paint, posmod(color_index, cls.body_colors.size()))
		TrafficVehicleClass.Kind.MOTORCYCLE:
			_motorcycle(p, d, g, cls, paint)
		TrafficVehicleClass.Kind.TUK:
			_tuk(p, d, g, cls, paint)
		TrafficVehicleClass.Kind.VAN:
			_van(p, d, g, cls, paint)
		_:
			_car(p, d, g, cls, paint)
	var mesh := ArrayMesh.new()
	p.commit(ArtMaterials.get_material(&"paint"), mesh)
	d.commit(ArtMaterials.get_material(&"plaster"), mesh)
	g.commit(ArtMaterials.get_material(&"glass"), mesh)
	_cache[key] = mesh
	return mesh


static func triangle_count(mesh: ArrayMesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += mesh.surface_get_array_index_len(s) / 3
	return n


static func clear_cache() -> void:
	_cache.clear()


static func _wheel(d: ArtMesh, pos: Vector3, r: float, w: float) -> void:
	var xf := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), pos)
	d.cylinder(xf, Vector3.ZERO, r, w, 10, TYRE)
	d.cylinder(xf, Vector3.ZERO, r * 0.55, w + 0.02, 8, RIM)


static func _car(p: ArtMesh, d: ArtMesh, g: ArtMesh, cls: TrafficVehicleClass, paint: Color) -> void:
	var I := Transform3D.IDENTITY
	var w := cls.width
	var hl := cls.length * 0.5
	# Lower body: rounded nose and tail.
	p.loft(I, [Vector4(-hl, 0.55, w * 0.9, 0.42), Vector4(-hl + 0.35, 0.6, w, 0.58), Vector4(hl - 0.35, 0.62, w, 0.6),
			Vector4(hl, 0.6, w * 0.92, 0.48)], 0.4, paint)
	# Greenhouse (glass) + roof (paint).
	g.loft(I, [Vector4(-0.95, 1.08, w * 0.86, 0.36), Vector4(-0.45, 1.13, w * 0.84, 0.46), Vector4(0.75, 1.13, w * 0.84, 0.46),
			Vector4(1.25, 1.06, w * 0.82, 0.32)], 0.35, GLASS)
	p.loft(I, [Vector4(-0.42, 1.38, w * 0.8, 0.06), Vector4(0.72, 1.38, w * 0.8, 0.06)], 0.5, paint)
	for sx: float in [-1.0, 1.0]:  # pillars
		p.box(I, Vector3(sx * w * 0.42, 1.12, 0.15), Vector3(0.06, 0.48, 0.08), paint)
	# Bumpers, lamps, plates.
	d.box(I, Vector3(0, 0.38, -hl - 0.02), Vector3(w * 0.92, 0.16, 0.12), DARK)
	d.box(I, Vector3(0, 0.38, hl + 0.02), Vector3(w * 0.92, 0.16, 0.12), DARK)
	for sx: float in [-1.0, 1.0]:
		d.box(I, Vector3(sx * w * 0.33, 0.66, -hl - 0.005), Vector3(0.32, 0.1, 0.03), LAMP)
		d.box(I, Vector3(sx * w * 0.36, 0.7, hl + 0.005), Vector3(0.26, 0.12, 0.03), TAIL)
	d.box(I, Vector3(0, 0.5, hl + 0.04), Vector3(0.42, 0.1, 0.02), CREAM)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_wheel(d, Vector3(sx * (w * 0.5 - 0.1), 0.31, sz * (hl - 0.8)), 0.31, 0.2)


static func _van(p: ArtMesh, d: ArtMesh, g: ArtMesh, cls: TrafficVehicleClass, paint: Color) -> void:
	var I := Transform3D.IDENTITY
	var w := cls.width
	var hl := cls.length * 0.5
	p.loft(I, [Vector4(-hl, 0.85, w * 0.92, 1.0), Vector4(-hl + 0.3, 1.05, w, 1.5), Vector4(hl - 0.05, 1.08, w, 1.62),
			Vector4(hl, 1.08, w * 0.96, 1.58)], 0.18, paint)
	# Big windscreen + side windows band.
	var ws := Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 1.45, -hl + 0.18))
	g.box(ws, Vector3.ZERO, Vector3(w * 0.86, 0.62, 0.04), GLASS)
	for sx: float in [-1.0, 1.0]:
		g.box(I, Vector3(sx * (w * 0.5 + 0.005), 1.48, 0.25), Vector3(0.01, 0.42, cls.length * 0.7), GLASS)
		d.box(I, Vector3(sx * (w * 0.5 + 0.01), 1.02, 0.4), Vector3(0.01, 0.03, 1.2), DARK)  # sliding door rail
	d.box(I, Vector3(0, 0.42, -hl - 0.02), Vector3(w * 0.94, 0.2, 0.1), DARK)
	d.box(I, Vector3(0, 0.42, hl + 0.02), Vector3(w * 0.94, 0.2, 0.1), DARK)
	for sx: float in [-1.0, 1.0]:
		d.box(I, Vector3(sx * w * 0.36, 0.72, -hl - 0.005), Vector3(0.26, 0.14, 0.03), LAMP)
		d.box(I, Vector3(sx * w * 0.42, 0.95, hl + 0.005), Vector3(0.14, 0.28, 0.03), TAIL)
	d.box(I, Vector3(0, 0.62, hl + 0.03), Vector3(0.42, 0.1, 0.02), CREAM)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_wheel(d, Vector3(sx * (w * 0.5 - 0.1), 0.32, sz * (hl - 0.75)), 0.32, 0.2)


static func _bus(p: ArtMesh, d: ArtMesh, g: ArtMesh, cls: TrafficVehicleClass, paint: Color, variant: int) -> void:
	var I := Transform3D.IDENTITY
	var w := cls.width
	var hl := cls.length * 0.5
	var public := paint.r > 0.5 and paint.g < 0.3  # red = public-bus-inspired
	var band := CREAM if public else (ArtPalette.AWNING_YELLOW if variant % 2 == 0 else ArtPalette.CORAL)
	var skirt := paint.darkened(0.25)
	# Main body (slightly rounded corners) on a dark chassis skirt.
	p.loft(I, [Vector4(-hl, 1.65, w * 0.98, 2.5), Vector4(-hl + 0.12, 1.65, w, 2.56), Vector4(hl - 0.1, 1.65, w, 2.56),
			Vector4(hl, 1.65, w * 0.98, 2.5)], 0.12, paint)
	d.box(I, Vector3(0, 0.45, 0), Vector3(w * 0.96, 0.3, cls.length - 0.3), DARK)
	# Cream / accent belt under the windows and a roof cap.
	for sx: float in [-1.0, 1.0]:
		p.box(I, Vector3(sx * (w * 0.5 + 0.005), 1.62, 0), Vector3(0.01, 0.22, cls.length - 0.6), band)
		p.box(I, Vector3(sx * (w * 0.5 + 0.005), 0.78, 0), Vector3(0.01, 0.12, cls.length - 0.6), skirt)
		# Side window row with dark mullions.
		g.box(I, Vector3(sx * (w * 0.5 + 0.008), 2.2, 0.35), Vector3(0.01, 0.72, cls.length - 2.0), GLASS)
		for k in 9:
			var z := lerpf(-hl + 1.4, hl - 0.8, float(k) / 8.0)
			d.box(I, Vector3(sx * (w * 0.5 + 0.012), 2.2, z), Vector3(0.012, 0.74, 0.07), paint.darkened(0.15))
	# Entrance door (left side, kerb side in Sri Lanka) near the front.
	d.box(I, Vector3(-(w * 0.5 + 0.01), 1.45, -hl + 1.55), Vector3(0.01, 2.0, 0.9), DARK.lightened(0.15))
	p.box(I, Vector3(0, 3.0, 0), Vector3(w * 0.92, 0.14, cls.length - 0.5), paint.lightened(0.15) if public else CREAM)
	# Front: big windscreen, destination board, bumper, lamps.
	g.box(I, Vector3(0, 2.0, -hl - 0.01), Vector3(w * 0.9, 1.15, 0.02), GLASS)
	d.box(I, Vector3(0, 2.78, -hl - 0.012), Vector3(w * 0.8, 0.3, 0.02), DARK)
	d.box(I, Vector3(0, 2.78, -hl - 0.02), Vector3(w * 0.6, 0.18, 0.01), Color(1.0, 0.62, 0.12))  # destination LEDs
	d.box(I, Vector3(0, 0.62, -hl - 0.05), Vector3(w * 0.98, 0.3, 0.12), DARK)
	for sx: float in [-1.0, 1.0]:
		d.box(I, Vector3(sx * w * 0.38, 0.95, -hl - 0.02), Vector3(0.3, 0.16, 0.03), LAMP)
		d.box(I, Vector3(sx * w * 0.42, 1.0, hl + 0.01), Vector3(0.16, 0.36, 0.03), TAIL)
	g.box(I, Vector3(0, 2.15, hl + 0.01), Vector3(w * 0.75, 0.7, 0.02), GLASS)
	if not public:
		# Private buses: roof rack + decorative stripe.
		for k in 5:
			d.box(I, Vector3(0, 3.14, lerpf(-hl + 1.5, hl - 1.5, float(k) / 4.0)), Vector3(w * 0.85, 0.05, 0.05), DARK)
		for sx: float in [-1.0, 1.0]:
			d.box(I, Vector3(sx * w * 0.42, 3.12, 0), Vector3(0.05, 0.08, cls.length - 3.0), DARK)
			p.box(I, Vector3(sx * (w * 0.5 + 0.007), 1.32, 0), Vector3(0.01, 0.1, cls.length - 0.6), ArtPalette.ACCENTS[(variant + 2) % ArtPalette.ACCENTS.size()])
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_wheel(d, Vector3(sx * (w * 0.5 - 0.18), 0.5, sz * (hl - 1.9)), 0.5, 0.32)


static func _motorcycle(p: ArtMesh, d: ArtMesh, g: ArtMesh, cls: TrafficVehicleClass, paint: Color) -> void:
	var I := Transform3D.IDENTITY
	_wheel(d, Vector3(0, 0.3, -0.72), 0.3, 0.1)
	_wheel(d, Vector3(0, 0.3, 0.7), 0.3, 0.12)
	d.box(I, Vector3(0, 0.55, 0), Vector3(0.16, 0.18, 1.1), DARK)                   # frame / engine
	p.loft(I, [Vector4(-0.45, 0.85, 0.24, 0.18), Vector4(-0.1, 0.88, 0.3, 0.24), Vector4(0.2, 0.85, 0.26, 0.18)], 0.5, paint)  # tank
	d.box(I, Vector3(0, 0.92, 0.42), Vector3(0.26, 0.08, 0.55), DARK)               # seat
	p.box(I, Vector3(0, 0.8, 0.72), Vector3(0.16, 0.08, 0.4), paint)                # rear fender
	d.cylinder(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.75, -0.62)), Vector3.ZERO, 0.025, 0.7, 5, RIM)  # fork
	d.box(I, Vector3(0, 1.08, -0.52), Vector3(0.66, 0.035, 0.035), DARK)            # handlebar
	d.box(I, Vector3(0, 0.98, -0.66), Vector3(0.14, 0.12, 0.06), LAMP)              # headlamp
	d.box(I, Vector3(0, 0.85, 0.94), Vector3(0.1, 0.05, 0.02), TAIL)
	# Rider (static, stylised): shirt in paint-adjacent tone, dark trousers, helmet.
	var shirt: Color = ArtPalette.CLOTH[int(absf(paint.r * 7.0 + paint.b * 5.0)) % ArtPalette.CLOTH.size()]
	d.box(I, Vector3(0, 1.32, 0.22), Vector3(0.38, 0.5, 0.24), shirt)
	for sx: float in [-1.0, 1.0]:
		d.box(Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(sx * 0.2, 1.3, -0.08)), Vector3.ZERO, Vector3(0.09, 0.42, 0.09), shirt)
		d.box(Transform3D(Basis(Vector3.RIGHT, -1.3), Vector3(sx * 0.13, 0.92, 0.12)), Vector3.ZERO, Vector3(0.13, 0.42, 0.14), Color(0.18, 0.2, 0.28))
		d.box(I, Vector3(sx * 0.15, 0.5, -0.12), Vector3(0.11, 0.42, 0.12), Color(0.18, 0.2, 0.28))
	d.sphere(I, Vector3(0, 1.76, 0.18), Vector3(0.15, 0.15, 0.17), ArtPalette.ACCENTS[(int(paint.g * 10.0)) % 4], 8, 5)  # helmet
	g.box(I, Vector3(0, 1.74, 0.03), Vector3(0.2, 0.08, 0.02), GLASS)


static func _tuk(p: ArtMesh, d: ArtMesh, g: ArtMesh, _cls: TrafficVehicleClass, paint: Color) -> void:
	var I := Transform3D.IDENTITY
	var accent := ArtPalette.AWNING_YELLOW
	p.loft(I, [Vector4(-1.32, 0.74, 0.5, 0.56), Vector4(-1.08, 0.78, 0.84, 0.78), Vector4(-0.62, 0.8, 1.12, 0.84)], 0.55, paint)
	p.loft(I, [Vector4(0.4, 0.66, 1.2, 0.56), Vector4(1.0, 0.68, 1.25, 0.6), Vector4(1.34, 0.68, 1.1, 0.56)], 0.45, paint)
	d.box(I, Vector3(0, 0.36, 0.0), Vector3(1.16, 0.07, 2.4), DARK)
	for sx: float in [-1.0, 1.0]:
		p.box(I, Vector3(sx * 0.6, 0.96, 0.9), Vector3(0.07, 0.05, 0.9), accent)
		d.cylinder(I, Vector3(sx * 0.6, 1.3, -0.8), 0.02, 0.6, 5, RIM)
		d.cylinder(I, Vector3(sx * 0.62, 1.3, 1.2), 0.02, 0.6, 5, RIM)
	d.arc_shell(I, -0.9, 1.3, 0.68, 1.58, 0.18, 6, DARK)
	g.box(Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(0, 1.36, -0.84)), Vector3.ZERO, Vector3(1.02, 0.55, 0.02), GLASS)
	d.box(I, Vector3(0, 1.0, -1.34), Vector3(0.16, 0.12, 0.03), LAMP)
	for sx: float in [-0.46, 0.46]:
		d.box(I, Vector3(sx, 0.82, 1.36), Vector3(0.14, 0.09, 0.03), TAIL)
	# Driver silhouette (static).
	var shirt: Color = ArtPalette.CLOTH[int(paint.r * 9.0 + paint.g * 3.0) % ArtPalette.CLOTH.size()]
	d.box(I, Vector3(0, 1.12, -0.18), Vector3(0.36, 0.44, 0.22), shirt)
	d.sphere(I, Vector3(0, 1.47, -0.2), Vector3(0.1, 0.12, 0.11), ArtPalette.SKIN[int(paint.b * 10.0) % ArtPalette.SKIN.size()], 7, 4)
	d.sphere(I, Vector3(0, 1.53, -0.17), Vector3(0.1, 0.07, 0.1), Color(0.07, 0.06, 0.06), 7, 3)
	_wheel(d, Vector3(0, 0.21, -1.0), 0.21, 0.12)
	_wheel(d, Vector3(-0.575, 0.21, 1.0), 0.21, 0.16)
	_wheel(d, Vector3(0.575, 0.21, 1.0), 0.21, 0.16)
