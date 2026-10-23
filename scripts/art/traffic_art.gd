class_name TrafficArt
extends RefCounted
## Sri Lankan traffic fleet art (v0.03B1 "traffic art v2"): public-bus-
## inspired red bus, private bus (blue/white or decorated multicolour),
## compact sedan, delivery/passenger van, commuter motorcycle with rider, and
## three-wheelers in the usual colours. All fictional — no manufacturer
## badges, no SLTB logos or real liveries.
##
## v2: smooth-shaded curved bodies (ArtMesh.shell/sweep/lathe), wheel arches,
## real bumpers, grilles, lamps on the emissive material, mirrors.
## One mesh per (kind, paint) with up to 6 shared-material surfaces (paint,
## trim, glass, chrome, rubber, lamps). Front is −Z (TrafficAgent forward).
## Footprints match the TrafficVehicleClass sizes (collision is a separate
## box on the agent; art never adds colliders).

static var _cache: Dictionary = {}

const DARK := Color(0.07, 0.07, 0.08)
const TYRE := Color(0.06, 0.06, 0.065)
const RIM := Color(0.78, 0.79, 0.8)
const CHROME := Color(0.86, 0.87, 0.89)
const GLASS := Color(0.12, 0.17, 0.21)
const LAMP := Color(1.0, 0.96, 0.84)
const TAIL := Color(0.85, 0.07, 0.05)
const AMBER := Color(1.0, 0.55, 0.08)
const CREAM := Color(0.95, 0.91, 0.8)
const PLATE := Color(0.95, 0.94, 0.88)


class Parts:
	var paint := ArtMesh.new()
	var trim := ArtMesh.new()
	var glass := ArtMesh.new()
	var chrome := ArtMesh.new()
	var rubber := ArtMesh.new()
	var lamps := ArtMesh.new()


static var _parts_cache: Dictionary = {}


static func mesh_for(cls: TrafficVehicleClass, color_index: int) -> ArrayMesh:
	var idx := posmod(color_index, cls.body_colors.size())
	var key := "%s_%d" % [cls.id, idx]
	if _cache.has(key):
		return _cache[key]
	var q := parts_for(cls, idx)
	var mesh := ArrayMesh.new()
	q.paint.commit(ArtMaterials.get_material(&"paint"), mesh)
	q.trim.commit(ArtMaterials.get_material(&"plaster"), mesh)
	q.glass.commit(ArtMaterials.get_material(&"glass"), mesh)
	q.chrome.commit(ArtMaterials.get_material(&"chrome"), mesh)
	q.rubber.commit(ArtMaterials.get_material(&"rubber"), mesh)
	q.lamps.commit(ArtMaterials.get_material(&"emissive"), mesh)
	_cache[key] = mesh
	return mesh


## The per-material part meshes (shared, do not modify) — static parked
## vehicles append these into district chunks instead of adding instances.
static func parts_for(cls: TrafficVehicleClass, color_index: int) -> Parts:
	var idx := posmod(color_index, cls.body_colors.size())
	var paint := cls.body_colors[idx]
	var key := "%s_%d" % [cls.id, idx]
	if _parts_cache.has(key):
		return _parts_cache[key]
	var q := Parts.new()
	match cls.kind:
		TrafficVehicleClass.Kind.BUS:
			_bus(q, cls, paint, idx)
		TrafficVehicleClass.Kind.MOTORCYCLE:
			_motorcycle(q, cls, paint)
		TrafficVehicleClass.Kind.TUK:
			_tuk(q, cls, paint)
		TrafficVehicleClass.Kind.VAN:
			_van(q, cls, paint)
		_:
			_car(q, cls, paint)
	_parts_cache[key] = q
	return q


static func triangle_count(mesh: ArrayMesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += mesh.surface_get_array_index_len(s) / 3
	return n


static func clear_cache() -> void:
	_cache.clear()
	_parts_cache.clear()


# --- shared parts ---

## Wheel with rounded tyre, painted rim and hub (axle along X).
static func _wheel(q: Parts, pos: Vector3, r: float, w: float, seg: int = 16) -> void:
	var xf := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), pos)
	var hw := w * 0.5
	q.rubber.lathe(xf, PackedVector2Array([Vector2(r * 0.62, -hw * 0.85), Vector2(r * 0.86, -hw), Vector2(r, -hw * 0.6),
			Vector2(r, hw * 0.6), Vector2(r * 0.86, hw), Vector2(r * 0.62, hw * 0.85)]), seg, TYRE)
	q.chrome.lathe(xf, PackedVector2Array([Vector2(r * 0.63, -hw * 0.8), Vector2(r * 0.4, -hw * 0.7), Vector2(r * 0.15, -hw * 0.9),
			Vector2(0.0, -hw * 0.92)]), maxi(seg - 4, 8), RIM)
	q.chrome.lathe(xf, PackedVector2Array([Vector2(0.0, hw * 0.92), Vector2(r * 0.15, hw * 0.9), Vector2(r * 0.4, hw * 0.7),
			Vector2(r * 0.63, hw * 0.8)]), maxi(seg - 4, 8), RIM)


