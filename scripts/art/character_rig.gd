class_name CharacterRig
extends Node3D
## Presentation for one person (v0.03B): a per-person Skeleton3D posing a
## shared CharacterBuilder mesh with cheap procedural animation. Purely
## visual — HumanAgent logic decides state; this only reads it.

enum Mode { IDLE, WALK, HURRY, RUN, EVADE, DIVE, WAIT, SEATED, BOARD, ARGUE, DRIVE }

const B := CharacterBuilder.Bone

var variant := 0
var mode: Mode = Mode.IDLE
const ALL_BONES: Array[int] = [B.HIPS, B.CHEST, B.HEAD, B.L_ARM, B.L_FOREARM, B.R_ARM, B.R_FOREARM, B.L_LEG, B.L_SHIN, B.R_LEG, B.R_SHIN]
## Walk cycle speed in m/s (drives stride frequency).
var move_speed := 1.3
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
## Animation is skipped when farther than this from the camera (LOD).
var animate_distance := 55.0

var _phase := 0.0
var _gesture := 0.0
var _seed := 0.0


func _init(p_variant: int = 0) -> void:
	variant = p_variant
	_seed = float(p_variant) * 1.37


func _ready() -> void:
	skeleton = CharacterBuilder.make_skeleton()
	skeleton.name = "Skeleton"
	# Modelled facing +Z; Godot forward (HumanAgent.face) is -Z. In mesh-local
	# terms a negative X rotation swings a limb forward.
	skeleton.rotation.y = PI
	add_child(skeleton)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Body"
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	set_variant(variant)


func set_variant(v: int) -> void:
	variant = posmod(v, CharacterBuilder.variant_count())
	if mesh_instance == null:
		return
	mesh_instance.mesh = CharacterBuilder.mesh_for(variant)
	mesh_instance.skin = skeleton.create_skin_from_rest_transforms()


## One-shot reaction (passenger comment, shout): arms up briefly.
func gesture(seconds: float = 0.8) -> void:
	_gesture = seconds


func _rot(bone: int, x: float, y: float = 0.0, z: float = 0.0) -> void:
	skeleton.set_bone_pose_rotation(bone, Quaternion.from_euler(Vector3(x, y, z)))


