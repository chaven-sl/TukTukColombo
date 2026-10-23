class_name CharacterBuilder
extends RefCounted
## Stylised adult Sri Lankan characters (v0.03B), generated procedurally.
##
## One rigidly skinned mesh per outfit variant (11 bones, ~2–3k triangles in v0.03B1:
## smooth lathed limbs, shaped torso and shoulders, jaw/ears/hair;
## one draw call per person), shared by every person wearing it; each person
## gets their own Skeleton3D so CharacterRig can pose them independently.
## Variety comes from a small shared part set: tops, lower garments, hair,
## headwear and bags in palette colours — no caricature, no stereotyping.

enum Bone { HIPS, CHEST, HEAD, L_ARM, L_FOREARM, R_ARM, R_FOREARM, L_LEG, L_SHIN, R_LEG, R_SHIN }
enum Top { SHIRT, TEE, BLOUSE, VEST }
enum Lower { TROUSERS, JEANS, SARONG, LONG_SKIRT, SHORTS }
enum Hair { SHORT, BUN, LONG, BALD }
enum Extra { NONE, BACKPACK, HANDBAG, HELMET, SAREE_DRAPE, APRON, CAP, UMBRELLA }

const BONE_NAMES := ["hips", "chest", "head", "l_arm", "l_forearm", "r_arm", "r_forearm", "l_leg", "l_shin", "r_leg", "r_shin"]
const BONE_PARENT := [-1, 0, 1, 1, 3, 1, 5, 0, 7, 0, 9]
## Rest positions relative to the parent bone (model space units = m).
const BONE_REST := [
	Vector3(0, 0.93, 0), Vector3(0, 0.22, 0), Vector3(0, 0.33, 0),
	Vector3(-0.2, 0.25, 0), Vector3(0, -0.29, 0), Vector3(0.2, 0.25, 0), Vector3(0, -0.29, 0),
	Vector3(-0.1, -0.02, 0), Vector3(0, -0.43, 0), Vector3(0.1, -0.02, 0), Vector3(0, -0.43, 0),
]

## 12 outfit variants: [top, lower, hair, extra, top colour idx, lower colour idx, skin idx, scale]
const VARIANTS := [
	[Top.SHIRT, Lower.TROUSERS, Hair.SHORT, Extra.NONE, 0, 8, 0, 1.0],        # office
	[Top.SHIRT, Lower.TROUSERS, Hair.SHORT, Extra.NONE, 1, 9, 2, 0.98],       # casual
	[Top.TEE, Lower.JEANS, Hair.SHORT, Extra.CAP, 3, 2, 1, 1.0],              # tee + cap
	[Top.SHIRT, Lower.SARONG, Hair.BALD, Extra.NONE, 0, 4, 3, 0.97],          # sarong + shirt
	[Top.BLOUSE, Lower.LONG_SKIRT, Hair.BUN, Extra.SAREE_DRAPE, 7, 7, 2, 0.94],  # saree-inspired
	[Top.BLOUSE, Lower.LONG_SKIRT, Hair.LONG, Extra.HANDBAG, 5, 6, 0, 0.93],  # long skirt + blouse
	[Top.VEST, Lower.SARONG, Hair.SHORT, Extra.APRON, 0, 10, 3, 0.99],        # vendor
	[Top.SHIRT, Lower.TROUSERS, Hair.SHORT, Extra.BACKPACK, 0, 2, 4, 0.96],   # backpack commuter
	[Top.TEE, Lower.JEANS, Hair.SHORT, Extra.HELMET, 8, 2, 1, 1.0],           # rider
	[Top.BLOUSE, Lower.TROUSERS, Hair.BUN, Extra.HANDBAG, 10, 8, 4, 0.95],    # blouse + trousers
	[Top.SHIRT, Lower.SARONG, Hair.SHORT, Extra.UMBRELLA, 9, 9, 0, 0.95],     # elder with umbrella
	[Top.TEE, Lower.SHORTS, Hair.SHORT, Extra.NONE, 4, 9, 3, 1.0],            # labourer
]

