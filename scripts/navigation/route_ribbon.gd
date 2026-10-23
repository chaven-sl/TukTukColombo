class_name RouteRibbon
extends MeshInstance3D
## Road-hugging GPS ribbon: animated chevrons along a RoutePlan, slightly above
## the road. The mesh is rebuilt only when the route changes; the part already
## driven is hidden by a shader uniform (no per-frame rebuild).

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, blend_mix, depth_draw_never;
uniform vec4 color : source_color = vec4(0.15, 0.85, 1.0, 1.0);
uniform float progress = 0.0;
uniform float spacing = 3.4;
void fragment() {
	float along = UV.x;
	float ahead = along - progress - 2.0;
	if (ahead < 0.0) { discard; }
	float across = abs(UV.y - 0.5) * 2.0;
	float f = fract((along - TIME * 4.0) / spacing);
	// Solid core line (always readable) + animated chevrons pointing along the
	// route (a V whose arms trail backwards).
	float v = f - across * 0.35;
	float chevron = smoothstep(0.18, 0.24, v) * (1.0 - smoothstep(0.56, 0.62, v));
	float core = 1.0 - smoothstep(0.16, 0.24, across);
	float a = max(chevron, core * 0.7);
	if (a < 0.02) { discard; }
	// v0.03B presentation: soft-edged, fades in just ahead of the tuk so it
	// never sits on the bonnet, and lets the asphalt read through a little.
	float fade = smoothstep(0.0, 6.0, ahead);
	ALBEDO = mix(color.rgb * 0.8, color.rgb, chevron);
	ALPHA = a * fade * 0.7;  // v0.03B1: guides, never dominates
}
"""

var _material: ShaderMaterial


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	material_override = _material
	visible = false


func show_plan(plan: RoutePlan, cfg: RouteGuidanceConfig) -> void:
	if plan == null or plan.is_empty():
		clear()
		return
	_material.set_shader_parameter("color", cfg.ribbon_color)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var half := cfg.ribbon_width * 0.5
	var lift := Vector3.UP * cfg.ribbon_height
	var step := 1.5
	var total := plan.length()
	var n := maxi(int(ceil(total / step)), 1)
	for k in n + 1:
		var along := minf(k * step, total)
		var p := plan.position_at(along) + lift
		var t := plan.tangent_at(along)
		var side := t.cross(Vector3.UP).normalized() * half
		verts.append(p - side)
		verts.append(p + side)
		uvs.append(Vector2(along, 0.0))
		uvs.append(Vector2(along, 1.0))
		if k > 0:
			var b := (k - 1) * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = am
	set_progress(0.0)
	visible = true


func set_progress(along: float) -> void:
	_material.set_shader_parameter("progress", along)


func clear() -> void:
	mesh = null
	visible = false
