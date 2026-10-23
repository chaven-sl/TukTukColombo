class_name HeroTukVisual
extends Node3D
## The player's tuk, final-direction art (v0.03B). An original Sri Lankan
## three-wheeler design — deep teal body, dark canopy, warm yellow accent,
## black trim, chrome details — NOT a copy of any manufacturer's model.
##
## Lives under TukController's `Visual` node and only READS the controller:
## the physics body, collision shape, mass and tuning are untouched. The
## controller already drives Visual/FrontSteer (steer), wheel mounts
## (suspension) and Spin (rotation); this adds the body, wheels, a handlebar
## that follows FrontSteer, brake/head-light hooks and a seated driver.
## Art follows physics — never the other way round.

const TEAL := Color(0.03, 0.34, 0.38)
const TEAL_DEEP := Color(0.02, 0.24, 0.27)
const ACCENT := Color(0.96, 0.74, 0.18)
const TRIM := Color(0.06, 0.06, 0.07)
const CANOPY := Color(0.1, 0.11, 0.12)
const CHROME := Color(0.82, 0.83, 0.85)
const VINYL := Color(0.28, 0.08, 0.07)

var tuk: TukController
var headlights_on := false
var driver: CharacterRig
var body_instance: MeshInstance3D
var handlebar: Node3D
var _brake_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
var _front_steer: Node3D
var _triangles := 0


func _ready() -> void:
	tuk = get_parent().get_parent() as TukController
	var visual := get_parent()
	_front_steer = visual.get_node_or_null("FrontSteer")
	# Retire the v0.01 placeholder boxes (keep the controller's wheel nodes).
	for c in visual.get_children():
		if c is MeshInstance3D:
			c.queue_free()
	_build_body()
	_build_wheels(visual)
	_build_handlebar()
	_build_driver()


func triangle_count() -> int:
	return _triangles


