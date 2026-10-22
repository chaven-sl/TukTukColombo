class_name GraphicsProfile
extends Resource
## Rendering quality tier. v0.03A: LOW / MEDIUM / HIGH all map closely to the
## approved prototype look; this exists so a future settings menu and
## device-based defaults need no restructuring. Gameplay never reads it.

enum Tier { LOW, MEDIUM, HIGH }

@export var tier: Tier = Tier.MEDIUM
@export var display_name_key := ""
@export var sun_shadows := true
@export var shadow_max_distance := 60.0
## 3D render resolution scale (1.0 = native). UI is never scaled down.
@export_range(0.5, 1.0) var render_scale := 1.0
@export var msaa_3d := Viewport.MSAA_DISABLED
## 0 = uncapped (vsync decides). 30 for devices that can't hold 60.
@export var max_fps := 60
@export var fog_enabled := true


func apply(viewport: Viewport, sun: DirectionalLight3D, environment: Environment) -> void:
	viewport.scaling_3d_scale = render_scale
	viewport.msaa_3d = msaa_3d
	Engine.max_fps = max_fps
	if sun != null:
		sun.shadow_enabled = sun_shadows
		sun.directional_shadow_max_distance = shadow_max_distance
	if environment != null:
		environment.fog_enabled = fog_enabled


static func default_tier_for_platform() -> Tier:
	return Tier.MEDIUM if OS.has_feature("mobile") else Tier.HIGH