## Dark wheel-arch lip around a wheel on the side `sx` (−1/+1).
static func _arch(q: Parts, centre: Vector3, r: float, x: float, depth: float) -> void:
	var frames: Array = []
	for k in 11:
		var a := lerpf(-0.15, PI + 0.15, float(k) / 10.0)
		var p := centre + Vector3(x, sin(a) * r, -cos(a) * r)
		var tangent := Vector3(0, cos(a), sin(a))
		var radial := Vector3(0, sin(a), -cos(a))
		frames.append(Transform3D(Basis(Vector3.RIGHT, radial, tangent), p))
	q.trim.sweep(frames, ArtMesh.superellipse(Vector2(depth, 0.025), 4.0, 8), DARK)


static func _tube(m: ArtMesh, points: Array, r: float, color: Color, seg: int = 6) -> void:
	var frames: Array = []
	for i in points.size():
		var p: Vector3 = points[i]
		var t: Vector3 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var up := Vector3.UP if absf(t.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		var x := up.cross(t).normalized()
		frames.append(Transform3D(Basis(x, t.cross(x).normalized(), t), p))
	var prof := PackedVector2Array()
	for k in seg:
		var a := TAU * float(k) / float(seg)
		prof.append(Vector2(cos(a), sin(a)) * r)
	m.sweep(frames, prof, color)


static func _mirror(q: Parts, at: Vector3, sx: float) -> void:
	var I := Transform3D.IDENTITY
	q.trim.shell(Transform3D(Basis.IDENTITY, at + Vector3(sx * 0.1, 0, 0)), [Vector4(-0.04, 0.0, 0.16, 0.11), Vector4(0.03, 0.0, 0.15, 0.1)], 3.0, 10, DARK)
	q.trim.box(I, at + Vector3(sx * 0.03, -0.02, 0.0), Vector3(0.07, 0.025, 0.03), DARK)


# --- vehicles ---

static func _car(q: Parts, cls: TrafficVehicleClass, paint: Color) -> void:
	var I := Transform3D.IDENTITY
	var w := cls.width
	var hl := cls.length * 0.5
	var wz := hl - 0.78
	# Lower body: rounded nose, flat flanks, tucked tail (sedan proportions).
	q.paint.shell(I, [
		Vector4(-hl, 0.58, w * 0.8, 0.34), Vector4(-hl + 0.12, 0.6, w * 0.95, 0.46), Vector4(-hl + 0.45, 0.63, w, 0.56),
		Vector4(-0.6, 0.66, w, 0.62), Vector4(0.6, 0.67, w, 0.64), Vector4(hl - 0.4, 0.68, w, 0.6),
		Vector4(hl - 0.1, 0.7, w * 0.95, 0.5), Vector4(hl, 0.7, w * 0.84, 0.4)], 5.0, 24, paint)
	# Bonnet and boot lids (slightly domed) + the greenhouse.
	q.paint.shell(I, [Vector4(-hl + 0.2, 0.9, w * 0.86, 0.06), Vector4(-1.0, 0.97, w * 0.92, 0.08)], 3.0, 14, paint)
	q.glass.shell(I, [Vector4(-1.0, 1.0, w * 0.88, 0.04), Vector4(-0.55, 1.22, w * 0.84, 0.42), Vector4(0.6, 1.24, w * 0.82, 0.44),
			Vector4(1.05, 1.05, w * 0.84, 0.12)], 5.0, 20, GLASS)
	q.paint.shell(I, [Vector4(-0.5, 1.44, w * 0.8, 0.04), Vector4(-0.3, 1.47, w * 0.82, 0.05), Vector4(0.45, 1.47, w * 0.8, 0.05),
			Vector4(0.62, 1.44, w * 0.78, 0.04)], 4.0, 16, paint)
	for sx: float in [-1.0, 1.0]:
		for z: float in [-0.52, 0.06, 0.62]:  # A / B / C pillars
			q.paint.box(I, Vector3(sx * w * 0.415, 1.22, z), Vector3(0.05, 0.46, 0.08), paint.darkened(0.08))
		q.trim.box(I, Vector3(sx * (w * 0.5 + 0.003), 0.86, 0.0), Vector3(0.01, 0.025, cls.length * 0.7), CHROME.darkened(0.3))  # belt line
		_mirror(q, Vector3(sx * w * 0.47, 1.02, -0.62), sx)
		for z: float in [-wz, wz]:
			_arch(q, Vector3(0, 0.31, z), 0.38, sx * (w * 0.5 - 0.02), 0.05)
			_wheel(q, Vector3(sx * (w * 0.5 - 0.085), 0.31, z), 0.31, 0.2)
	# Bumpers, grille, lamps, plates.
	q.trim.shell(I, [Vector4(-hl - 0.04, 0.45, w * 0.92, 0.16), Vector4(-hl + 0.12, 0.45, w * 0.98, 0.18)], 6.0, 16, DARK)
	q.trim.shell(I, [Vector4(hl - 0.1, 0.48, w * 0.98, 0.18), Vector4(hl + 0.04, 0.48, w * 0.9, 0.16)], 6.0, 16, DARK)
	q.trim.box(I, Vector3(0, 0.66, -hl - 0.005), Vector3(w * 0.36, 0.12, 0.02), DARK)
	q.chrome.box(I, Vector3(0, 0.66, -hl - 0.012), Vector3(w * 0.38, 0.015, 0.01), CHROME)
	for sx: float in [-1.0, 1.0]:
		q.lamps.shell(Transform3D(Basis.IDENTITY, Vector3(sx * w * 0.34, 0, 0)), [Vector4(-hl - 0.005, 0.7, 0.3, 0.1), Vector4(-hl + 0.06, 0.7, 0.32, 0.12)], 4.0, 10, LAMP)
		q.lamps.shell(Transform3D(Basis.IDENTITY, Vector3(sx * w * 0.36, 0, 0)), [Vector4(hl - 0.06, 0.76, 0.28, 0.12), Vector4(hl + 0.005, 0.76, 0.26, 0.11)], 4.0, 10, TAIL)
		q.lamps.box(I, Vector3(sx * w * 0.47, 0.72, -hl + 0.12), Vector3(0.02, 0.05, 0.1), AMBER)
	q.trim.box(I, Vector3(0, 0.5, -hl - 0.05), Vector3(0.36, 0.1, 0.012), PLATE)
	q.trim.box(I, Vector3(0, 0.58, hl + 0.05), Vector3(0.36, 0.1, 0.012), PLATE)


static func _van(q: Parts, cls: TrafficVehicleClass, paint: Color) -> void:
	var I := Transform3D.IDENTITY
	var w := cls.width
	var hl := cls.length * 0.5
	var wz := hl - 0.72
	# Tall box body with a short sloping nose (city delivery / staff van).
	q.paint.shell(I, [
		Vector4(-hl, 0.62, w * 0.9, 0.55), Vector4(-hl + 0.15, 0.7, w * 0.98, 0.8), Vector4(-hl + 0.55, 0.98, w, 1.4),
		Vector4(-hl + 0.95, 1.06, w, 1.6), Vector4(hl - 0.15, 1.07, w, 1.62), Vector4(hl, 1.06, w * 0.97, 1.58)], 7.0, 24, paint)
	var ws := Transform3D(Basis(Vector3.RIGHT, -0.48), Vector3(0, 1.4, -hl + 0.62))
	q.glass.box(ws, Vector3.ZERO, Vector3(w * 0.86, 0.72, 0.02), GLASS)
	for sx: float in [-1.0, 1.0]:
		q.glass.box(I, Vector3(sx * (w * 0.5 + 0.004), 1.5, 0.35), Vector3(0.01, 0.46, cls.length * 0.62), GLASS)
		for z: float in [-0.35, 0.45, 1.2]:
			q.paint.box(I, Vector3(sx * (w * 0.5 + 0.008), 1.5, z), Vector3(0.012, 0.48, 0.07), paint.darkened(0.12))
		q.trim.box(I, Vector3(sx * (w * 0.5 + 0.01), 1.05, 0.4), Vector3(0.012, 0.025, 1.4), DARK)  # sliding door rail
		q.trim.box(I, Vector3(sx * (w * 0.5 + 0.006), 0.6, 0.0), Vector3(0.012, 0.18, cls.length * 0.8), DARK)  # rubbing strip
		_mirror(q, Vector3(sx * w * 0.5, 1.28, -hl + 0.75), sx)
		for z: float in [-wz, wz]:
			_arch(q, Vector3(0, 0.32, z), 0.39, sx * (w * 0.5 - 0.02), 0.05)
			_wheel(q, Vector3(sx * (w * 0.5 - 0.085), 0.32, z), 0.32, 0.2)
	q.trim.shell(I, [Vector4(-hl - 0.05, 0.46, w * 0.94, 0.2), Vector4(-hl + 0.1, 0.46, w * 0.98, 0.22)], 6.0, 16, DARK)
	q.trim.shell(I, [Vector4(hl - 0.08, 0.46, w * 0.98, 0.2), Vector4(hl + 0.05, 0.46, w * 0.94, 0.18)], 6.0, 16, DARK)
	q.trim.box(I, Vector3(0, 0.75, -hl - 0.01), Vector3(w * 0.5, 0.16, 0.02), DARK)  # grille
	for k in 3:
		q.chrome.box(I, Vector3(0, 0.7 + k * 0.05, -hl - 0.02), Vector3(w * 0.48, 0.012, 0.01), CHROME)
	for sx: float in [-1.0, 1.0]:
		q.lamps.box(I, Vector3(sx * w * 0.37, 0.78, -hl - 0.005), Vector3(0.26, 0.13, 0.03), LAMP)
		q.lamps.box(I, Vector3(sx * w * 0.43, 0.98, hl + 0.005), Vector3(0.14, 0.32, 0.03), TAIL)
	q.glass.box(I, Vector3(0, 1.48, hl + 0.006), Vector3(w * 0.78, 0.5, 0.01), GLASS)
	q.trim.box(I, Vector3(0, 0.6, -hl - 0.06), Vector3(0.36, 0.1, 0.012), PLATE)
	q.trim.box(I, Vector3(0, 0.66, hl + 0.06), Vector3(0.36, 0.1, 0.012), PLATE)


static func _bus(q: Parts, cls: TrafficVehicleClass, paint: Color, variant: int) -> void:
	var I := Transform3D.IDENTITY
	var w := cls.width
	var hl := cls.length * 0.5
	var public := paint.r > 0.5 and paint.g < 0.3  # red = public-bus-inspired
	var band := CREAM if public else (ArtPalette.AWNING_YELLOW if variant % 2 == 0 else ArtPalette.CORAL)
	var lower := paint.darkened(0.12)
	# Tall body, rounded vertical corners, slightly domed roof; the front is
	# a near-flat face with a gentle rake (Sri Lankan bus silhouette).
	q.paint.shell(I, [
		Vector4(-hl, 1.62, w * 0.94, 2.62), Vector4(-hl + 0.08, 1.66, w * 0.99, 2.7), Vector4(-hl + 0.3, 1.68, w, 2.74),
		Vector4(hl - 0.3, 1.68, w, 2.74), Vector4(hl - 0.06, 1.66, w * 0.99, 2.7), Vector4(hl, 1.64, w * 0.95, 2.64)], 9.0, 32, paint)
	q.trim.box(I, Vector3(0, 0.38, 0), Vector3(w * 0.9, 0.26, cls.length - 0.5), DARK)  # chassis skirt shadow
	for sx: float in [-1.0, 1.0]:
		var x := sx * (w * 0.5 + 0.006)
		# Cream band under the windows, darker lower panels with a rub strip.
		q.paint.box(I, Vector3(x, 1.72, 0), Vector3(0.012, 0.26, cls.length - 0.5), band)
		q.paint.box(I, Vector3(x, 0.92, 0.3), Vector3(0.012, 0.62, cls.length - 1.8), lower)
		q.trim.box(I, Vector3(x * 1.002, 1.22, 0.3), Vector3(0.012, 0.06, cls.length - 1.6), DARK)
		# Black window rhythm: glass band with deep mullions.
		q.glass.box(I, Vector3(x, 2.32, 0.4), Vector3(0.012, 0.8, cls.length - 2.0), GLASS)
		var n := 10
		for k in n + 1:
			var z := lerpf(-hl + 1.3, hl - 0.6, float(k) / float(n))
			q.paint.box(I, Vector3(x * 1.003, 2.32, z), Vector3(0.014, 0.82, 0.09), paint.darkened(0.05))
		q.chrome.box(I, Vector3(x * 1.004, 2.73, 0.4), Vector3(0.012, 0.03, cls.length - 2.0), CHROME)  # rain gutter
		_mirror(q, Vector3(sx * (w * 0.5 + 0.1), 2.1, -hl + 0.05), sx)
		_tube(q.chrome, [Vector3(sx * w * 0.47, 2.5, -hl + 0.05), Vector3(sx * (w * 0.5 + 0.14), 2.3, -hl - 0.05), Vector3(sx * (w * 0.5 + 0.15), 2.1, -hl + 0.02)], 0.02, CHROME)
		for z: float in [-hl + 2.0, hl - 2.2]:
			_arch(q, Vector3(0, 0.52, z), 0.62, sx * (w * 0.5 - 0.01), 0.07)
			_wheel(q, Vector3(sx * (w * 0.5 - 0.145), 0.52, z), 0.52, 0.32, 18)
	# Entrance doors on the kerb (left) side: front and middle.
	for z: float in [-hl + 1.0, 0.6]:
		q.trim.box(I, Vector3(-(w * 0.5 + 0.012), 1.38, z), Vector3(0.012, 2.1, 0.86), DARK.lightened(0.08))
		q.glass.box(I, Vector3(-(w * 0.5 + 0.016), 1.75, z), Vector3(0.01, 0.9, 0.7), GLASS)
		q.chrome.box(I, Vector3(-(w * 0.5 + 0.02), 1.3, z - 0.38), Vector3(0.02, 1.2, 0.02), CHROME)  # grab rail
	# Front: split windscreen, destination board, grille, bumper, lamps.
	var front := -hl - 0.012
	q.glass.box(I, Vector3(-w * 0.235, 2.05, front), Vector3(w * 0.44, 1.2, 0.02), GLASS)
	q.glass.box(I, Vector3(w * 0.235, 2.05, front), Vector3(w * 0.44, 1.2, 0.02), GLASS)
	q.trim.box(I, Vector3(0, 2.05, front - 0.004), Vector3(0.06, 1.22, 0.02), DARK)
	q.trim.box(I, Vector3(0, 2.88, front - 0.004), Vector3(w * 0.86, 0.34, 0.02), DARK)
	q.lamps.box(I, Vector3(0, 2.88, front - 0.012), Vector3(w * 0.62, 0.2, 0.01), Color(1.0, 0.58, 0.1))  # destination LEDs
	if public:
		q.paint.box(I, Vector3(0, 1.3, front - 0.004), Vector3(w * 0.96, 0.18, 0.02), band)
	q.trim.box(I, Vector3(0, 0.98, front - 0.006), Vector3(w * 0.5, 0.32, 0.02), DARK)  # grille
	for k in 5:
		q.chrome.box(I, Vector3(0, 0.86 + k * 0.06, front - 0.012), Vector3(w * 0.48, 0.014, 0.01), CHROME)
	q.trim.shell(I, [Vector4(-hl - 0.1, 0.58, w * 0.98, 0.3), Vector4(-hl + 0.05, 0.58, w, 0.32)], 6.0, 16, DARK)
	for sx: float in [-1.0, 1.0]:
		q.chrome.lathe(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(sx * w * 0.36, 1.0, front)), PackedVector2Array([Vector2(0.0, -0.03), Vector2(0.13, -0.02), Vector2(0.13, 0.01)]), 12, CHROME)
		q.lamps.lathe(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(sx * w * 0.36, 1.0, front - 0.012)), PackedVector2Array([Vector2(0.11, 0.0), Vector2(0.0, 0.02)]), 12, LAMP)
		q.lamps.box(I, Vector3(sx * w * 0.44, 1.0, front - 0.01), Vector3(0.1, 0.08, 0.02), AMBER)
		q.lamps.box(I, Vector3(sx * w * 0.42, 1.05, hl + 0.012), Vector3(0.18, 0.38, 0.03), TAIL)
	q.trim.box(I, Vector3(0, 0.7, front - 0.12), Vector3(0.5, 0.12, 0.012), PLATE)
	# Rear: window, engine grille, bumper, plate.
	q.glass.box(I, Vector3(0, 2.25, hl + 0.012), Vector3(w * 0.78, 0.8, 0.02), GLASS)
	q.trim.box(I, Vector3(0, 1.0, hl + 0.012), Vector3(w * 0.6, 0.4, 0.02), DARK)
	q.trim.shell(I, [Vector4(hl - 0.05, 0.55, w, 0.28), Vector4(hl + 0.08, 0.55, w * 0.96, 0.26)], 6.0, 16, DARK)
	q.trim.box(I, Vector3(0, 0.75, hl + 0.1), Vector3(0.5, 0.12, 0.012), PLATE)
	# Roof: vents / hatches and a raised cap line.
	for z: float in [-hl + 2.2, 0.0, hl - 2.2]:
		q.paint.shell(Transform3D(Basis.IDENTITY, Vector3(0, 0, z)), [Vector4(-0.45, 3.02, 0.9, 0.08), Vector4(0.45, 3.02, 0.9, 0.08)], 6.0, 12, paint.lightened(0.18) if public else CREAM)
	if not public:
		# Private buses: roof rack, ladder, decorative side stripes.
		for k in 6:
			q.trim.box(I, Vector3(0, 3.16, lerpf(-hl + 1.2, hl - 1.2, float(k) / 5.0)), Vector3(w * 0.86, 0.05, 0.05), DARK)
		for sx: float in [-1.0, 1.0]:
			q.trim.box(I, Vector3(sx * w * 0.43, 3.14, 0), Vector3(0.05, 0.08, cls.length - 2.4), DARK)
			q.paint.box(I, Vector3(sx * (w * 0.5 + 0.01), 1.44, 0), Vector3(0.012, 0.1, cls.length - 0.8), ArtPalette.ACCENTS[(variant + 2) % ArtPalette.ACCENTS.size()])
			q.paint.box(I, Vector3(sx * (w * 0.5 + 0.01), 1.32, 0), Vector3(0.012, 0.05, cls.length - 0.8), ArtPalette.ACCENTS[(variant + 4) % ArtPalette.ACCENTS.size()])
		for k in 8:
			q.chrome.box(I, Vector3(w * 0.3, 1.4 + k * 0.22, hl + 0.06), Vector3(0.36, 0.025, 0.025), CHROME)
		for sx: float in [0.12, 0.48]:
			q.chrome.box(I, Vector3(w * sx, 2.2, hl + 0.06), Vector3(0.025, 1.7, 0.025), CHROME)


