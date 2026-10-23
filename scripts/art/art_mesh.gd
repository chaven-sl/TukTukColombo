class_name ArtMesh
extends RefCounted
## Fast procedural mesh builder for the v0.03B art pass (no Blender in this
## environment; every asset is generated from reproducible GDScript).
##
## Writes straight into packed arrays (much faster than SurfaceTool from
## GDScript). Colour lives in vertex colours, so one shared material renders
## most of a district — the "atlas-equivalent" that keeps draw calls low.
## Optional bone/weight channels make rigid-skinned character meshes.
##
## All primitives take a local Transform3D so parts compose into one mesh.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()
var bones := PackedInt32Array()     # 4 per vertex (rigid: first used)
var weights := PackedFloat32Array() # 4 per vertex
var skinned := false
## Current rigid bone for subsequently added geometry (skinned meshes).
var bone := 0


func vertex_count() -> int:
	return verts.size()


func triangle_count() -> int:
	return indices.size() / 3


func _v(p: Vector3, n: Vector3, c: Color, uv: Vector2 = Vector2.ZERO) -> int:
	verts.append(p)
	normals.append(n)
	colors.append(c)
	uvs.append(uv)
	if skinned:
		bones.append_array([bone, 0, 0, 0])
		weights.append_array([1.0, 0.0, 0.0, 0.0])
	return verts.size() - 1


## Quad a→b→c→d (any winding); the face normal is computed and the triangles
## are emitted front-facing for that normal.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, uv := Rect2(0, 0, 1, 1)) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-12:
		n = (c - b).cross(a - b)
	n = n.normalized()
	var i := _v(a, n, color, uv.position)
	_v(b, n, color, Vector2(uv.end.x, uv.position.y))
	_v(c, n, color, uv.end)
	_v(d, n, color, Vector2(uv.position.x, uv.end.y))
	# Godot front faces are clockwise when viewed from the front.
	indices.append_array([i, i + 2, i + 1, i, i + 3, i + 2])


func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	var i := _v(a, n, color)
	_v(b, n, color)
	_v(c, n, color)
	indices.append_array([i, i + 2, i + 1])


## Axis-aligned box (in `xf` space) centred at `c` with size `s`.
## `faces`: bitmask of faces to emit (1 +X, 2 -X, 4 +Y, 8 -Y, 16 +Z, 32 -Z).
func box(xf: Transform3D, c: Vector3, s: Vector3, color: Color, faces: int = 63, shade_sides := true) -> void:
	var h := s * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * (c + Vector3(x * h.x, y * h.y, z * h.z))
	var side := color.darkened(0.06) if shade_sides else color
	if faces & 4:
		quad(p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), p.call(-1, 1, -1), color)
	if faces & 8:
		quad(p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1), color.darkened(0.2))
	if faces & 16:
		quad(p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), side)
	if faces & 32:
		quad(p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1), side)
	if faces & 1:
		quad(p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), color)
	if faces & 2:
		quad(p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), color)


## Box whose vertical edges are chamfered by `bevel` (softer silhouettes).
func bevel_box(xf: Transform3D, c: Vector3, s: Vector3, bevel: float, color: Color) -> void:
	var h := s * 0.5
	var b := minf(bevel, minf(h.x, h.z) * 0.9)
	var ring := [Vector2(-h.x + b, -h.z), Vector2(h.x - b, -h.z), Vector2(h.x, -h.z + b), Vector2(h.x, h.z - b),
			Vector2(h.x - b, h.z), Vector2(-h.x + b, h.z), Vector2(-h.x, h.z - b), Vector2(-h.x, -h.z + b)]
	var top: Array[Vector3] = []
	var bot: Array[Vector3] = []
	for r: Vector2 in ring:
		top.append(xf * (c + Vector3(r.x, h.y, r.y)))
		bot.append(xf * (c + Vector3(r.x, -h.y, r.y)))
	for i in 8:
		var j := (i + 1) % 8
		quad(bot[j], bot[i], top[i], top[j], color.darkened(0.04 * float(i % 2)))
	for i in range(1, 7):
		tri(top[0], top[i + 1], top[i], color)
		tri(bot[0], bot[i], bot[i + 1], color.darkened(0.2))


