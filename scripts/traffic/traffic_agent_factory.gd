class_name TrafficAgentFactory
extends RefCounted
## Builds pooled TrafficAgent nodes. v0.03B: each vehicle is one TrafficArt
## mesh (shared per class + paint variant); the paint variant changes per
## spawn. Collision stays a simple box (art never touches physics).

static var _box_cache: Dictionary = {}
static var _cylinder_cache: Dictionary = {}
static var _material_cache: Dictionary = {}


static func create_agent(cls: TrafficVehicleClass, id: int) -> TrafficAgent:
	var agent := TrafficAgent.new()
	agent.name = "%s_%02d" % [cls.id, id]
	agent.agent_id = id
	agent.vehicle_class = cls
	agent.half_length = cls.length * 0.5
	agent.half_width = cls.width * 0.5
	# Node transform is authoritative; the kinematic body follows it each tick.
	agent.sync_to_physics = false
	agent.collision_layer = 0
	agent.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(cls.width, cls.height - 0.15, cls.length)
	shape.shape = box
	shape.position = Vector3(0.0, cls.height * 0.5 + 0.075, 0.0)
	agent.add_child(shape)
	var visual := Node3D.new()
	visual.name = "Visual"
	agent.add_child(visual)
	# v0.03B: one art mesh per vehicle (TrafficArt), 2–3 draw calls.
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = TrafficArt.mesh_for(cls, 0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visual.add_child(body)
	agent.body_meshes.append(body)
	return agent


## Releases shared meshes/materials (call when the traffic system is freed).
static func clear_cache() -> void:
	_box_cache.clear()
	_cylinder_cache.clear()
	_material_cache.clear()
	TrafficArt.clear_cache()


static func body_material(color: Color) -> StandardMaterial3D:
	if not _material_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.65
		_material_cache[color] = mat
	return _material_cache[color]


static func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	if not _box_cache.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		_box_cache[size] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = _box_cache[size]
	mi.position = pos
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _wheel(parent: Node3D, radius: float, width: float, pos: Vector3) -> void:
	var key := Vector2(radius, width)
	if not _cylinder_cache.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = width
		mesh.radial_segments = 10
		mesh.rings = 1
		_cylinder_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = _cylinder_cache[key]
	mi.position = pos
	mi.rotation_degrees = Vector3(0, 0, 90)
	mi.material_override = body_material(Color(0.05, 0.05, 0.05))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _glass() -> StandardMaterial3D:
	return body_material(Color(0.32, 0.4, 0.46))


static func _emissive(color: Color) -> StandardMaterial3D:
	var key := Color(color.r, color.g, color.b, 0.999)
	if not _material_cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		_material_cache[key] = mat
	return _material_cache[key]
