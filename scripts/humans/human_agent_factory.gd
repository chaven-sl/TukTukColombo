class_name HumanAgentFactory
extends RefCounted
## Builds pooled HumanAgents with primitive placeholder figures: capsule body,
## sphere head, a passenger marker diamond and a small reaction indicator.
## Meshes/materials are shared; nothing here is final art.

const SHIRTS := [Color(0.85, 0.85, 0.82), Color(0.25, 0.45, 0.7), Color(0.7, 0.3, 0.25), Color(0.35, 0.55, 0.35),
		Color(0.9, 0.75, 0.3), Color(0.55, 0.4, 0.6), Color(0.3, 0.3, 0.32), Color(0.85, 0.55, 0.6)]

static var _cache: Dictionary = {}


static func create_agent(id: int) -> HumanAgent:
	var agent := HumanAgent.new()
	agent.name = "Human_%02d" % id
	agent.human_id = id
	var root := Node3D.new()
	root.name = "Visual"
	agent.add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = _mesh("body")
	body.position = Vector3(0, 0.66, 0)
	body.material_override = body_material(SHIRTS[id % SHIRTS.size()])
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = _mesh("head")
	head.position = Vector3(0, 1.45, 0)
	head.material_override = body_material(Color(0.45, 0.32, 0.24))
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(head)
	var marker := MeshInstance3D.new()
	marker.mesh = _mesh("marker")
	marker.position = Vector3(0, 2.35, 0)
	marker.rotation_degrees = Vector3(45, 0, 45)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	root.add_child(marker)
	var indicator := MeshInstance3D.new()
	indicator.mesh = _mesh("indicator")
	indicator.position = Vector3(0, 1.85, 0)
	indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	indicator.visible = false
	root.add_child(indicator)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.0, 0)
	label.font_size = 28
	label.pixel_size = 0.006
	label.no_depth_test = true
	label.visible = false
	root.add_child(label)
	agent.attach_visual(root, body, marker, indicator, label)
	agent.visible = false
	return agent


static func _mesh(kind: String) -> Mesh:
	var key := "mesh_" + kind
	if _cache.has(key):
		return _cache[key]
	var mesh: Mesh
	match kind:
		"body":
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.22
			capsule.height = 1.25
			capsule.radial_segments = 8
			capsule.rings = 2
			mesh = capsule
		"head":
			var sphere := SphereMesh.new()
			sphere.radius = 0.13
			sphere.height = 0.26
			sphere.radial_segments = 8
			sphere.rings = 4
			mesh = sphere
		"marker":
			var box := BoxMesh.new()
			box.size = Vector3(0.32, 0.32, 0.32)
			mesh = box
		_:
			var dot := SphereMesh.new()
			dot.radius = 0.1
			dot.height = 0.2
			dot.radial_segments = 6
			dot.rings = 3
			mesh = dot
	_cache[key] = mesh
	return mesh


static func body_material(color: Color) -> StandardMaterial3D:
	var key := "body_%s" % color
	if not _cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		_cache[key] = mat
	return _cache[key]


static func marker_material(color: Color) -> StandardMaterial3D:
	var key := "marker_%s" % color
	if not _cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.5
		_cache[key] = mat
	return _cache[key]


static func reaction_material(r: HumanAgent.Reaction) -> StandardMaterial3D:
	var color := Color(1, 1, 1)
	match r:
		HumanAgent.Reaction.HESITATE:
			color = Color(1.0, 0.9, 0.2)
		HumanAgent.Reaction.STEP_BACK, HumanAgent.Reaction.HURRY:
			color = Color(1.0, 0.5, 0.1)
		HumanAgent.Reaction.FREEZE:
			color = Color(1.0, 0.15, 0.1)
		HumanAgent.Reaction.ANGRY:
			color = Color(0.95, 0.05, 0.2)
	return marker_material(color)


static func clear_cache() -> void:
	_cache.clear()
