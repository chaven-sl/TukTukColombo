class_name RoadMaterials
extends RefCounted
## Shared, mobile-friendly placeholder materials for generated world geometry.
## Vertex colours carry most of the variation so draw calls stay low.


enum Style { GREYBOX, COLOMBO }


static func create(style: int = Style.GREYBOX) -> Dictionary:
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
	if style == Style.COLOMBO:
		_colombo(m)
	return m


## v0.03B Fort–Pettah look: dusty, patched asphalt with restrained world-space
## detail (one small seamless noise texture, triplanar — no UVs, no photo
## textures), sun-faded paint, dusty verges. Readable at 60–70 km/h.
static func _colombo(m: Dictionary) -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.color_ramp = Gradient.new()
	tex.color_ramp.set_color(0, Color(0.8, 0.81, 0.83))
	tex.color_ramp.set_color(1, Color(1.0, 1.0, 1.0))
	var asphalt := _vertex_colour_material(0.92)
	asphalt.vertex_color_use_as_albedo = false  # dusty mid-grey, not the greybox charcoal
	asphalt.albedo_texture = tex
	asphalt.albedo_color = Color(0.36, 0.37, 0.39)  # neutral-cool so warm light doesn't turn it brown
	asphalt.uv1_triplanar = true
	asphalt.uv1_world_triplanar = true
	asphalt.uv1_scale = Vector3(0.22, 0.22, 0.22)
	m["asphalt"] = asphalt
	var kerb := _vertex_colour_material(0.85)
	kerb.albedo_color = Color(0.94, 0.95, 0.97)
	kerb.albedo_texture = tex
	kerb.uv1_triplanar = true
	kerb.uv1_world_triplanar = true
	kerb.uv1_scale = Vector3(0.6, 0.6, 0.6)
	m["kerb"] = kerb
	var markings := _vertex_colour_material(0.8)
	markings.albedo_color = Color(0.86, 0.85, 0.8)  # sun-faded paint
	m["markings"] = markings
	var ground := _flat(Color(0.52, 0.48, 0.4), 1.0)  # dusty, sparse verge
	ground.albedo_texture = tex
	ground.uv1_triplanar = true
	ground.uv1_world_triplanar = true
	ground.uv1_scale = Vector3(0.08, 0.08, 0.08)
	m["ground"] = ground


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
