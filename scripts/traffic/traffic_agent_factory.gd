class_name TrafficAgentFactory
extends RefCounted
## Builds pooled TrafficAgent nodes with primitive placeholder silhouettes.
## Meshes and materials are shared across agents; only the body material
## reference changes per spawn. Traffic never casts shadows (mobile budget).

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
	match cls.kind:
		TrafficVehicleClass.Kind.CAR:
			_build_car(agent, visual, cls)
		TrafficVehicleClass.Kind.BUS:
			_build_bus(agent, visual, cls)
		TrafficVehicleClass.Kind.MOTORCYCLE:
			_build_motorcycle(agent, visual, cls)
		TrafficVehicleClass.Kind.TUK:
			_build_tuk(agent, visual, cls)
	return agent


## Releases shared meshes/materials (call when the traffic system is freed).
static func clear_cache() -> void:
	_box_cache.clear()
	_cylinder_cache.clear()
	_material_cache.clear()


static func body_material(color: Color) -> StandardMaterial3D:
	if not _material_cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.65
		_material_cache[color] = mat
	return _material_cache[color]


static func _build_car(agent: TrafficAgent, v: Node3D, cls: TrafficVehicleClass) -> void:
	var w := cls.width
	var l := cls.length
	agent.body_meshes.append(_box(v, Vector3(w, 0.72, l), Vector3(0, 0.62, 0), body_material(cls.body_colors[0])))
	_box(v, Vector3(w * 0.86, 0.55, l * 0.5), Vector3(0, 1.25, 0.15 * l), _glass())
	_box(v, Vector3(w * 0.9, 0.08, l * 0.46), Vector3(0, 1.55, 0.15 * l), body_material(Color(0.2, 0.2, 0.22)))
	_box(v, Vector3(w * 0.8, 0.12, 0.05), Vector3(0, 0.8, l * 0.5 + 0.01), _emissive(Color(0.8, 0.05, 0.05)))
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_wheel(v, 0.32, 0.22, Vector3(x * (w * 0.5 - 0.12), 0.32, z * (l * 0.5 - 0.8)))


static func _build_bus(agent: TrafficAgent, v: Node3D, cls: TrafficVehicleClass) -> void:
	var w := cls.width
	var l := cls.length
	agent.body_meshes.append(_box(v, Vector3(w, 2.5, l), Vector3(0, 1.6, 0), body_material(cls.body_colors[0])))
	_box(v, Vector3(w + 0.04, 0.8, l - 1.6), Vector3(0, 2.2, 0.4), _glass())
	_box(v, Vector3(w - 0.25, 1.0, 0.06), Vector3(0, 2.05, -l * 0.5 - 0.02), _glass())
	_box(v, Vector3(w - 0.1, 0.14, l - 0.4), Vector3(0, 2.92, 0), body_material(Color(0.85, 0.85, 0.82)))
	_box(v, Vector3(1.4, 0.32, 0.05), Vector3(0, 2.75, -l * 0.5 - 0.04), _emissive(Color(1.0, 0.6, 0.1)))
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_wheel(v, 0.5, 0.3, Vector3(x * (w * 0.5 - 0.15), 0.5, z * (l * 0.5 - 1.9)))


static func _build_motorcycle(agent: TrafficAgent, v: Node3D, cls: TrafficVehicleClass) -> void:
	var dark := body_material(Color(0.12, 0.12, 0.13))
	_box(v, Vector3(0.3, 0.42, 1.45), Vector3(0, 0.66, 0), dark)
	_box(v, Vector3(0.36, 0.28, 0.6), Vector3(0, 0.95, -0.15), body_material(Color(0.3, 0.3, 0.32)))
	_box(v, Vector3(0.7, 0.05, 0.05), Vector3(0, 1.08, -0.5), dark)
	agent.body_meshes.append(_box(v, Vector3(0.44, 0.62, 0.34), Vector3(0, 1.38, 0.12), body_material(cls.body_colors[0])))
	_box(v, Vector3(0.3, 0.3, 0.32), Vector3(0, 1.82, 0.06), body_material(Color(0.9, 0.9, 0.9)))
	_wheel(v, 0.3, 0.12, Vector3(0, 0.3, -0.72))
	_wheel(v, 0.3, 0.14, Vector3(0, 0.3, 0.72))


static func _build_tuk(agent: TrafficAgent, v: Node3D, cls: TrafficVehicleClass) -> void:
	var body := body_material(cls.body_colors[0])
	agent.body_meshes.append(_box(v, Vector3(1.25, 0.78, 2.35), Vector3(0, 0.74, 0.12), body))
	agent.body_meshes.append(_box(v, Vector3(0.75, 0.72, 0.45), Vector3(0, 0.72, -1.08), body))
	_box(v, Vector3(1.1, 0.55, 0.05), Vector3(0, 1.36, -0.78), _glass())
	_box(v, Vector3(1.32, 0.07, 2.0), Vector3(0, 1.7, 0.15), body_material(Color(0.08, 0.08, 0.09)))
	for x in [-1.0, 1.0]:
		_box(v, Vector3(0.05, 0.6, 0.05), Vector3(x * 0.62, 1.38, -0.78), body_material(Color(0.08, 0.08, 0.09)))
	_wheel(v, 0.21, 0.12, Vector3(0, 0.21, -1.0))
	_wheel(v, 0.21, 0.16, Vector3(-0.575, 0.21, 1.0))
	_wheel(v, 0.21, 0.16, Vector3(0.575, 0.21, 1.0))


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
