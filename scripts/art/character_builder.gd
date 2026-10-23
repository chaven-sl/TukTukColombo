class_name CharacterBuilder
extends RefCounted
## Stylised adult Sri Lankan characters (v0.03B), generated procedurally.
##
## One rigidly skinned mesh per outfit variant (11 bones, ~1–1.4k triangles,
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


static func _build(v: Array) -> ArrayMesh:
	var top: int = v[0]
	var lower: int = v[1]
	var hair: int = v[2]
	var extra: int = v[3]
	var top_c: Color = ArtPalette.CLOTH[v[4]]
	var low_c: Color = ArtPalette.CLOTH[v[5]]
	var skin: Color = ArtPalette.SKIN[v[6]]
	var k: float = v[7]
	var m := ArtMesh.new()
	m.skinned = true
	var I := Transform3D.IDENTITY
	var hair_c := Color(0.08, 0.07, 0.07) if hair != Hair.BALD else skin
	var shoe := Color(0.12, 0.1, 0.09)
	var at := func(bone_i: int) -> Vector3: return bone_global_rest(bone_i) * k
	# --- hips / lower body ---
	m.bone = Bone.HIPS
	var hips: Vector3 = at.call(Bone.HIPS)
	m.bevel_box(I, hips + Vector3(0, 0.02, 0) * k, Vector3(0.34, 0.2, 0.2) * k, 0.05 * k, low_c)
	# --- torso ---
	m.bone = Bone.CHEST
	var chest: Vector3 = at.call(Bone.CHEST)
	var torso_h := 0.44 * k
	var torso_w := (0.36 if top != Top.BLOUSE else 0.33) * k
	m.bevel_box(I, chest + Vector3(0, 0.06, 0) * k, Vector3(torso_w, torso_h, 0.21 * k), 0.06 * k, top_c)
	if top == Top.SHIRT:  # collar + placket
		m.box(I, chest + Vector3(0, 0.27, 0.06) * k, Vector3(0.14, 0.04, 0.1) * k, top_c.lightened(0.1))
		m.box(I, chest + Vector3(0, 0.06, 0.106) * k, Vector3(0.025, 0.36, 0.005) * k, top_c.darkened(0.12))
	if top == Top.VEST:  # bare arms vest + undershirt
		m.box(I, chest + Vector3(0, 0.08, 0.108) * k, Vector3(0.18, 0.3, 0.005) * k, ArtPalette.CLOTH[0])
	if extra == Extra.SAREE_DRAPE:  # pallu across the torso from the left shoulder
		var accent := ArtPalette.ACCENTS[0]
		var a := Transform3D(Basis(Vector3.FORWARD, 0.55), chest + Vector3(-0.02, 0.06, 0.115) * k)
		m.box(a, Vector3.ZERO, Vector3(0.12, 0.52, 0.01) * k, top_c.lightened(0.12))
		m.box(a, Vector3(-0.065, 0, 0) * k, Vector3(0.012, 0.52, 0.012) * k, accent)
	if extra == Extra.APRON:
		m.box(I, chest + Vector3(0, -0.12, 0.11) * k, Vector3(0.3, 0.5, 0.01) * k, ArtPalette.CLOTH[9])
	if extra == Extra.BACKPACK:
		m.bevel_box(I, chest + Vector3(0, 0.05, -0.16) * k, Vector3(0.28, 0.36, 0.13) * k, 0.04 * k, ArtPalette.CLOTH[2].darkened(0.2))
	# --- head ---
	m.bone = Bone.HEAD
	var head: Vector3 = at.call(Bone.HEAD)
	m.cylinder(I, head + Vector3(0, -0.06, 0) * k, 0.055 * k, 0.1 * k, 6, skin, false)
	m.sphere(I, head + Vector3(0, 0.1, 0.01) * k, Vector3(0.105, 0.125, 0.115) * k, skin, 9, 6)
	m.box(I, head + Vector3(0, 0.08, 0.115) * k, Vector3(0.03, 0.05, 0.03) * k, skin.darkened(0.08))  # nose
	match hair:
		Hair.SHORT:
			m.sphere(I, head + Vector3(0, 0.175, -0.035) * k, Vector3(0.11, 0.08, 0.11) * k, hair_c, 8, 4)
		Hair.BUN:
			m.sphere(I, head + Vector3(0, 0.17, -0.04) * k, Vector3(0.112, 0.085, 0.115) * k, hair_c, 8, 4)
			m.sphere(I, head + Vector3(0, 0.1, -0.13) * k, Vector3(0.06, 0.06, 0.06) * k, hair_c, 6, 4)
		Hair.LONG:
			m.sphere(I, head + Vector3(0, 0.165, -0.04) * k, Vector3(0.115, 0.09, 0.118) * k, hair_c, 8, 4)
			m.box(I, head + Vector3(0, -0.05, -0.08) * k, Vector3(0.2, 0.3, 0.06) * k, hair_c)
	match extra:
		Extra.HELMET:
			m.sphere(I, head + Vector3(0, 0.15, -0.02) * k, Vector3(0.14, 0.13, 0.15) * k, ArtPalette.ACCENTS[1], 9, 5)
			m.box(I, head + Vector3(0, 0.11, 0.13) * k, Vector3(0.2, 0.06, 0.03) * k, ArtPalette.GLASS)
		Extra.CAP:
			m.sphere(I, head + Vector3(0, 0.19, -0.02) * k, Vector3(0.115, 0.065, 0.12) * k, ArtPalette.ACCENTS[2], 8, 4)
			m.box(I, head + Vector3(0, 0.15, 0.15) * k, Vector3(0.16, 0.015, 0.1) * k, ArtPalette.ACCENTS[2])
	# --- arms ---
	var sleeve := top_c if top != Top.VEST else skin
	for side: int in [-1, 1]:
		var arm_bone := Bone.L_ARM if side < 0 else Bone.R_ARM
		var fore_bone := Bone.L_FOREARM if side < 0 else Bone.R_FOREARM
		var sh: Vector3 = at.call(arm_bone)
		m.bone = arm_bone
		var short_sleeve := top == Top.TEE or top == Top.BLOUSE
		m.cylinder(I, sh + Vector3(0, -0.14, 0) * k, 0.055 * k, 0.29 * k, 6, sleeve if not short_sleeve else skin, true, 0.06 * k)
		if short_sleeve:
			m.cylinder(I, sh + Vector3(0, -0.05, 0) * k, 0.065 * k, 0.12 * k, 6, top_c, true)
		var el: Vector3 = at.call(fore_bone)
		m.bone = fore_bone
		m.cylinder(I, el + Vector3(0, -0.13, 0) * k, 0.045 * k, 0.27 * k, 6, skin if top != Top.SHIRT else top_c, true, 0.05 * k)
		if top == Top.SHIRT:
			m.cylinder(I, el + Vector3(0, -0.22, 0) * k, 0.043 * k, 0.09 * k, 6, skin, true)
		m.sphere(I, el + Vector3(0, -0.3, 0.01) * k, Vector3(0.045, 0.06, 0.035) * k, skin, 6, 4)  # hand
		if side < 0 and extra == Extra.HANDBAG:
			m.box(I, el + Vector3(-0.04, -0.4, 0) * k, Vector3(0.06, 0.18, 0.24) * k, ArtPalette.BRICK.darkened(0.2))
		if side > 0 and extra == Extra.UMBRELLA:  # closed umbrella carried like a cane
			m.cylinder(I, el + Vector3(0, -0.55, 0.05) * k, 0.03 * k, 0.6 * k, 5, Color(0.1, 0.1, 0.12), true, 0.01 * k)
	# --- legs / lower garment ---
	for side: int in [-1, 1]:
		var leg_bone := Bone.L_LEG if side < 0 else Bone.R_LEG
		var shin_bone := Bone.L_SHIN if side < 0 else Bone.R_SHIN
		var hip: Vector3 = at.call(leg_bone)
		m.bone = leg_bone
		var thigh_c := low_c if lower != Lower.SHORTS else low_c
		m.cylinder(I, hip + Vector3(0, -0.21, 0) * k, 0.085 * k, 0.43 * k, 7, thigh_c, true, 0.075 * k)
		var knee: Vector3 = at.call(shin_bone)
		m.bone = shin_bone
		var shin_c := low_c if (lower == Lower.TROUSERS or lower == Lower.JEANS) else skin
		m.cylinder(I, knee + Vector3(0, -0.21, 0) * k, 0.06 * k, 0.42 * k, 7, shin_c, true, 0.055 * k)
		m.bevel_box(I, knee + Vector3(0, -0.45, 0.05) * k, Vector3(0.1, 0.07, 0.24) * k, 0.03 * k, shoe)
	if lower == Lower.SARONG or lower == Lower.LONG_SKIRT:
		# Wrap skirt rides with the hips; legs animate inside it, feet show below.
		m.bone = Bone.HIPS
		var length := (0.72 if lower == Lower.LONG_SKIRT else 0.66) * k
		var hem_r := (0.2 if lower == Lower.LONG_SKIRT else 0.17) * k
		m.cylinder(I, hips + Vector3(0, -length * 0.5 + 0.05 * k, 0), hem_r, length, 9, low_c, false, 0.17 * k)
		if lower == Lower.SARONG:  # woven band
			m.cylinder(I, hips + Vector3(0, -length + 0.12 * k, 0), hem_r * 1.01, 0.05 * k, 9, low_c.darkened(0.3), false)
	return m.commit(ArtMaterials.get_material(&"plaster"))