static func _rider(q: Parts, paint: Color) -> void:
	# Stylised commuter: shirt, dark trousers, helmet with visor (static).
	var shirt: Color = ArtPalette.CLOTH[int(absf(paint.r * 7.0 + paint.b * 5.0)) % ArtPalette.CLOTH.size()]
	var trousers := Color(0.16, 0.18, 0.25)
	var skin: Color = ArtPalette.SKIN[int(paint.g * 10.0) % ArtPalette.SKIN.size()]
	var I := Transform3D.IDENTITY
	q.trim.shell(Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 1.33, 0.2)), [Vector4(-0.12, 0.0, 0.34, 0.2), Vector4(0.0, 0.0, 0.4, 0.5), Vector4(0.1, 0.0, 0.36, 0.48)], 3.0, 12, shirt)
	for sx: float in [-1.0, 1.0]:
		_tube(q.trim, [Vector3(sx * 0.2, 1.48, 0.14), Vector3(sx * 0.24, 1.3, -0.1), Vector3(sx * 0.28, 1.12, -0.42)], 0.05, shirt, 6)
		q.trim.sphere(I, Vector3(sx * 0.28, 1.1, -0.46), Vector3(0.045, 0.04, 0.05), skin, 6, 4)
		_tube(q.trim, [Vector3(sx * 0.12, 1.0, 0.28), Vector3(sx * 0.16, 0.98, -0.12), Vector3(sx * 0.17, 0.55, -0.16), Vector3(sx * 0.17, 0.28, -0.12)], 0.065, trousers, 6)
		q.rubber.box(I, Vector3(sx * 0.17, 0.26, -0.18), Vector3(0.1, 0.07, 0.22), TYRE)
	q.trim.sphere(I, Vector3(0, 1.62, 0.16), Vector3(0.06, 0.07, 0.06), skin, 6, 4)
	q.paint.sphere(I, Vector3(0, 1.76, 0.17), Vector3(0.155, 0.15, 0.175), ArtPalette.ACCENTS[(int(paint.g * 10.0)) % 4], 12, 7)
	q.glass.shell(Transform3D(Basis.IDENTITY, Vector3(0, 1.74, 0.0)), [Vector4(-0.02, 0.0, 0.24, 0.1), Vector4(0.06, 0.0, 0.26, 0.11)], 3.0, 10, GLASS)