static var _mesh_cache: Dictionary = {}
static var _static_cache: Dictionary = {}
## Segment scale while building (static crowd figures use a low-detail build).
static var _seg := 1.0


static func variant_count() -> int:
	return VARIANTS.size()


## Shared skinned mesh for a variant (built once).
static func mesh_for(variant: int) -> ArrayMesh:
	variant = posmod(variant, VARIANTS.size())
	if _mesh_cache.has(variant):
		return _mesh_cache[variant]
	var m := _build(VARIANTS[variant])
	_mesh_cache[variant] = m
	return m


static func clear_cache() -> void:
	_mesh_cache.clear()
	_static_cache.clear()


## Model-space rest position of each bone.
static func bone_global_rest(i: int) -> Vector3:
	var p := Vector3.ZERO
	var b := i
	while b >= 0:
		p += BONE_REST[b]
		b = BONE_PARENT[b]
	return p


static func make_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	for i in BONE_NAMES.size():
		sk.add_bone(BONE_NAMES[i])
	for i in BONE_NAMES.size():
		if BONE_PARENT[i] >= 0:
			sk.set_bone_parent(i, BONE_PARENT[i])
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, BONE_REST[i]))
		sk.set_bone_pose_position(i, BONE_REST[i])
	return sk


## Unskinned copy of a variant in its rest pose, for baking static
## background figures into district chunks (v0.03B1 crowd layer).
static func static_figure(variant: int) -> ArtMesh:
	variant = posmod(variant, VARIANTS.size())
	if _static_cache.has(variant):
		return _static_cache[variant]
	_seg = 0.3
	var m := _build_art(VARIANTS[variant])
	_seg = 1.0
	var plain := ArtMesh.new()
	plain.append(m)
	_static_cache[variant] = plain
	return plain


static func _build(v: Array) -> ArrayMesh:
	return _build_art(v).commit(ArtMaterials.get_material(&"plaster"))


## Tapered limb hanging from `top` (bone-local rest point) down `length`,
## radius `r_top` → `r_bot`, rounded ends. Smooth (lathe).
static func _limb(m: ArtMesh, top: Vector3, length: float, r_top: float, r_bot: float, color: Color, seg: int = 9) -> void:
	if _seg < 1.0:  # low-detail crowd build: a simple tapered capsule
		m.lathe(Transform3D(Basis.IDENTITY, top), PackedVector2Array([Vector2(0.0, -length - r_bot * 0.3), Vector2(r_bot, -length),
				Vector2(r_top, 0.0), Vector2(0.0, r_top * 0.5)]), 5, color)
		return
	m.lathe(Transform3D(Basis.IDENTITY, top), PackedVector2Array([
		Vector2(0.0, -length - r_bot * 0.4), Vector2(r_bot * 0.75, -length - r_bot * 0.15), Vector2(r_bot, -length * 0.92),
		Vector2(lerpf(r_bot, r_top, 0.55), -length * 0.45), Vector2(r_top, -length * 0.08), Vector2(r_top * 0.7, r_top * 0.4),
		Vector2(0.0, r_top * 0.6)]), maxi(4, int(seg * _seg)), color)


## Vertical body shell: sections Vector4(y, z offset, width, depth).
static func _vshell(m: ArtMesh, base: Vector3, sections: Array, color: Color, p := 2.6, n := 14) -> void:
	var secs: Array = []
	for q: Vector4 in sections:
		secs.append(Vector4(q.x, -q.y, q.z, q.w))
	m.shell(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), base), secs, p, maxi(6, int(n * _seg)), color, true)


static func _sph(m: ArtMesh, c: Vector3, r: Vector3, color: Color, seg: int, rings: int) -> void:
	m.sphere(Transform3D.IDENTITY, c, r, color, maxi(4, int(seg * _seg)), maxi(3, int(rings * _seg)))