## Cylinder along local Y from `c - h/2` to `c + h/2` (in xf space).
func cylinder(xf: Transform3D, c: Vector3, radius: float, height: float, segments: int, color: Color, caps := true, radius_top := -1.0) -> void:
	var rt := radius if radius_top < 0.0 else radius_top
	var ring_b: Array[Vector3] = []
	var ring_t: Array[Vector3] = []
	for k in segments:
		var a := TAU * float(k) / float(segments)
		var dir := Vector3(cos(a), 0.0, sin(a))
		ring_b.append(xf * (c + dir * radius + Vector3.DOWN * height * 0.5))
		ring_t.append(xf * (c + dir * rt + Vector3.UP * height * 0.5))
	for k in segments:
		var j := (k + 1) % segments
		quad(ring_b[j], ring_b[k], ring_t[k], ring_t[j], color)  # outward-facing
	if caps:
		var top_c := xf * (c + Vector3.UP * height * 0.5)
		var bot_c := xf * (c + Vector3.DOWN * height * 0.5)
		for k in segments:
			var j := (k + 1) % segments
			tri(top_c, ring_t[j], ring_t[k], color)
			tri(bot_c, ring_b[k], ring_b[j], color.darkened(0.2))


## Low-poly ellipsoid (heads, hands, canopies).
func sphere(xf: Transform3D, c: Vector3, r: Vector3, color: Color, seg: int = 8, rings: int = 5) -> void:
	var grid: Array = []
	for i in rings + 1:
		var v := PI * float(i) / float(rings)
		var row: Array[Vector3] = []
		for k in seg:
			var u := TAU * float(k) / float(seg)
			row.append(xf * (c + Vector3(sin(v) * cos(u) * r.x, cos(v) * r.y, sin(v) * sin(u) * r.z)))
		grid.append(row)
	for i in rings:
		for k in seg:
			var j := (k + 1) % seg
			var a: Vector3 = grid[i][k]
			var b: Vector3 = grid[i][j]
			var cc: Vector3 = grid[i + 1][j]
			var d: Vector3 = grid[i + 1][k]
			if i == 0:
				tri(a, cc, d, color)
			elif i == rings - 1:
				tri(a, b, d, color)
			else:
				quad(a, b, cc, d, color)


## Semicircular-headed arch opening frame (front face only) — station arcades.
## Draws the wall panel of width w, height h at local z = 0 with an arch hole of
## opening width ow and springing height sh; hole is left empty (or filled dark).
func arch_panel(xf: Transform3D, w: float, h: float, ow: float, sh: float, color: Color, seg: int = 7, fill := Color(0, 0, 0, 0)) -> void:
	var hw := w * 0.5
	var r := ow * 0.5
	# Piers.
	quad(xf * Vector3(-hw, 0, 0), xf * Vector3(-r, 0, 0), xf * Vector3(-r, sh, 0), xf * Vector3(-hw, sh, 0), color)
	quad(xf * Vector3(r, 0, 0), xf * Vector3(hw, 0, 0), xf * Vector3(hw, sh, 0), xf * Vector3(r, sh, 0), color)
	# Spandrels around the arch curve up to the top.
	for k in seg:
		var a0 := PI - PI * float(k) / float(seg)
		var a1 := PI - PI * float(k + 1) / float(seg)
		var p0 := Vector3(cos(a0) * r, sh + sin(a0) * r, 0)
		var p1 := Vector3(cos(a1) * r, sh + sin(a1) * r, 0)
		var t0 := Vector3(lerpf(-hw, hw, float(k) / float(seg)), h, 0)
		var t1 := Vector3(lerpf(-hw, hw, float(k + 1) / float(seg)), h, 0)
		quad(xf * p0, xf * p1, xf * t1, xf * t0, color)
		if fill.a > 0.0:
			tri(xf * Vector3(0, sh, -0.02), xf * p1, xf * p0, fill)
	quad(xf * Vector3(-hw, sh, 0), xf * Vector3(-r, sh, 0), xf * Vector3(-r, sh + 0.001, 0), xf * Vector3(-hw, h, 0), color)
	quad(xf * Vector3(r, sh, 0), xf * Vector3(hw, sh, 0), xf * Vector3(hw, h, 0), xf * Vector3(r, sh + 0.001, 0), color)
	if fill.a > 0.0:
		quad(xf * Vector3(-r, 0, -0.02), xf * Vector3(r, 0, -0.02), xf * Vector3(r, sh, -0.02), xf * Vector3(-r, sh, -0.02), fill)


