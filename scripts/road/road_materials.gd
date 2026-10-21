class_name RoadMaterials
extends RefCounted
## Shared, mobile-friendly placeholder materials for generated world geometry.
## Vertex colours carry most of the variation so draw calls stay low.


static func create() -> Dictionary:
	var m := {}
	m["asphalt"] = _vertex_colour_material(0.95)
	m["kerb"] = _vertex_colour_material(0.85)
	var markings := _vertex_colour_material(0.8)
	markings.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m["markings"] = markings
	m["ground"] = _flat(Color(0.36, 0.42, 0.27), 1.0)
	m["concrete"] = _flat(Color(0.62, 0.6, 0.56), 0.9)
	m["dark"] = _flat(Color(0.12, 0.12, 0.13), 0.8)
	var tunnel := StandardMaterial3D.new()
	tunnel.albedo_color = Color(0.02, 0.02, 0.025)
	tunnel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m["tunnel"] = tunnel
	m["lamp_off"] = _flat(Color(0.18, 0.18, 0.18), 0.6)
	m["lamp_red_on"] = _emissive(Color(1.0, 0.12, 0.08))
	m["lamp_amber_on"] = _emissive(Color(1.0, 0.65, 0.05))
	m["lamp_green_on"] = _emissive(Color(0.15, 1.0, 0.3))
	var lines := StandardMaterial3D.new()
	lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.vertex_color_use_as_albedo = true
	lines.no_depth_test = true
	m["debug_lines"] = lines
	m["scenery"] = _vertex_colour_material(0.9)
	return m


static func _vertex_colour_material(roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _flat(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


static func _emissive(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	return mat
