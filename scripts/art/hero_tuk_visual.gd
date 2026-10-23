class_name HeroTukVisual
extends Node3D
## The player's tuk, final-direction art (v0.03B1 "hero tuk v2"). An original
## Sri Lankan three-wheeler design — deep teal body, dark canopy, warm yellow
## accent, black trim, chrome details — NOT a copy of any manufacturer's model
## and with no badges.
##
## Lives under TukController's `Visual` node and only READS the controller:
## the physics body, collision shape, mass and tuning are untouched. The
## controller already drives Visual/FrontSteer (steer), wheel mounts
## (suspension) and Spin (rotation); this adds the body, wheels, a fork and
## mudguard that steer with FrontSteer, a handlebar that follows it,
## brake/head-light hooks and a seated driver. Art follows physics.
##
## v2: smooth-shaded curved panels (ArtMesh.shell/sweep/lathe) instead of
## boxes, and real material separation: glossy paint, matte canopy fabric,
## rubber tyres, chrome, see-through windscreen, vinyl seats, emissive lamps.

const TEAL := Color(0.02, 0.36, 0.4)
const TEAL_DEEP := Color(0.015, 0.25, 0.28)
const ACCENT := Color(0.98, 0.72, 0.14)
const TRIM := Color(0.05, 0.05, 0.055)
const CANOPY := Color(0.045, 0.048, 0.052)
const CHROME := Color(0.86, 0.87, 0.89)
const VINYL := Color(0.3, 0.07, 0.06)
const TYRE := Color(0.07, 0.07, 0.075)
const PLATE := Color(0.96, 0.94, 0.86)
const AMBER := Color(1.0, 0.55, 0.08)

## Wheel geometry matches the physics rig (player_tuk.tscn): r 0.21 m,
## front at z −1.0, rear at z +1.0, rear track ±0.575.
const WHEEL_R := 0.21

var tuk: TukController
var headlights_on := false
var driver: CharacterRig
var body_instance: MeshInstance3D
var handlebar: Node3D
## Fork + front mudguard; parented to FrontSteer so they turn with the wheel.
var fork_instance: MeshInstance3D
var _brake_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
var _front_steer: Node3D
var _triangles := 0
var _material_kinds: Dictionary = {}


func _ready() -> void:
	tuk = get_parent().get_parent() as TukController
	var visual := get_parent()
	_front_steer = visual.get_node_or_null("FrontSteer")
	# Retire the v0.01 placeholder boxes (keep the controller's wheel nodes).
	for c in visual.get_children():
		if c is MeshInstance3D:
			c.queue_free()
	_build_body()
	_build_fork()
	_build_wheels(visual)
	_build_handlebar()
	_build_driver()


func triangle_count() -> int:
	return _triangles


## Distinct shared material kinds used by the hero art (test hook).
func material_kinds() -> PackedStringArray:
	return PackedStringArray(_material_kinds.keys())


func _commit(parts: Dictionary, into: ArrayMesh) -> void:
	for kind: StringName in parts:
		var m: ArtMesh = parts[kind]
		if m.verts.is_empty():
			continue
		m.commit(ArtMaterials.get_material(kind), into)
		_triangles += m.triangle_count()
		_material_kinds[String(kind)] = true


static func _arc_frames(centre: Vector3, radius: float, a0: float, a1: float, steps: int, x: float) -> Array:
	# Frames around the X axis (wheel arches / mudguards); profile X → world X.
	var out: Array = []
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / float(steps))
		var p := centre + Vector3(x, sin(a) * radius, -cos(a) * radius)
		var tangent := Vector3(0, cos(a), sin(a))
		var radial := Vector3(0, sin(a), -cos(a))
		out.append(Transform3D(Basis(Vector3.RIGHT, radial, tangent), p))
	return out


static func _line_frames(points: Array, up_hint := Vector3.UP) -> Array:
	var out: Array = []
	for i in points.size():
		var p: Vector3 = points[i]
		var t: Vector3 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var up := up_hint if absf(t.dot(up_hint)) < 0.95 else Vector3.FORWARD
		var x := up.cross(t).normalized()
		var y := t.cross(x).normalized()
		out.append(Transform3D(Basis(x, y, t), p))
	return out


