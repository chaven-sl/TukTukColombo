class_name ArtMaterials
extends RefCounted
## The small shared material set for the whole district (art bible: avoid a
## material-per-object explosion). Colour comes from vertex colours.

static var _cache: Dictionary = {}


static func get_material(kind: StringName) -> StandardMaterial3D:
	if _cache.has(kind):
		return _cache[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	match kind:
		&"plaster":
			m.roughness = 0.88
		&"paint":  # vehicle paint: slightly glossy painted metal
			m.roughness = 0.3
			m.metallic = 0.12
			m.metallic_specular = 0.7
		&"chrome":  # no sky reflections on mobile: bright, semi-metallic, tight highlight
			m.roughness = 0.22
			m.metallic = 0.45
			m.metallic_specular = 0.9
		&"rubber":
			m.roughness = 0.96
			m.metallic_specular = 0.25
		&"vinyl":  # seats: soft sheen
			m.roughness = 0.55
			m.metallic_specular = 0.55
		&"glass_clear":  # windscreens: actually see-through
			m.roughness = 0.05
			m.metallic_specular = 0.9
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		&"wood":
			m.roughness = 0.8
		&"cardboard":  # sacks, boxes, cloth goods
			m.roughness = 0.95
			m.metallic_specular = 0.2
		&"metal":  # shutters, poles, rails: dull painted/galvanised
			m.roughness = 0.5
			m.metallic = 0.35
		&"glass":
			m.roughness = 0.08
			m.metallic = 0.3
			m.metallic_specular = 0.9
		&"fabric":
			m.roughness = 1.0
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		&"skin":
			m.roughness = 0.7
		&"emissive":
			m.emission_enabled = true
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			m.emission = Color(1, 1, 1)
			m.emission_energy_multiplier = 1.4
			m.roughness = 0.4
		&"wire":
			m.roughness = 0.9
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_:
			m.roughness = 0.85
	_cache[kind] = m
	return m


static func clear_cache() -> void:
	_cache.clear()
