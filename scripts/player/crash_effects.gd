class_name CrashEffects
extends Node3D
## Cheap crash feedback (v0.03A2): one-shot dust/debris burst and sparks at
## the impact point, lingering smoke on a damaged tuk. Pre-built CPU particle
## emitters (no allocation per crash). No explosions, no fire.

var _dust: CPUParticles3D
var _sparks: CPUParticles3D
var _smoke: CPUParticles3D


func _ready() -> void:
	_dust = _emitter(28, 0.9, Color(0.62, 0.56, 0.46), 0.22, 3.5)
	_sparks = _emitter(16, 0.35, Color(1.0, 0.8, 0.35), 0.05, 7.0)
	_smoke = _emitter(18, 2.2, Color(0.3, 0.3, 0.32, 0.8), 0.35, 0.8)
	_smoke.one_shot = false
	_smoke.emitting = false
	_smoke.gravity = Vector3(0, 1.2, 0)


func _emitter(amount: int, life: float, color: Color, size: float, speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = false
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	p.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = false
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func impact(tier: VehicleDamageState.Tier, at: Vector3, normal: Vector3) -> void:
	if tier == VehicleDamageState.Tier.NONE:
		return
	_dust.global_position = at + Vector3.UP * 0.4
	_dust.direction = (normal + Vector3.UP).normalized()
	_dust.restart()
	if tier != VehicleDamageState.Tier.LIGHT:
		_sparks.global_position = at + Vector3.UP * 0.6
		_sparks.restart()


func set_smoke(vehicle: Node3D, on: bool) -> void:
	if on:
		if _smoke.get_parent() != vehicle:
			_smoke.reparent(vehicle, false)
			_smoke.position = Vector3(0, 1.0, -0.9)
		_smoke.emitting = true
	else:
		_smoke.emitting = false