func _build_body() -> void:
	var paint := ArtMesh.new()
	var dark := ArtMesh.new()
	var metal := ArtMesh.new()
	var glass := ArtMesh.new()
	var I := Transform3D.IDENTITY
	# --- floor pan / chassis ---
	dark.box(I, Vector3(0, 0.36, 0.05), Vector3(1.18, 0.07, 2.45), TRIM)
	# --- front cowl: a lofted, rounded nose that widens towards the cabin ---
	paint.loft(I, [Vector4(-1.35, 0.74, 0.5, 0.56), Vector4(-1.26, 0.76, 0.66, 0.7), Vector4(-1.08, 0.78, 0.86, 0.8),
			Vector4(-0.86, 0.8, 1.04, 0.86), Vector4(-0.6, 0.8, 1.14, 0.86)], 0.55, TEAL)
	# Upper dash cowl under the windscreen.
	paint.loft(I, [Vector4(-0.98, 1.12, 0.8, 0.12), Vector4(-0.62, 1.16, 1.08, 0.18)], 0.4, TEAL_DEEP)
	# Black bumper belt and yellow accent across the nose.
	dark.loft(I, [Vector4(-1.38, 0.5, 0.58, 0.1), Vector4(-1.12, 0.5, 0.86, 0.1)], 0.5, TRIM)
	paint.box(I, Vector3(0, 0.84, -1.36), Vector3(0.44, 0.045, 0.02), ACCENT)
	# Front mudguard arching over the front wheel.
	for k in 5:
		var a := lerpf(-1.0, 1.0, float(k) / 4.0)
		var xf := Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, 0.21, -1.0))
		paint.box(xf, Vector3(0, 0.29, 0), Vector3(0.2, 0.025, 0.13), TEAL)
	# Headlamp: chrome bezel + lens (lens on its own material for the hook).
	metal.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.0, -1.31)), Vector3.ZERO, 0.115, 0.06, 12, CHROME)
	# Indicators.
	for sx: float in [-0.3, 0.3]:
		dark.box(I, Vector3(sx, 0.98, -1.27), Vector3(0.08, 0.05, 0.05), Color(0.95, 0.55, 0.1))
	# --- windscreen + frame ---
	var ws := Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(0, 1.38, -0.84))
	glass.box(ws, Vector3.ZERO, Vector3(1.04, 0.58, 0.02), Color(0.55, 0.7, 0.75))
	dark.box(ws, Vector3(0, 0.3, 0), Vector3(1.1, 0.04, 0.05), TRIM)
	dark.box(ws, Vector3(-0.54, 0, 0), Vector3(0.04, 0.62, 0.05), TRIM)
	dark.box(ws, Vector3(0.54, 0, 0), Vector3(0.04, 0.62, 0.05), TRIM)
	# Mirrors on stalks.
	for sx: float in [-1.0, 1.0]:
		metal.box(I, Vector3(sx * 0.62, 1.32, -0.9), Vector3(0.14, 0.02, 0.02), CHROME)
		dark.bevel_box(I, Vector3(sx * 0.72, 1.36, -0.9), Vector3(0.1, 0.13, 0.03), 0.03, TRIM)
	# Dashboard silhouette with a round speedo.
	dark.box(I, Vector3(0, 1.08, -0.7), Vector3(0.95, 0.1, 0.18), TRIM)
	metal.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.42), Vector3(0, 1.15, -0.66)), Vector3.ZERO, 0.06, 0.02, 10, CHROME)
	# --- rear tub (rounded), low sills along the open passenger sides ---
	paint.loft(I, [Vector4(0.42, 0.66, 1.2, 0.56), Vector4(0.9, 0.68, 1.26, 0.6), Vector4(1.24, 0.7, 1.24, 0.62),
			Vector4(1.37, 0.7, 1.08, 0.56)], 0.45, TEAL)
	for sx: float in [-1.0, 1.0]:
		paint.box(I, Vector3(sx * 0.6, 0.97, 0.9), Vector3(0.07, 0.05, 0.94), ACCENT)    # yellow accent line
		dark.box(I, Vector3(sx * 0.59, 0.4, 0.2), Vector3(0.1, 0.07, 1.9), TRIM)          # rocker trim
		paint.box(I, Vector3(sx * 0.57, 0.55, -0.32), Vector3(0.07, 0.32, 0.5), TEAL)    # driver footwell side
		dark.box(I, Vector3(sx * 0.6, 0.47, 1.0), Vector3(0.16, 0.05, 0.52), TRIM)        # rear wheel arch lip
	dark.box(I, Vector3(0, 0.98, 1.37), Vector3(1.1, 0.04, 0.05), TRIM)
	# Number plate (fictional) — the plate surface; text comes from signage later.
	paint.box(I, Vector3(0, 0.55, 1.36), Vector3(0.36, 0.12, 0.02), Color(0.95, 0.93, 0.85))
	# Mudflaps.
	for sx: float in [-0.575, 0.575]:
		dark.box(I, Vector3(sx, 0.3, 1.27), Vector3(0.16, 0.22, 0.02), TRIM)
	# --- seats ---
	dark.bevel_box(I, Vector3(0, 0.7, 0.85), Vector3(1.1, 0.12, 0.46), 0.05, VINYL)       # rear bench
	dark.bevel_box(I, Vector3(0, 0.92, 1.16), Vector3(1.1, 0.36, 0.1), 0.05, VINYL)       # backrest (low, passenger visible)
	dark.bevel_box(I, Vector3(0, 0.82, -0.28), Vector3(0.36, 0.1, 0.32), 0.05, VINYL)     # driver saddle
	dark.box(I, Vector3(0, 0.58, -0.28), Vector3(0.3, 0.38, 0.28), TRIM)                  # saddle base
	# --- canopy: chrome posts + arched fabric roof, rolled side curtains ---
	for p: Vector3 in [Vector3(-0.6, 0, -0.8), Vector3(0.6, 0, -0.8), Vector3(-0.62, 0, 1.2), Vector3(0.62, 0, 1.2)]:
		metal.cylinder(I, Vector3(p.x, 1.3, p.z), 0.022, 0.62, 6, CHROME)
	dark.arc_shell(I, -0.9, 1.3, 0.69, 1.58, 0.2, 9, CANOPY)
	dark.loft(I, [Vector4(-0.94, 1.6, 1.36, 0.06), Vector4(-0.88, 1.6, 1.38, 0.06)], 0.5, CANOPY)  # front visor lip
	for sx: float in [-1.0, 1.0]:
		dark.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx * 0.68, 1.57, 0.2)), Vector3.ZERO, 0.04, 2.1, 6, CANOPY.lightened(0.04))
	# Rear canvas rolled up (open back): the passenger stays visible from the
	# chase camera — the brief's "passenger visible during the ride".
	dark.box(I, Vector3(0, 1.53, 1.29), Vector3(1.32, 0.1, 0.03), CANOPY)
	dark.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 1.47, 1.3)), Vector3.ZERO, 0.05, 1.3, 7, CANOPY.lightened(0.05))
	paint.box(I, Vector3(0, 1.62, -0.92), Vector3(1.2, 0.05, 0.04), ACCENT)          # canopy front accent
	# --- assemble ---
	var mesh := ArrayMesh.new()
	paint.commit(ArtMaterials.get_material(&"paint"), mesh)
	dark.commit(ArtMaterials.get_material(&"plaster"), mesh)
	metal.commit(ArtMaterials.get_material(&"metal"), mesh)
	glass.commit(ArtMaterials.get_material(&"glass"), mesh)
	_triangles = paint.triangle_count() + dark.triangle_count() + metal.triangle_count() + glass.triangle_count()
	body_instance = MeshInstance3D.new()
	body_instance.name = "HeroBody"
	body_instance.mesh = mesh
	add_child(body_instance)
	# Lights on their own instances so state hooks can change emission.
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(1.0, 0.97, 0.85)
	_head_mat.emission_enabled = true
	_head_mat.emission = Color(1.0, 0.95, 0.8)
	_head_mat.emission_energy_multiplier = 0.4
	var lens := ArtMesh.new()
	lens.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.0, -1.335)), Vector3.ZERO, 0.095, 0.02, 12, Color.WHITE)
	_add_light("Headlight", lens, _head_mat)
	_brake_mat = StandardMaterial3D.new()
	_brake_mat.albedo_color = Color(0.55, 0.05, 0.04)
	_brake_mat.emission_enabled = true
	_brake_mat.emission = Color(1.0, 0.1, 0.06)
	_brake_mat.emission_energy_multiplier = 0.2
	var tail := ArtMesh.new()
	for sx: float in [-0.46, 0.46]:
		tail.box(Transform3D.IDENTITY, Vector3(sx, 0.82, 1.36), Vector3(0.16, 0.1, 0.03), Color.WHITE)
	_add_light("TailLights", tail, _brake_mat)
	_triangles += lens.triangle_count() + tail.triangle_count()