## Lofted body along local Z: each section is Vector4(z, centre_y, width,
## height) with chamfer `bevel` (fraction of the smaller half-size). Rings
## are connected with quads; both ends capped. Gives rounded vehicle noses,
## tubs and cowls from a handful of numbers.
func loft(xf: Transform3D, sections: Array, bevel: float, color: Color, caps := true) -> void:
	var rings: Array = []
	for sec: Vector4 in sections:
		var hw := sec.z * 0.5
		var hh := sec.w * 0.5
		var b := minf(hw, hh) * bevel
		var cy := sec.y
		var pts: Array[Vector3] = []
		for q: Vector2 in [Vector2(-hw + b, -hh), Vector2(hw - b, -hh), Vector2(hw, -hh + b), Vector2(hw, hh - b),
				Vector2(hw - b, hh), Vector2(-hw + b, hh), Vector2(-hw, hh - b), Vector2(-hw, -hh + b)]:
			pts.append(xf * Vector3(q.x, cy + q.y, sec.x))
		rings.append(pts)
	for r in rings.size() - 1:
		var a: Array[Vector3] = rings[r]
		var bb: Array[Vector3] = rings[r + 1]
		for i in 8:
			var j := (i + 1) % 8
			quad(a[i], a[j], bb[j], bb[i], color)
	if caps:
		var f: Array[Vector3] = rings[0]
		var l: Array[Vector3] = rings[rings.size() - 1]
		for i in range(1, 7):
			tri(f[0], f[i + 1], f[i], color)  # faces -Z (sections ascend in z)
			tri(l[0], l[i], l[i + 1], color)


## Arched roof shell (canopies, awnings): a half-ellipse cross-section across
## X swept along Z from z0 to z1, double-sided via two passes.
func arc_shell(xf: Transform3D, z0: float, z1: float, half_w: float, y_base: float, rise: float, seg: int, color: Color) -> void:
	for k in seg:
		var a0 := PI * float(k) / float(seg)
		var a1 := PI * float(k + 1) / float(seg)
		var p0 := Vector3(cos(a0) * half_w, y_base + sin(a0) * rise, 0)
		var p1 := Vector3(cos(a1) * half_w, y_base + sin(a1) * rise, 0)
		var q0 := xf * (p0 + Vector3(0, 0, z0))
		var q1 := xf * (p1 + Vector3(0, 0, z0))
		var r0 := xf * (p0 + Vector3(0, 0, z1))
		var r1 := xf * (p1 + Vector3(0, 0, z1))
		quad(q1, r1, r0, q0, color)                 # outside (up)
		quad(q0, r0, r1, q1, color.darkened(0.25))  # underside


## Hanging wire (catenary-ish) as a thin flat ribbon.
func wire(a: Vector3, b: Vector3, sag: float, thickness: float, color: Color, seg: int = 8) -> void:
	var prev := a
	for k in range(1, seg + 1):
		var t := float(k) / float(seg)
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var up := Vector3.UP * thickness
		quad(prev, p, p + up, prev + up, color)
		prev = p


## Shifts every vertex (re-centre a world-space batch on its node).
func translate(offset: Vector3) -> void:
	for i in verts.size():
		verts[i] += offset


func append(other: ArtMesh, xf: Transform3D = Transform3D.IDENTITY) -> void:
	var base := verts.size()
	var nb := xf.basis.inverse().transposed()
	for i in other.verts.size():
		verts.append(xf * other.verts[i])
		normals.append((nb * other.normals[i]).normalized())
	colors.append_array(other.colors)
	uvs.append_array(other.uvs)
	if skinned:
		if other.skinned:
			bones.append_array(other.bones)
			weights.append_array(other.weights)
		else:
			for i in other.verts.size():
				bones.append_array([bone, 0, 0, 0])
				weights.append_array([1.0, 0.0, 0.0, 0.0])
	for i in other.indices:
		indices.append(base + i)


## Commits to an ArrayMesh surface (appends a surface if `into` is given).
func commit(material: Material = null, into: ArrayMesh = null) -> ArrayMesh:
	var mesh := into if into != null else ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	if skinned:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh
