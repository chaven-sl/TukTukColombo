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


# --- v0.03B1 smooth-shaded primitives (curved bodies read far less "boxy") ---

## Smooth grid surface: `rows` is an Array of PackedVector3Array, all the same
## length. Normals are averaged from neighbours and oriented away from
## `inside` (a point inside the closed shape) so the surface faces outward.
## `wrap` closes each row into a ring.
func grid(rows: Array, color: Color, wrap: bool, inside: Vector3, colors_per_row: PackedColorArray = PackedColorArray()) -> void:
	var nr := rows.size()
	if nr < 2:
		return
	var nc := (rows[0] as PackedVector3Array).size()
	var base := verts.size()
	for r in nr:
		var row: PackedVector3Array = rows[r]
		var prev_row: PackedVector3Array = rows[maxi(r - 1, 0)]
		var next_row: PackedVector3Array = rows[mini(r + 1, nr - 1)]
		var col := color if colors_per_row.is_empty() else colors_per_row[r]
		for c in nc:
			var cl := (c - 1 + nc) % nc if wrap else maxi(c - 1, 0)
			var cr := (c + 1) % nc if wrap else mini(c + 1, nc - 1)
			var du := row[cr] - row[cl]
			var dv := next_row[c] - prev_row[c]
			var n := du.cross(dv)
			if n.length_squared() < 1e-12:
				n = row[c] - inside
			n = n.normalized()
			if n.dot(row[c] - inside) < 0.0:
				n = -n
			_v(row[c], n, col, Vector2(float(c) / float(nc), float(r) / float(nr - 1)))
	var cols := nc if wrap else nc - 1
	for r in nr - 1:
		for c in cols:
			var c1 := (c + 1) % nc
			var a := base + r * nc + c
			var b := base + r * nc + c1
			var d := base + (r + 1) * nc + c
			var e := base + (r + 1) * nc + c1
			_tri_out(a, b, e)
			_tri_out(a, e, d)


## Emits triangle i0,i1,i2 front-facing along its vertices' (outward) normal.
func _tri_out(i0: int, i1: int, i2: int) -> void:
	var nr := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
	var navg := normals[i0] + normals[i1] + normals[i2]
	# Godot front faces are clockwise seen from the front: the right-hand
	# normal of the emitted order must point away from the viewer.
	if nr.dot(navg) > 0.0:
		indices.append_array([i0, i2, i1])
	else:
		indices.append_array([i0, i1, i2])


## Superellipse ring (n points) in the XY plane: half sizes `h`, exponent `p`
## (2 = ellipse, 4+ = rounded box). Starts at the bottom, counter-clockwise.
static func superellipse(h: Vector2, p: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		var a := -PI * 0.5 + TAU * float(k) / float(n)
		var ca := cos(a)
		var sa := sin(a)
		out.append(Vector2(signf(ca) * pow(absf(ca), 2.0 / p) * h.x, signf(sa) * pow(absf(sa), 2.0 / p) * h.y))
	return out


## Smooth body shell along local Z: each section Vector4(z, centre_y, width,
## height) becomes a rounded-box ring (exponent `p`, `n` points). Optional
## flat-ish caps close the ends.
func shell(xf: Transform3D, sections: Array, p: float, n: int, color: Color, caps := true) -> void:
	var rows: Array = []
	var centre := Vector3.ZERO
	for sec: Vector4 in sections:
		var ring := PackedVector3Array()
		for q in superellipse(Vector2(sec.z * 0.5, sec.w * 0.5), p, n):
			ring.append(xf * Vector3(q.x, sec.y + q.y, sec.x))
		rows.append(ring)
		centre += xf * Vector3(0, sec.y, sec.x)
	centre /= float(sections.size())
	grid(rows, color, true, centre)
	if caps:
		for end in [0, rows.size() - 1]:
			var ring: PackedVector3Array = rows[end]
			var sec: Vector4 = sections[end]
			var cpt := xf * Vector3(0, sec.y, sec.x)
			var nrm := (cpt - centre).normalized()
			var ci := _v(cpt, nrm, color)
			var first := verts.size()
			for v in ring:
				_v(v, nrm, color)
			for k in ring.size():
				var a := first + k
				var b := first + (k + 1) % ring.size()
				var tr := (verts[a] - verts[ci]).cross(verts[b] - verts[ci])
				if tr.dot(nrm) > 0.0:
					indices.append_array([ci, b, a])
				else:
					indices.append_array([ci, a, b])


## Tube along a polyline of frames (each Transform3D: origin = centre, basis
## X/Y = profile axes). `profile` points are in the frame's XY plane.
func sweep(frames: Array, profile: PackedVector2Array, color: Color, closed := true) -> void:
	var rows: Array = []
	var centre := Vector3.ZERO
	for f: Transform3D in frames:
		var ring := PackedVector3Array()
		for q in profile:
			ring.append(f * Vector3(q.x, q.y, 0))
		rows.append(ring)
		centre += f.origin
	centre /= float(frames.size())
	if closed:
		# Orient each normal away from its own frame centre (works for bends).
		var base := verts.size()
		grid(rows, color, true, centre)
		var nc := profile.size()
		for r in frames.size():
			var o: Vector3 = (frames[r] as Transform3D).origin
			for c in nc:
				var i := base + r * nc + c
				if normals[i].dot(verts[i] - o) < 0.0:
					normals[i] = -normals[i]
	else:
		grid(rows, color, false, centre)


## Surface of revolution about local Y: `profile` = Vector2(radius, y) from
## bottom to top, `seg` segments. Smooth normals.
func lathe(xf: Transform3D, profile: PackedVector2Array, seg: int, color: Color) -> void:
	var rows: Array = []
	for q in profile:
		var ring := PackedVector3Array()
		for k in seg:
			var a := TAU * float(k) / float(seg)
			ring.append(xf * Vector3(cos(a) * q.x, q.y, sin(a) * q.x))
		rows.append(ring)
	# Normals: radial for the sidewall, axial where the profile runs inward.
	var base := verts.size()
	grid(rows, color, true, xf * Vector3.ZERO)
	var axis := (xf.basis * Vector3.UP).normalized()
	var nc := seg
	for r in profile.size():
		var c0 := xf * Vector3(0, profile[r].y, 0)
		for c in nc:
			var i := base + r * nc + c
			var radial := (verts[i] - c0).normalized()
			var dr := profile[mini(r + 1, profile.size() - 1)] - profile[maxi(r - 1, 0)]
			# Profile tangent (dr) → normal in the (radial, axis) plane.
			var nn := (radial * dr.y - axis * dr.x).normalized()
			normals[i] = nn if nn.length_squared() > 0.5 else radial
	# Re-emit winding consistent with the corrected normals.
	var first_index := indices.size() - (profile.size() - 1) * nc * 6
	var tris := indices.slice(first_index)
	indices.resize(first_index)
	for t in range(0, tris.size(), 3):
		_tri_out(tris[t], tris[t + 1], tris[t + 2])


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