func _tube(m: ArtMesh, points: Array, r: float, color: Color, seg: int = 8) -> void:
	var prof := PackedVector2Array()
	for k in seg:
		var a := TAU * float(k) / float(seg)
		prof.append(Vector2(cos(a), sin(a)) * r)
	m.sweep(_line_frames(points), prof, color)


func _build_body() -> void:
	var paint := ArtMesh.new()
	var trim := ArtMesh.new()
	var chrome := ArtMesh.new()
	var fabric := ArtMesh.new()
	var vinyl := ArtMesh.new()
	var glass := ArtMesh.new()
	var rubber := ArtMesh.new()
	var lamps := ArtMesh.new()
	var I := Transform3D.IDENTITY

	# --- chassis / floor pan (mostly hidden; grounds the body visually) ---
	trim.shell(I, [Vector4(-0.95, 0.36, 0.5, 0.08), Vector4(-0.6, 0.36, 1.0, 0.08), Vector4(1.3, 0.38, 1.14, 0.08)], 6.0, 12, TRIM)

	# --- front cowl: the tuk's face. Rounded shield, wide at the floor,
	# rising and narrowing to the windscreen; headlamp on its brow. ---
	paint.shell(I, [
		Vector4(-1.46, 0.8, 0.5, 0.78), Vector4(-1.43, 0.81, 0.74, 0.88), Vector4(-1.36, 0.82, 0.9, 0.94),
		Vector4(-1.22, 0.83, 1.02, 0.96), Vector4(-1.02, 0.83, 1.1, 0.96), Vector4(-0.8, 0.82, 1.14, 0.94),
		Vector4(-0.66, 0.81, 1.14, 0.92)], 4.2, 32, TEAL, true)
	# Panel separation: a dark seam where the cowl meets the cabin sides.
	trim.shell(I, [Vector4(-0.67, 0.82, 1.175, 0.975), Vector4(-0.64, 0.82, 1.175, 0.975)], 3.2, 28, TRIM, false)
	# Yellow accent chevron band across the nose and a deep-teal brow.
	paint.shell(I, [Vector4(-1.44, 0.74, 0.764, 0.06), Vector4(-1.36, 0.74, 0.924, 0.06), Vector4(-1.0, 0.74, 1.124, 0.06), Vector4(-0.7, 0.74, 1.156, 0.06)], 4.2, 32, ACCENT, false)
	# Hood rising from the cowl brow to the windscreen base.
	paint.shell(I, [Vector4(-1.4, 1.27, 0.46, 0.06), Vector4(-1.2, 1.3, 0.82, 0.1), Vector4(-0.96, 1.32, 1.0, 0.12), Vector4(-0.74, 1.32, 1.08, 0.12)], 3.0, 18, TEAL_DEEP)
	# Front bumper: chrome bar on short stays + rubber end caps.
	_tube(chrome, [Vector3(-0.4, 0.5, -1.36), Vector3(-0.2, 0.47, -1.47), Vector3(0.2, 0.47, -1.47), Vector3(0.4, 0.5, -1.36)], 0.022, CHROME)
	for sx: float in [-0.4, 0.4]:
		rubber.sphere(I, Vector3(sx, 0.5, -1.36), Vector3(0.035, 0.035, 0.035), TYRE, 8, 5)
	# Front number plate (fictional, plain) under the accent band.
	paint.box(I, Vector3(0, 0.6, -1.455), Vector3(0.3, 0.1, 0.012), PLATE)
	trim.box(I, Vector3(0, 0.6, -1.452), Vector3(0.32, 0.12, 0.008), TRIM)

	# --- headlamp: chrome bucket on the brow, glass lens is its own light ---
	var hl := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.12, -1.45))
	chrome.lathe(hl, PackedVector2Array([Vector2(0.0, -0.07), Vector2(0.09, -0.06), Vector2(0.125, -0.02), Vector2(0.13, 0.03), Vector2(0.118, 0.045)]), 18, CHROME)
	# Indicators on chrome stalks either side of the lamp.
	for sx: float in [-1.0, 1.0]:
		_tube(chrome, [Vector3(sx * 0.12, 1.1, -1.42), Vector3(sx * 0.3, 1.08, -1.4)], 0.01, CHROME, 6)
		lamps.sphere(I, Vector3(sx * 0.33, 1.08, -1.4), Vector3(0.045, 0.038, 0.055), AMBER, 10, 6)

	# --- windscreen: framed, see-through, slightly raked ---
	var ws := Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, 1.6, -0.86))
	glass.box(ws, Vector3.ZERO, Vector3(1.0, 0.56, 0.012), Color(0.7, 0.82, 0.86, 0.28))
	var wpts: Array = []
	for q: Vector2 in [Vector2(-0.51, -0.29), Vector2(-0.51, 0.29), Vector2(0.51, 0.29), Vector2(0.51, -0.29)]:
		wpts.append(ws * Vector3(q.x, q.y, 0))
	_tube(trim, [wpts[0], wpts[1]], 0.026, TRIM, 6)
	_tube(trim, [wpts[1], wpts[2]], 0.026, TRIM, 6)
	_tube(trim, [wpts[2], wpts[3]], 0.026, TRIM, 6)
	_tube(trim, [wpts[3], wpts[0]], 0.026, TRIM, 6)
	# Wiper parked at the base.
	_tube(trim, [ws * Vector3(-0.05, -0.26, -0.02), ws * Vector3(0.38, -0.22, -0.02)], 0.008, TRIM, 4)

	# --- dashboard silhouette behind the screen, round speedo ---
	trim.shell(I, [Vector4(-0.84, 1.3, 0.96, 0.12), Vector4(-0.64, 1.28, 1.06, 0.14)], 3.0, 16, TRIM)
	chrome.lathe(Transform3D(Basis(Vector3.RIGHT, PI * 0.38), Vector3(0, 1.37, -0.7)), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.065, 0.02), Vector2(0.0, 0.024)]), 14, CHROME)

	# --- cabin sides: low sills joining the cowl to the rear tub ---
	for sx: float in [-1.0, 1.0]:
		paint.shell(Transform3D(Basis.IDENTITY, Vector3(sx * 0.56, 0, 0)), [
			Vector4(-0.68, 0.56, 0.08, 0.38), Vector4(-0.3, 0.52, 0.08, 0.3), Vector4(0.3, 0.52, 0.08, 0.3)], 4.0, 10, TEAL)
		trim.shell(Transform3D(Basis.IDENTITY, Vector3(sx * 0.6, 0, 0)), [Vector4(-0.6, 0.38, 0.05, 0.06), Vector4(0.36, 0.38, 0.05, 0.06)], 4.0, 8, TRIM)
		# Footboard edge + grab handle for the driver.
		_tube(chrome, [Vector3(sx * 0.6, 0.98, -0.62), Vector3(sx * 0.6, 1.08, -0.5), Vector3(sx * 0.6, 1.06, -0.36)], 0.012, CHROME, 6)

	# --- rear tub: rounded, wider body over the rear axle; open passenger
	# sides above the sill line. Wheels show below it. ---
	paint.shell(I, [
		Vector4(0.28, 0.72, 1.18, 0.54), Vector4(0.5, 0.73, 1.28, 0.58), Vector4(0.9, 0.74, 1.32, 0.6),
		Vector4(1.12, 0.78, 1.32, 0.68), Vector4(1.3, 0.82, 1.28, 0.76), Vector4(1.42, 0.82, 1.18, 0.74),
		Vector4(1.48, 0.8, 1.02, 0.66)], 3.8, 32, TEAL)
	# Rear engine cover rising behind the backrest (the classic tuk hump).
	paint.shell(I, [Vector4(1.18, 1.16, 1.0, 0.06), Vector4(1.3, 1.19, 1.12, 0.1), Vector4(1.44, 1.16, 1.0, 0.08)], 3.0, 20, TEAL_DEEP)
	# Wraparound yellow accent belt and a black rub strip below it.
	paint.shell(I, [Vector4(0.42, 0.9, 1.31, 0.075), Vector4(0.9, 0.9, 1.35, 0.075), Vector4(1.12, 0.9, 1.35, 0.075),
		Vector4(1.3, 0.9, 1.31, 0.075), Vector4(1.42, 0.9, 1.21, 0.075), Vector4(1.48, 0.9, 1.05, 0.075)], 3.8, 32, ACCENT, false)
	trim.shell(I, [Vector4(0.42, 0.56, 1.286, 0.04), Vector4(0.9, 0.56, 1.326, 0.04), Vector4(1.12, 0.56, 1.326, 0.04),
		Vector4(1.3, 0.56, 1.286, 0.04), Vector4(1.42, 0.56, 1.186, 0.04), Vector4(1.48, 0.56, 1.026, 0.04)], 3.8, 32, TRIM, false)
	# Rear mudguards hugging the rear wheels (dark, below the tub).
	var guard_prof := ArtMesh.superellipse(Vector2(0.1, 0.018), 4.0, 10)
	for sx: float in [-0.575, 0.575]:
		rubber.sweep(_arc_frames(Vector3(0, WHEEL_R, 1.0), WHEEL_R + 0.05, -0.25, 1.75, 10, sx), guard_prof, TRIM)
		trim.box(I, Vector3(sx, 0.2, 1.3), Vector3(0.16, 0.2, 0.012), TRIM)  # mudflap
	# Tail lamps: chrome bezels, red lenses (lens = brake light hook).
	for sx: float in [-0.48, 0.48]:
		chrome.shell(Transform3D(Basis.IDENTITY, Vector3(sx, 0, 0)), [Vector4(1.455, 0.76, 0.2, 0.13), Vector4(1.495, 0.76, 0.2, 0.13)], 4.0, 12, CHROME)
	# Rear plate with border + reflectors.
	paint.box(I, Vector3(0, 0.6, 1.505), Vector3(0.34, 0.12, 0.012), PLATE)
	trim.box(I, Vector3(0, 0.6, 1.5), Vector3(0.36, 0.14, 0.008), TRIM)
	for sx: float in [-0.3, 0.3]:
		lamps.box(I, Vector3(sx, 0.6, 1.495), Vector3(0.06, 0.03, 0.01), Color(0.9, 0.12, 0.08))
	# Rear chrome grab bar / bumper.
	_tube(chrome, [Vector3(-0.5, 0.46, 1.42), Vector3(-0.42, 0.42, 1.56), Vector3(0.42, 0.42, 1.56), Vector3(0.5, 0.46, 1.42)], 0.02, CHROME)

	# --- seats: vinyl bench with two cushions + piping, saddle for the driver ---
	vinyl.shell(I, [Vector4(0.58, 0.79, 1.1, 0.12), Vector4(0.82, 0.8, 1.12, 0.14), Vector4(1.06, 0.79, 1.1, 0.12)], 3.0, 18, VINYL)
	for sx: float in [-0.27, 0.27]:
		vinyl.shell(Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(sx, 1.0, 1.14)), [Vector4(-0.05, 0.0, 0.5, 0.36), Vector4(0.05, 0.0, 0.52, 0.38)], 3.4, 18, VINYL)
	trim.shell(I, [Vector4(0.56, 0.735, 1.12, 0.02), Vector4(1.08, 0.735, 1.12, 0.02)], 4.0, 12, TRIM, false)
	vinyl.shell(I, [Vector4(-0.46, 0.84, 0.26, 0.08), Vector4(-0.3, 0.86, 0.34, 0.11), Vector4(-0.1, 0.84, 0.32, 0.09)], 3.0, 16, VINYL)
	trim.shell(I, [Vector4(-0.42, 0.6, 0.26, 0.42), Vector4(-0.12, 0.6, 0.28, 0.42)], 4.0, 10, TRIM)  # saddle box
	# Driver's back-rest bar (classic tuk partition rail).
	_tube(chrome, [Vector3(-0.55, 1.12, 0.06), Vector3(0.55, 1.12, 0.06)], 0.016, CHROME, 6)

	# --- canopy: roof supports, curved fabric roof with a front lip, side
	# curtain rolls, rolled rear canvas (open back: passenger stays visible) ---
	for p: Array in [[Vector3(-0.56, 1.0, -0.66), Vector3(-0.66, 1.7, -0.86)], [Vector3(0.56, 1.0, -0.66), Vector3(0.66, 1.7, -0.86)],
			[Vector3(-0.64, 1.0, 1.3), Vector3(-0.7, 1.7, 1.3)], [Vector3(0.64, 1.0, 1.3), Vector3(0.7, 1.7, 1.3)],
			[Vector3(-0.64, 0.95, 0.4), Vector3(-0.7, 1.7, 0.4)], [Vector3(0.64, 0.95, 0.4), Vector3(0.7, 1.7, 0.4)]]:
		_tube(chrome, p, 0.02, CHROME, 8)
	var roof_rows: Array = []
	var roof_in: Array = []
	var zs := [-1.08, -1.02, -0.92, -0.7, -0.3, 0.2, 0.7, 1.1, 1.3, 1.38]
	for i in zs.size():
		var z: float = zs[i]
		var droop: float = 0.0 if i > 2 else [0.12, 0.05, 0.015][i]  # front visor curls down
		var ring_o := PackedVector3Array()
		var ring_i := PackedVector3Array()
		for k in 15:
			var a := PI * float(k) / 14.0
			var x := cos(a) * 0.72
			var y: float = 1.7 + pow(sin(a), 0.6) * 0.2 - droop
			ring_o.append(Vector3(x, y, z))
			ring_i.append(Vector3(x * 0.985, y - 0.025, z))
		roof_rows.append(ring_o)
		roof_in.append(ring_i)
	fabric.grid(roof_rows, CANOPY, false, Vector3(0, 1.2, 0.2))
	fabric.grid(roof_in, CANOPY.darkened(0.25), false, Vector3(0, 2.6, 0.2))
	# Canopy edge piping + yellow front valance stripe.
	for sx: float in [-1.0, 1.0]:
		_tube(trim, [Vector3(sx * 0.72, 1.7, -0.92), Vector3(sx * 0.72, 1.7, 1.38)], 0.016, TRIM, 6)
		var roll := PackedVector2Array()
		for k in 10:
			var a := TAU * float(k) / 10.0
			roll.append(Vector2(cos(a), sin(a)) * 0.05)
		fabric.sweep(_line_frames([Vector3(sx * 0.73, 1.64, -0.5), Vector3(sx * 0.73, 1.64, 1.25)]), roll, CANOPY.lightened(0.08))
		for z: float in [-0.2, 0.5, 1.05]:
			fabric.box(I, Vector3(sx * 0.735, 1.64, z), Vector3(0.012, 0.13, 0.03), ACCENT.darkened(0.3))  # straps
	paint.shell(I, [Vector4(-1.04, 1.62, 1.42, 0.05), Vector4(-1.0, 1.62, 1.43, 0.05)], 4.0, 16, ACCENT, false)
	var rear_roll := PackedVector2Array()
	for k in 12:
		var a := TAU * float(k) / 12.0
		rear_roll.append(Vector2(cos(a), sin(a)) * 0.065)
	fabric.sweep(_line_frames([Vector3(-0.66, 1.68, 1.36), Vector3(0.66, 1.68, 1.36)]), rear_roll, CANOPY.lightened(0.07))

	# --- assemble the body ---
	var mesh := ArrayMesh.new()
	_commit({&"paint": paint, &"plaster": trim, &"chrome": chrome, &"fabric": fabric, &"vinyl": vinyl,
			&"rubber": rubber, &"emissive": lamps, &"glass_clear": glass}, mesh)
	body_instance = MeshInstance3D.new()
	body_instance.name = "HeroBody"
	body_instance.mesh = mesh
	add_child(body_instance)
	_build_lights()