static func _motorcycle(q: Parts, _cls: TrafficVehicleClass, paint: Color) -> void:
	var I := Transform3D.IDENTITY
	_wheel(q, Vector3(0, 0.3, -0.7), 0.3, 0.09, 16)
	_wheel(q, Vector3(0, 0.3, 0.68), 0.3, 0.11, 16)
	# Frame / engine block / exhaust.
	q.trim.shell(I, [Vector4(-0.25, 0.48, 0.18, 0.22), Vector4(0.25, 0.46, 0.2, 0.26)], 4.0, 12, DARK)
	_tube(q.chrome, [Vector3(0.12, 0.38, -0.1), Vector3(0.16, 0.34, 0.4), Vector3(0.18, 0.42, 0.85)], 0.035, CHROME, 8)
	# Fuel tank, side covers, seat, tail.
	q.paint.shell(I, [Vector4(-0.45, 0.86, 0.18, 0.12), Vector4(-0.3, 0.9, 0.3, 0.2), Vector4(-0.05, 0.9, 0.32, 0.22), Vector4(0.12, 0.86, 0.24, 0.14)], 3.0, 14, paint)
	q.paint.shell(I, [Vector4(0.1, 0.72, 0.22, 0.2), Vector4(0.45, 0.76, 0.18, 0.16)], 4.0, 12, paint)
	q.trim.shell(I, [Vector4(0.08, 0.95, 0.24, 0.06), Vector4(0.35, 0.97, 0.28, 0.08), Vector4(0.7, 0.95, 0.22, 0.06)], 3.0, 12, DARK)
	q.paint.shell(I, [Vector4(0.6, 0.82, 0.14, 0.05), Vector4(0.95, 0.75, 0.12, 0.04)], 4.0, 10, paint)  # rear fender
	# Fork, front fender, headlamp nacelle, handlebar with mirrors.
	for sx: float in [-0.07, 0.07]:
		_tube(q.chrome, [Vector3(sx, 0.3, -0.7), Vector3(sx, 0.62, -0.6), Vector3(sx, 0.98, -0.5)], 0.02, CHROME, 6)
	q.paint.shell(I, [Vector4(-0.95, 0.56, 0.12, 0.04), Vector4(-0.7, 0.64, 0.13, 0.05), Vector4(-0.48, 0.58, 0.12, 0.04)], 4.0, 10, paint)
	q.paint.shell(I, [Vector4(-0.62, 1.0, 0.18, 0.16), Vector4(-0.5, 1.02, 0.22, 0.2)], 3.0, 12, paint)
	q.lamps.lathe(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 1.0, -0.63)), PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.0, 0.015)]), 10, LAMP)
	_tube(q.chrome, [Vector3(-0.34, 1.12, -0.42), Vector3(0, 1.08, -0.5), Vector3(0.34, 1.12, -0.42)], 0.015, CHROME, 6)
	for sx: float in [-1.0, 1.0]:
		_tube(q.chrome, [Vector3(sx * 0.22, 1.1, -0.46), Vector3(sx * 0.28, 1.32, -0.48)], 0.008, CHROME, 4)
		q.trim.sphere(I, Vector3(sx * 0.29, 1.35, -0.48), Vector3(0.05, 0.035, 0.012), DARK, 6, 3)
		q.lamps.box(I, Vector3(sx * 0.1, 0.84, 0.98), Vector3(0.04, 0.03, 0.02), AMBER)
	q.lamps.box(I, Vector3(0, 0.82, 0.96), Vector3(0.1, 0.05, 0.02), TAIL)
	q.trim.box(I, Vector3(0, 0.66, 1.0), Vector3(0.18, 0.1, 0.01), PLATE)
	_rider(q, paint)