func animate(delta: float, camera_pos: Vector3) -> void:
	if skeleton == null or not is_visible_in_tree():
		return
	if global_position.distance_squared_to(camera_pos) > animate_distance * animate_distance:
		return
	var freq := 1.0
	match mode:
		Mode.WALK, Mode.BOARD:
			freq = move_speed * 4.3
		Mode.HURRY:
			freq = move_speed * 4.0
		Mode.RUN, Mode.EVADE:
			freq = 11.0
		Mode.DIVE:
			freq = 0.0
		_:
			freq = 1.6
	_phase = fmod(_phase + delta * freq, TAU * 64.0)
	_gesture = maxf(_gesture - delta, 0.0)
	var s := sin(_phase)
	var c := cos(_phase)
	var hips_y := CharacterBuilder.BONE_REST[B.HIPS].y
	skeleton.set_bone_pose_position(B.HIPS, Vector3(0, hips_y, 0))
	# Neutral.
	for b in ALL_BONES:
		skeleton.set_bone_pose_rotation(b, Quaternion.IDENTITY)
	match mode:
		Mode.IDLE, Mode.WAIT:
			var breathe := sin(_phase + _seed) * 0.02
			_rot(B.CHEST, breathe)
			_rot(B.HEAD, sin(_phase * 0.35 + _seed) * 0.08, sin(_phase * 0.2 + _seed) * 0.3)
			# Per-person idle stance so groups don't look cloned.
			match int(_seed * 7.0) % 4:
				0:
					_rot(B.L_ARM, 0.05, 0, 0.08)
					_rot(B.R_ARM, 0.05, 0, -0.08)
					_rot(B.L_FOREARM, -0.15)
					_rot(B.R_FOREARM, -0.15)
				1:  # hands clasped in front
					_rot(B.L_ARM, -0.25, 0, -0.18)
					_rot(B.R_ARM, -0.25, 0, 0.18)
					_rot(B.L_FOREARM, -0.9, 0.5)
					_rot(B.R_FOREARM, -0.9, -0.5)
				2:  # hand on hip, weight on one leg
					_rot(B.R_ARM, 0.1, 0, -0.65)
					_rot(B.R_FOREARM, -1.5)
					_rot(B.L_ARM, 0.05, 0, 0.08)
					_rot(B.HIPS, 0.0, 0.0, 0.06)
					_rot(B.L_LEG, 0.0, 0.0, -0.08)
				_:  # arms folded
					_rot(B.L_ARM, -0.5, 0, -0.25)
					_rot(B.R_ARM, -0.5, 0, 0.25)
					_rot(B.L_FOREARM, -1.7, 0.6)
					_rot(B.R_FOREARM, -1.7, -0.6)
		Mode.WALK, Mode.BOARD, Mode.HURRY:
			# v0.03B1: longer stride, knee lift on the swing leg, arms swing
			# opposite with elbows bending forward, pelvis/chest counter-twist.
			var amp := 0.55 if mode != Mode.HURRY else 0.72
			_rot(B.L_LEG, s * amp)
			_rot(B.R_LEG, -s * amp)
			_rot(B.L_SHIN, -maxf(-c, 0.0) * amp * 1.5 - 0.05)
			_rot(B.R_SHIN, -maxf(c, 0.0) * amp * 1.5 - 0.05)
			_rot(B.L_ARM, -s * amp * 0.85, 0, 0.07)
			_rot(B.R_ARM, s * amp * 0.85, 0, -0.07)
			_rot(B.L_FOREARM, -0.3 - maxf(-s, 0.0) * 0.45)
			_rot(B.R_FOREARM, -0.3 - maxf(s, 0.0) * 0.45)
			_rot(B.HIPS, 0.0, s * 0.08)
			_rot(B.CHEST, 0.05 if mode != Mode.HURRY else 0.18, -s * 0.12)
			_rot(B.HEAD, -0.03, s * 0.05)
			skeleton.set_bone_pose_position(B.HIPS, Vector3(0, hips_y + absf(c) * 0.03, 0))
		Mode.RUN, Mode.EVADE:
			_rot(B.L_LEG, s * 1.05 - 0.1)
			_rot(B.R_LEG, -s * 1.05 - 0.1)
			_rot(B.L_SHIN, -maxf(-c, 0.0) * 1.9 - 0.2)
			_rot(B.R_SHIN, -maxf(c, 0.0) * 1.9 - 0.2)
			_rot(B.L_ARM, -s * 1.1, 0, 0.14)
			_rot(B.R_ARM, s * 1.1, 0, -0.14)
			_rot(B.L_FOREARM, -1.45)
			_rot(B.R_FOREARM, -1.45)
			_rot(B.HIPS, 0.12, s * 0.1)
			_rot(B.CHEST, 0.32, -s * 0.15)
			_rot(B.HEAD, -0.28)
			skeleton.set_bone_pose_position(B.HIPS, Vector3(0, hips_y - 0.03 + absf(c) * 0.08, 0))
		Mode.DIVE:
			# Throwing themselves aside: body pitched, arms out, legs trailing.
			_rot(B.HIPS, 1.1, 0.0, 0.25)
			_rot(B.CHEST, 0.45, 0.0, 0.15)
			_rot(B.HEAD, -0.75)
			_rot(B.L_ARM, -2.7, 0, 0.45)
			_rot(B.R_ARM, -2.5, 0, -0.35)
			_rot(B.L_FOREARM, -0.2)
			_rot(B.R_FOREARM, -0.35)
			_rot(B.L_LEG, -0.75)
			_rot(B.R_LEG, 0.35)
			_rot(B.L_SHIN, -1.2)
			_rot(B.R_SHIN, -0.25)
			skeleton.set_bone_pose_position(B.HIPS, Vector3(0, hips_y - 0.35, 0))
		Mode.SEATED, Mode.DRIVE:
			_rot(B.L_LEG, -1.5)
			_rot(B.R_LEG, -1.5)
			_rot(B.L_SHIN, 1.45)
			_rot(B.R_SHIN, 1.45)
			if mode == Mode.DRIVE:
				_rot(B.L_ARM, -1.1, 0, 0.25)
				_rot(B.R_ARM, -1.1, 0, -0.25)
				_rot(B.L_FOREARM, -0.5)
				_rot(B.R_FOREARM, -0.5)
				_rot(B.HEAD, 0.05, sin(_phase * 0.4) * 0.15)
			else:
				# Passenger: sitting back, hands resting on the knees, looking
				# around at the street (head stays visible above the backrest).
				_rot(B.CHEST, -0.12, sin(_phase * 0.11 + _seed) * 0.1)
				_rot(B.L_ARM, -0.55, 0, 0.18)
				_rot(B.R_ARM, -0.55, 0, -0.18)
				_rot(B.L_FOREARM, -0.75)
				_rot(B.R_FOREARM, -0.75)
				_rot(B.HEAD, 0.05 + sin(_phase * 0.3 + _seed) * 0.06, sin(_phase * 0.17 + _seed) * 0.55)
		Mode.ARGUE:
			# Animated, insistent gestures — never contact.
			# Pointing / both-hands-open gestures, leaning in, head jabbing.
			var g := sin(_phase * 3.5)
			var g2 := sin(_phase * 1.3 + _seed)
			_rot(B.R_ARM, -1.5 + g * 0.55, 0, -0.25)
			_rot(B.R_FOREARM, -0.45 + g * 0.45)
			_rot(B.L_ARM, -0.7 - maxf(g2, 0.0) * 0.8, 0, 0.55 + maxf(g2, 0.0) * 0.4)
			_rot(B.L_FOREARM, -1.2 + maxf(g2, 0.0) * 0.6)
			_rot(B.HIPS, 0.0, g2 * 0.12)
			_rot(B.CHEST, 0.18 + g * 0.06, sin(_phase * 1.7) * 0.2)
			_rot(B.HEAD, 0.12 + g * 0.12, g2 * 0.15)
			_rot(B.L_LEG, -0.12)
			_rot(B.R_LEG, 0.1)
	if _gesture > 0.0:
		var up := sin(clampf(_gesture / 0.8, 0.0, 1.0) * PI)
		_rot(B.L_ARM, -2.2 * up, 0, 0.3 * up)
		_rot(B.R_ARM, -2.2 * up, 0, -0.3 * up)
		_rot(B.HEAD, -0.25 * up)