## Lights on their own instances so state hooks can change emission.
func _build_lights() -> void:
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(1.0, 0.97, 0.88)
	_head_mat.emission_enabled = true
	_head_mat.emission = Color(1.0, 0.95, 0.8)
	_head_mat.emission_energy_multiplier = 0.4
	_head_mat.roughness = 0.05
	var lens := ArtMesh.new()
	lens.lathe(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.12, -1.45)),
			PackedVector2Array([Vector2(0.112, 0.03), Vector2(0.09, 0.05), Vector2(0.0, 0.058)]), 18, Color.WHITE)
	_add_light("Headlight", lens, _head_mat)
	_brake_mat = StandardMaterial3D.new()
	_brake_mat.albedo_color = Color(0.6, 0.04, 0.03)
	_brake_mat.emission_enabled = true
	_brake_mat.emission = Color(1.0, 0.1, 0.06)
	_brake_mat.emission_energy_multiplier = 0.25
	_brake_mat.roughness = 0.1
	var tail := ArtMesh.new()
	for sx: float in [-0.48, 0.48]:
		tail.shell(Transform3D(Basis.IDENTITY, Vector3(sx, 0, 0)), [Vector4(1.49, 0.76, 0.17, 0.1), Vector4(1.51, 0.76, 0.15, 0.085)], 4.0, 12, Color.WHITE)
	_add_light("TailLights", tail, _brake_mat)
	_material_kinds["lamp_head"] = true
	_material_kinds["lamp_brake"] = true