static func _tuk(q: Parts, _cls: TrafficVehicleClass, paint: Color) -> void:
	var I := Transform3D.IDENTITY
	var accent := ArtPalette.AWNING_YELLOW
	var canopy := Color(0.05, 0.05, 0.055) if paint.get_luminance() > 0.12 else Color(0.32, 0.3, 0.26)
	# Same family as the hero (lighter detail): cowl, sills, tub, canopy.
	q.paint.shell(I, [Vector4(-1.46, 0.8, 0.5, 0.78), Vector4(-1.4, 0.81, 0.8, 0.9), Vector4(-1.22, 0.83, 1.02, 0.96),
			Vector4(-0.9, 0.82, 1.12, 0.94), Vector4(-0.66, 0.81, 1.14, 0.92)], 4.2, 20, paint)
	q.paint.shell(I, [Vector4(-1.4, 1.27, 0.46, 0.06), Vector4(-1.0, 1.31, 0.96, 0.12), Vector4(-0.74, 1.32, 1.06, 0.12)], 3.0, 12, paint.darkened(0.25))
	q.paint.shell(I, [Vector4(0.28, 0.72, 1.18, 0.54), Vector4(0.9, 0.74, 1.32, 0.6), Vector4(1.3, 0.82, 1.28, 0.76),
			Vector4(1.48, 0.8, 1.02, 0.66)], 3.8, 20, paint)
	q.paint.shell(I, [Vector4(0.42, 0.9, 1.31, 0.07), Vector4(0.9, 0.9, 1.35, 0.07), Vector4(1.3, 0.9, 1.31, 0.07), Vector4(1.48, 0.9, 1.05, 0.07)], 3.8, 20, accent, false)
	q.trim.shell(I, [Vector4(-0.95, 0.36, 0.5, 0.08), Vector4(1.3, 0.38, 1.14, 0.08)], 6.0, 8, DARK)
	for sx: float in [-1.0, 1.0]:
		q.paint.box(I, Vector3(sx * 0.56, 0.52, -0.2), Vector3(0.08, 0.3, 0.95), paint)
		for zz: Array in [[-0.66, -0.86], [1.3, 1.3], [0.4, 0.4]]:
			_tube(q.chrome, [Vector3(sx * 0.6, 0.98, zz[0]), Vector3(sx * 0.7, 1.7, zz[1])], 0.018, CHROME, 5)
		_arch(q, Vector3(0, 0.21, 1.0), 0.27, sx * 0.575, 0.08)
	var rows: Array = []
	for z: float in [-1.08, -0.98, -0.7, 0.3, 1.38]:
		var droop := 0.1 if z < -1.0 else (0.03 if z < -0.9 else 0.0)
		var ring := PackedVector3Array()
		for k in 11:
			var a := PI * float(k) / 10.0
			ring.append(Vector3(cos(a) * 0.72, 1.7 + pow(sin(a), 0.6) * 0.2 - droop, z))
		rows.append(ring)
	q.trim.grid(rows, canopy, false, Vector3(0, 1.2, 0.2))
	var under: Array = []
	for r: PackedVector3Array in rows:
		var ring := PackedVector3Array()
		for v in r:
			ring.append(v + Vector3(0, -0.025, 0))
		under.append(ring)
	q.trim.grid(under, canopy.darkened(0.3), false, Vector3(0, 2.6, 0.2))
	var ws := Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, 1.6, -0.86))
	q.glass.box(ws, Vector3.ZERO, Vector3(1.0, 0.56, 0.02), GLASS)
	q.chrome.lathe(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.12, -1.45)), PackedVector2Array([Vector2(0.0, -0.06), Vector2(0.11, -0.04), Vector2(0.12, 0.03)]), 12, CHROME)
	q.lamps.lathe(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.12, -1.45)), PackedVector2Array([Vector2(0.1, 0.03), Vector2(0.0, 0.05)]), 12, LAMP)
	for sx: float in [-0.48, 0.48]:
		q.lamps.box(I, Vector3(sx, 0.76, 1.49), Vector3(0.16, 0.1, 0.03), TAIL)
	q.trim.box(I, Vector3(0, 0.6, 1.5), Vector3(0.34, 0.12, 0.012), PLATE)
	q.trim.shell(I, [Vector4(0.6, 0.79, 1.1, 0.12), Vector4(1.06, 0.79, 1.1, 0.12)], 3.0, 10, Color(0.25, 0.07, 0.06))
	q.trim.shell(Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, 1.0, 1.14)), [Vector4(-0.05, 0.0, 1.04, 0.36), Vector4(0.05, 0.0, 1.06, 0.38)], 3.4, 12, Color(0.25, 0.07, 0.06))
	# Driver silhouette (static, stylised).
	var shirt: Color = ArtPalette.CLOTH[int(paint.r * 9.0 + paint.g * 3.0) % ArtPalette.CLOTH.size()]
	var skin: Color = ArtPalette.SKIN[int(paint.b * 10.0) % ArtPalette.SKIN.size()]
	q.trim.shell(Transform3D(Basis.IDENTITY, Vector3(0, 1.17, -0.26)), [Vector4(-0.12, 0.0, 0.36, 0.42), Vector4(0.12, 0.0, 0.38, 0.46)], 3.0, 12, shirt)
	q.trim.sphere(I, Vector3(0, 1.52, -0.28), Vector3(0.1, 0.12, 0.11), skin, 10, 6)
	q.trim.sphere(I, Vector3(0, 1.58, -0.25), Vector3(0.105, 0.07, 0.105), Color(0.07, 0.06, 0.06), 10, 4)
	for sx: float in [-1.0, 1.0]:
		_tube(q.trim, [Vector3(sx * 0.18, 1.32, -0.22), Vector3(sx * 0.22, 1.18, -0.45), Vector3(sx * 0.3, 1.16, -0.6)], 0.05, shirt, 5)
	_wheel(q, Vector3(0, 0.21, -1.0), 0.21, 0.11, 14)
	_wheel(q, Vector3(-0.575, 0.21, 1.0), 0.21, 0.14, 14)
	_wheel(q, Vector3(0.575, 0.21, 1.0), 0.21, 0.14, 14)