static func _build_art(v: Array) -> ArtMesh:
	var top: int = v[0]
	var lower: int = v[1]
	var hair: int = v[2]
	var extra: int = v[3]
	var top_c: Color = ArtPalette.CLOTH[v[4]]
	var low_c: Color = ArtPalette.CLOTH[v[5]]
	var skin: Color = ArtPalette.SKIN[v[6]]
	var k: float = v[7]
	var female := top == Top.BLOUSE
	var m := ArtMesh.new()
	m.skinned = true
	var I := Transform3D.IDENTITY
	var hair_c := Color(0.07, 0.06, 0.06) if hair != Hair.BALD else skin
	var shoe := Color(0.13, 0.1, 0.08)
	var at := func(bone_i: int) -> Vector3: return bone_global_rest(bone_i) * k
	var hips: Vector3 = at.call(Bone.HIPS)
	var chest: Vector3 = at.call(Bone.CHEST)
	var head: Vector3 = at.call(Bone.HEAD)
	# --- pelvis (lower garment colour) ---
	m.bone = Bone.HIPS
	_vshell(m, Vector3(0, 0, 0), [Vector4(hips.y - 0.1 * k, 0, 0.3 * k, 0.19 * k), Vector4(hips.y + 0.02 * k, 0, 0.32 * k, 0.2 * k),
			Vector4(hips.y + 0.1 * k, 0, 0.29 * k, 0.19 * k)], low_c)
	# --- torso: waist → chest → shoulders, sloped shoulder line ---
	m.bone = Bone.CHEST
	var sw := (0.34 if female else 0.4) * k
	_vshell(m, Vector3(0, 0, 0), [
		Vector4(hips.y + 0.08 * k, 0.0, (0.27 if female else 0.3) * k, 0.18 * k),
		Vector4(chest.y + 0.0 * k, 0.005 * k, (0.29 if female else 0.33) * k, (0.21 if female else 0.2) * k),
		Vector4(chest.y + 0.14 * k, 0.0, sw, 0.21 * k),
		Vector4(chest.y + 0.22 * k, -0.005 * k, sw * 0.96, 0.19 * k),
		Vector4(chest.y + 0.27 * k, -0.01 * k, sw * 0.6, 0.13 * k)], top_c, 2.8, 16)
	if top == Top.SHIRT:  # collar + placket
		m.shell(Transform3D(Basis.IDENTITY, chest + Vector3(0, 0.27, 0.0) * k), [Vector4(-0.06 * k, 0.0, 0.15 * k, 0.05 * k), Vector4(0.07 * k, 0.0, 0.16 * k, 0.05 * k)], 2.0, 10, top_c.lightened(0.12), false)
		m.box(I, chest + Vector3(0, 0.08, 0.104) * k, Vector3(0.022, 0.36, 0.006) * k, top_c.darkened(0.14))
	if top == Top.VEST:
		m.box(I, chest + Vector3(0, 0.1, 0.1) * k, Vector3(0.16, 0.28, 0.006) * k, ArtPalette.CLOTH[0])
	if extra == Extra.SAREE_DRAPE:  # pallu over the left shoulder, across the torso
		var accent := ArtPalette.ACCENTS[0]
		var a := Transform3D(Basis(Vector3.FORWARD, 0.55), chest + Vector3(-0.02, 0.08, 0.108) * k)
		m.box(a, Vector3.ZERO, Vector3(0.13, 0.56, 0.012) * k, top_c.lightened(0.15))
		m.box(a, Vector3(-0.07, 0, 0.002) * k, Vector3(0.014, 0.56, 0.012) * k, accent)
		m.box(Transform3D(Basis.IDENTITY, chest + Vector3(-0.12, 0.05, -0.1) * k), Vector3.ZERO, Vector3(0.12, 0.5, 0.012) * k, top_c.lightened(0.15))
	if extra == Extra.APRON:
		m.box(I, chest + Vector3(0, -0.14, 0.106) * k, Vector3(0.3, 0.52, 0.01) * k, ArtPalette.CLOTH[9])
	if extra == Extra.BACKPACK:
		m.shell(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), chest + Vector3(0, 0.07, -0.16) * k), [Vector4(-0.18 * k, 0, 0.28 * k, 0.12 * k), Vector4(0.18 * k, 0, 0.27 * k, 0.12 * k)], 3.0, 12, ArtPalette.CLOTH[2].darkened(0.25))
	# --- neck + head: smaller, rounder skull, jaw, ears, nose ---
	m.bone = Bone.HEAD
	_limb(m, head + Vector3(0, 0.0, 0.0), 0.08 * k, 0.05 * k, 0.055 * k, skin, 8)
	_sph(m, head + Vector3(0, 0.115, 0.0) * k, Vector3(0.096, 0.112, 0.105) * k, skin, 12, 8)
	_sph(m, head + Vector3(0, 0.055, 0.03) * k, Vector3(0.078, 0.06, 0.08) * k, skin, 10, 5)  # jaw
	if _seg >= 1.0:  # face details only on the full-detail (animated) build
		_sph(m, head + Vector3(0, 0.1, 0.105) * k, Vector3(0.018, 0.026, 0.022) * k, skin.darkened(0.06), 6, 4)  # nose
	for sx: float in ([-1.0, 1.0] if _seg >= 1.0 else []):
		_sph(m, head + Vector3(sx * 0.095, 0.11, 0.0) * k, Vector3(0.016, 0.03, 0.022) * k, skin.darkened(0.05), 6, 4)  # ears
		_sph(m, head + Vector3(sx * 0.035, 0.13, 0.095) * k, Vector3(0.012, 0.008, 0.006) * k, Color(0.08, 0.06, 0.05), 5, 3)  # eyes
	match hair:
		Hair.SHORT:
			_sph(m, head + Vector3(0, 0.155, -0.012) * k, Vector3(0.102, 0.085, 0.11) * k, hair_c, 12, 6)
		Hair.BUN:
			_sph(m, head + Vector3(0, 0.15, -0.015) * k, Vector3(0.104, 0.09, 0.112) * k, hair_c, 12, 6)
			_sph(m, head + Vector3(0, 0.1, -0.13) * k, Vector3(0.058, 0.055, 0.05) * k, hair_c, 8, 5)
		Hair.LONG:
			_sph(m, head + Vector3(0, 0.15, -0.015) * k, Vector3(0.106, 0.092, 0.114) * k, hair_c, 12, 6)
			m.shell(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), head + Vector3(0, 0.0, -0.075) * k), [Vector4(-0.2 * k, 0, 0.17 * k, 0.06 * k), Vector4(0.12 * k, 0, 0.2 * k, 0.07 * k)], 3.0, 10, hair_c)
	match extra:
		Extra.HELMET:
			_sph(m, head + Vector3(0, 0.14, -0.01) * k, Vector3(0.135, 0.13, 0.145) * k, ArtPalette.ACCENTS[1], 12, 7)
			m.box(I, head + Vector3(0, 0.1, 0.13) * k, Vector3(0.19, 0.06, 0.025) * k, ArtPalette.GLASS)
		Extra.CAP:
			_sph(m, head + Vector3(0, 0.18, -0.01) * k, Vector3(0.108, 0.06, 0.115) * k, ArtPalette.ACCENTS[2], 10, 5)
			m.box(I, head + Vector3(0, 0.15, 0.14) * k, Vector3(0.15, 0.014, 0.09) * k, ArtPalette.ACCENTS[2])
	# --- arms: shoulder cap, upper arm, forearm, hand ---
	var short_sleeve := top == Top.TEE or top == Top.BLOUSE or top == Top.VEST
	for side: int in [-1, 1]:
		var arm_bone := Bone.L_ARM if side < 0 else Bone.R_ARM
		var fore_bone := Bone.L_FOREARM if side < 0 else Bone.R_FOREARM
		var sh: Vector3 = at.call(arm_bone)
		m.bone = arm_bone
		var upper_c := skin if top == Top.VEST else top_c
		_limb(m, sh + Vector3(-side * 0.005, 0.0, 0.0) * k, 0.27 * k, 0.058 * k, 0.046 * k, upper_c if not short_sleeve else skin)
		if short_sleeve and top != Top.VEST:
			_limb(m, sh + Vector3(0, 0.01, 0) * k, 0.11 * k, 0.066 * k, 0.06 * k, top_c)
		var el: Vector3 = at.call(fore_bone)
		m.bone = fore_bone
		_limb(m, el, 0.25 * k, 0.045 * k, 0.034 * k, top_c if top == Top.SHIRT else skin)
		if top == Top.SHIRT:
			_limb(m, el + Vector3(0, -0.2, 0) * k, 0.06 * k, 0.034 * k, 0.03 * k, skin)
		m.shell(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), el + Vector3(0, -0.3, 0.005) * k), [Vector4(-0.05 * k, 0, 0.055 * k, 0.03 * k), Vector4(0.03 * k, 0, 0.06 * k, 0.035 * k)], 2.4, 8, skin)  # hand
		if side < 0 and extra == Extra.HANDBAG:
			m.shell(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), el + Vector3(-0.045, -0.36, 0) * k), [Vector4(-0.1 * k, 0, 0.07 * k, 0.24 * k), Vector4(0.08 * k, 0, 0.06 * k, 0.22 * k)], 4.0, 10, ArtPalette.BRICK.darkened(0.2))
		if side > 0 and extra == Extra.UMBRELLA:  # closed umbrella carried like a cane
			m.cylinder(I, el + Vector3(0, -0.55, 0.05) * k, 0.03 * k, 0.6 * k, 6, Color(0.1, 0.1, 0.12), true, 0.012 * k)
	# --- legs / footwear ---
	for side: int in [-1, 1]:
		var leg_bone := Bone.L_LEG if side < 0 else Bone.R_LEG
		var shin_bone := Bone.L_SHIN if side < 0 else Bone.R_SHIN
		var hip: Vector3 = at.call(leg_bone)
		m.bone = leg_bone
		var trousers := lower == Lower.TROUSERS or lower == Lower.JEANS
		_limb(m, hip, 0.42 * k, 0.088 * k, 0.062 * k, low_c if lower != Lower.SHORTS else low_c, 10)
		var knee: Vector3 = at.call(shin_bone)
		m.bone = shin_bone
		_limb(m, knee, 0.4 * k, 0.06 * k, 0.04 * k, low_c if trousers else skin, 10)
		if lower == Lower.SHORTS:
			_limb(m, knee + Vector3(0, 0.22, 0) * k, 0.14 * k, 0.075 * k, 0.07 * k, low_c, 10)
		var sandal := lower == Lower.SARONG or lower == Lower.LONG_SKIRT or lower == Lower.SHORTS
		m.shell(Transform3D(Basis.IDENTITY, knee + Vector3(0, -0.425, 0.035) * k),
				[Vector4(-0.09 * k, 0.0, 0.085 * k, 0.05 * k), Vector4(0.02 * k, 0.01 * k, 0.095 * k, 0.07 * k), Vector4(0.13 * k, -0.005 * k, 0.08 * k, 0.045 * k)],
				2.6, 10, shoe if not sandal else Color(0.3, 0.2, 0.12))
	if lower == Lower.SARONG or lower == Lower.LONG_SKIRT:
		# Wrap skirt rides with the hips; legs animate inside it, feet show below.
		m.bone = Bone.HIPS
		var length := (0.74 if lower == Lower.LONG_SKIRT else 0.68) * k
		var hem := (0.21 if lower == Lower.LONG_SKIRT else 0.18) * k
		var y0 := hips.y + 0.08 * k
		m.lathe(I, PackedVector2Array([Vector2(hem * 0.92, y0 - length), Vector2(hem, y0 - length + 0.03 * k), Vector2(hem * 0.86, y0 - length * 0.5),
				Vector2(0.165 * k, y0 - 0.06 * k), Vector2(0.15 * k, y0)]), maxi(6, int(14 * _seg)), low_c)
		if lower == Lower.SARONG:  # woven band near the hem
			m.lathe(I, PackedVector2Array([Vector2(hem * 1.005, y0 - length + 0.1 * k), Vector2(hem * 0.98, y0 - length + 0.16 * k)]), maxi(6, int(14 * _seg)), low_c.darkened(0.35))
	return m