func _add_light(node_name: String, m: ArtMesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = m.commit(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_triangles += m.triangle_count()


## Front fork + mudguard under FrontSteer: they turn with the steered wheel.
func _build_fork() -> void:
	if _front_steer == null:
		return
	var paint := ArtMesh.new()
	var chrome := ArtMesh.new()
	# FrontSteer sits at the wheel centre (0, 0.21, −1.0); local coordinates.
	for sx: float in [-0.085, 0.085]:
		_tube(chrome, [Vector3(sx, 0.0, 0.0), Vector3(sx * 0.8, 0.32, -0.1), Vector3(sx * 0.6, 0.62, -0.2)], 0.022, CHROME, 8)
	chrome.lathe(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), PackedVector2Array([Vector2(0.0, -0.1), Vector2(0.03, -0.1), Vector2(0.03, 0.1), Vector2(0.0, 0.1)]), 8, CHROME)  # axle
	var prof := ArtMesh.superellipse(Vector2(0.085, 0.016), 3.0, 12)
	paint.sweep(_arc_frames(Vector3.ZERO, WHEEL_R + 0.045, -0.35, 1.9, 12, 0.0), prof, TEAL)
	var mesh := ArrayMesh.new()
	_commit({&"paint": paint, &"chrome": chrome}, mesh)
	fork_instance = MeshInstance3D.new()
	fork_instance.name = "HeroFork"
	fork_instance.mesh = mesh
	_front_steer.add_child(fork_instance)


func _wheel_mesh(width: float) -> ArrayMesh:
	var rubber := ArtMesh.new()
	var chrome := ArtMesh.new()
	var paint := ArtMesh.new()
	var I := Transform3D.IDENTITY
	var hw := width * 0.5
	# Tyre: rounded sidewalls (lathe about the axle = local Y).
	rubber.lathe(I, PackedVector2Array([Vector2(0.125, -hw * 0.82), Vector2(0.17, -hw * 0.98), Vector2(0.2, -hw * 0.9),
			Vector2(WHEEL_R, -hw * 0.55), Vector2(WHEEL_R, hw * 0.55), Vector2(0.2, hw * 0.9), Vector2(0.17, hw * 0.98),
			Vector2(0.125, hw * 0.82)]), 24, TYRE)
	# Tread blocks (shallow).
	for k in 18:
		var a := TAU * float(k) / 18.0
		rubber.box(Transform3D(Basis(Vector3.UP, a), Vector3.ZERO), Vector3(WHEEL_R + 0.003, 0, 0), Vector3(0.008, width * 0.7, 0.03), TYRE.darkened(0.3), 1)
	# Steel rim (painted) + chrome hubcap with lug bumps.
	paint.lathe(I, PackedVector2Array([Vector2(0.126, -hw * 0.8), Vector2(0.11, -hw * 0.6), Vector2(0.06, -hw * 0.5),
			Vector2(0.06, hw * 0.5), Vector2(0.11, hw * 0.6), Vector2(0.126, hw * 0.8)]), 20, Color(0.82, 0.82, 0.8))
	for side: float in [-1.0, 1.0]:
		chrome.lathe(Transform3D(Basis(Vector3.RIGHT, 0.0 if side > 0.0 else PI), Vector3.ZERO),
				PackedVector2Array([Vector2(0.065, hw * 0.5), Vector2(0.06, hw * 0.62), Vector2(0.035, hw * 0.75), Vector2(0.0, hw * 0.78)]), 14, CHROME)
		for k in 5:
			var a := TAU * float(k) / 5.0
			chrome.sphere(I, Vector3(cos(a) * 0.045, side * hw * 0.58, sin(a) * 0.045), Vector3(0.008, 0.008, 0.008), CHROME, 6, 3)
	var mesh := ArrayMesh.new()
	_commit({&"rubber": rubber, &"paint": paint, &"chrome": chrome}, mesh)
	return mesh


func _build_wheels(visual: Node) -> void:
	var front := _wheel_mesh(0.11)
	var rear := _wheel_mesh(0.14)
	for path in ["FrontSteer/Spin", "RearLeft/Spin", "RearRight/Spin"]:
		var spin := visual.get_node_or_null(path) as Node3D
		if spin == null:
			continue
		var old := spin.get_node_or_null("Wheel")
		if old != null:
			old.queue_free()
		var w := MeshInstance3D.new()
		w.name = "HeroWheel"
		w.mesh = front if path.begins_with("Front") else rear
		w.rotation_degrees = Vector3(0, 0, 90)  # lathe axis (Y) → the axle (X)
		spin.add_child(w)


## Handlebar + steering column: a separate node that copies FrontSteer's yaw.
func _build_handlebar() -> void:
	handlebar = Node3D.new()
	handlebar.name = "Handlebar"
	handlebar.position = Vector3(0, 1.12, -0.66)
	add_child(handlebar)
	var chrome := ArtMesh.new()
	var rubber := ArtMesh.new()
	_tube(chrome, [Vector3(0, -0.2, -0.06), Vector3(0, 0.0, 0.0)], 0.024, CHROME, 8)  # column
	_tube(chrome, [Vector3(-0.32, 0.06, 0.1), Vector3(-0.18, 0.03, 0.03), Vector3(0, 0.0, 0.0), Vector3(0.18, 0.03, 0.03), Vector3(0.32, 0.06, 0.1)], 0.016, CHROME, 8)
	for sx: float in [-1.0, 1.0]:
		_tube(rubber, [Vector3(sx * 0.3, 0.055, 0.09), Vector3(sx * 0.4, 0.07, 0.13)], 0.022, TRIM, 8)  # grips
		_tube(chrome, [Vector3(sx * 0.22, 0.05, 0.02), Vector3(sx * 0.34, 0.035, 0.0)], 0.007, CHROME, 5)  # levers
		# Mirrors on stalks.
		_tube(chrome, [Vector3(sx * 0.24, 0.04, 0.05), Vector3(sx * 0.3, 0.2, 0.0), Vector3(sx * 0.38, 0.28, -0.02)], 0.008, CHROME, 5)
		chrome.lathe(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(sx * 0.4, 0.3, -0.02)),
				PackedVector2Array([Vector2(0.0, -0.012), Vector2(0.055, -0.01), Vector2(0.06, 0.006), Vector2(0.0, 0.012)]), 14, TRIM)
	var mesh := ArrayMesh.new()
	_commit({&"chrome": chrome, &"rubber": rubber}, mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	handlebar.add_child(mi)


func _build_driver() -> void:
	driver = CharacterRig.new(1)
	driver.name = "Driver"
	driver.mode = CharacterRig.Mode.DRIVE
	# Hips over the saddle (rig origin = feet; hips rest ≈ 0.91 m).
	driver.position = Vector3(0, 0.9 - 0.91, -0.28)
	add_child(driver)


func _process(delta: float) -> void:
	var ps := PerfSections.begin()
	_process_body(delta)
	PerfSections.end(PerfSections.HERO_VISUAL, ps)


func _process_body(delta: float) -> void:
	if _front_steer != null and handlebar != null:
		handlebar.rotation.y = _front_steer.rotation.y
	if tuk != null:
		var braking := tuk.input.brake > 0.1 and tuk.forward_speed > 0.3
		_brake_mat.emission_energy_multiplier = 2.6 if braking else 0.25
	_head_mat.emission_energy_multiplier = 2.0 if headlights_on else 0.4
	if driver != null:
		var cam := get_viewport().get_camera_3d()
		driver.animate(delta, cam.global_position if cam != null else global_position)