func _add_light(node_name: String, m: ArtMesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = m.commit(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _wheel_mesh(width: float) -> ArrayMesh:
	var tyre := ArtMesh.new()
	var rim := ArtMesh.new()
	var I := Transform3D.IDENTITY
	tyre.cylinder(I, Vector3.ZERO, 0.21, width, 16, Color(0.06, 0.06, 0.065))
	# Tread blocks.
	for k in 16:
		var a := TAU * float(k) / 16.0
		var xf := Transform3D(Basis(Vector3.UP, a), Vector3.ZERO)
		tyre.box(xf, Vector3(0.212, 0, 0), Vector3(0.012, width * 0.9, 0.05), Color(0.04, 0.04, 0.045), 1)
	rim.cylinder(I, Vector3.ZERO, 0.12, width + 0.01, 12, Color(0.7, 0.71, 0.72))
	rim.cylinder(I, Vector3.ZERO, 0.05, width + 0.03, 8, Color(0.85, 0.86, 0.88))
	var mesh := ArrayMesh.new()
	tyre.commit(ArtMaterials.get_material(&"plaster"), mesh)
	rim.commit(ArtMaterials.get_material(&"metal"), mesh)
	_triangles += tyre.triangle_count() + rim.triangle_count()
	return mesh


func _build_wheels(visual: Node) -> void:
	var front := _wheel_mesh(0.12)
	var rear := _wheel_mesh(0.16)
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
		w.rotation_degrees = Vector3(0, 0, 90)  # cylinder axis → the axle (X)
		spin.add_child(w)


## Handlebar + steering column: a separate node that copies FrontSteer's yaw.
func _build_handlebar() -> void:
	handlebar = Node3D.new()
	handlebar.name = "Handlebar"
	handlebar.position = Vector3(0, 1.08, -0.62)
	add_child(handlebar)
	var m := ArtMesh.new()
	var I := Transform3D.IDENTITY
	m.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), Vector3(0, 0, 0), 0.018, 0.62, 6, CHROME)
	for sx: float in [-0.3, 0.3]:
		m.cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), Vector3(0, -sx, 0), 0.026, 0.12, 6, TRIM)
	m.cylinder(I, Vector3(0, -0.12, 0.02), 0.022, 0.24, 6, CHROME)
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit(ArtMaterials.get_material(&"metal"))
	handlebar.add_child(mi)
	_triangles += m.triangle_count()


func _build_driver() -> void:
	driver = CharacterRig.new(1)
	driver.name = "Driver"
	driver.mode = CharacterRig.Mode.DRIVE
	# Hips over the saddle (rig origin = feet; hips rest ≈ 0.91 m).
	driver.position = Vector3(0, 0.88 - 0.91, -0.22)
	add_child(driver)


func _process(delta: float) -> void:
	if _front_steer != null and handlebar != null:
		handlebar.rotation.y = _front_steer.rotation.y
	if tuk != null:
		var braking := tuk.input.brake > 0.1 and tuk.forward_speed > 0.3
		_brake_mat.emission_energy_multiplier = 2.6 if braking else 0.25
	_head_mat.emission_energy_multiplier = 2.0 if headlights_on else 0.4
	if driver != null:
		var cam := get_viewport().get_camera_3d()
		driver.animate(delta, cam.global_position if cam != null else global_position)
