class_name DistrictLighting
extends RefCounted
## Fort–Pettah lighting (art bible): HOT TROPICAL LATE MORNING, ~10:30–11:00.
## Bright, slightly warm sun high in the sky, pale tropical blue, subtle humid
## haze, strong contact shadows, no heavy bloom. No day/night cycle.

const SUN_COLOR := Color(1.0, 0.94, 0.82)
const SKY_TOP := Color(0.26, 0.5, 0.84)
const SKY_HORIZON := Color(0.7, 0.8, 0.88)
const HAZE := Color(0.8, 0.84, 0.86)


static func make_environment() -> Environment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP
	sky_mat.sky_horizon_color = SKY_HORIZON
	sky_mat.ground_horizon_color = Color(0.7, 0.68, 0.62)
	sky_mat.ground_bottom_color = Color(0.35, 0.33, 0.3)
	sky_mat.sun_angle_max = 20.0
	sky_mat.sky_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Flat ambient + no sky reflections: sampling sky radiance on every lit
	# pixel cost the Mali-G610 its vsync budget (device-measured, v0.03B).
	# The sky stays as the visible background only.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.78, 0.76)  # warm street bounce + pale sky fill
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.tonemap_white = 5.0
	# Humid haze: light depth fog, a touch warm.
	env.fog_enabled = true
	env.fog_light_color = HAZE
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.08
	return env


## Sun at ~10:45 local: high (~58°), from the east-south-east.
static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = SUN_COLOR
	sun.light_energy = 1.75
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_blur = 1.2
	sun.rotation = Vector3(deg_to_rad(-58.0), deg_to_rad(118.0), 0.0)
	return sun
