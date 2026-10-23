class_name ImpactPropManager
extends Node3D
## Light street clutter that reacts to the tuk (v0.03A2): roadside signs,
## market box stacks, cones, stall boards, shop displays.
##
## Deliberately NOT physics bodies: they never stop the tuk (buildings and
## walls do that). Each tick the few props near the player are tested against
## the tuk footprint (same cheap OrientedRect test as people). A hit makes a
## prop wobble (slow) or get knocked flying with a simple ballistic tumble;
## box stacks / displays also shed pooled debris pieces. Knocked props settle,
## shrink away and respawn later out of view. Fixed pools, no allocation
## during play, capped active debris.

enum Kind { SIGN, BOXES, CONE, STALL_BOARD, DISPLAY }
enum PropState { STANDING, WOBBLING, KNOCKED, SETTLED, GONE }

const MAX_PROPS := 16
const DEBRIS_POOL := 18
const KNOCK_MIN_KMH := 6.0
const RESPAWN_SECONDS := 25.0

var player: TukController
var camera: Camera3D

# Per-prop parallel arrays (fixed size; no per-frame allocation).
var nodes: Array[MeshInstance3D] = []
var kinds := PackedInt32Array()
var states := PackedInt32Array()
var home: Array[Transform3D] = []
var radius := PackedFloat32Array()
var vel := PackedVector3Array()
var spin := PackedVector3Array()
var timer := PackedFloat32Array()

var _debris: Array[MeshInstance3D] = []
var _debris_vel := PackedVector3Array()
var _debris_t := PackedFloat32Array()
var _next_debris := 0

# Diagnostics.
var stats_knocked := 0
var stats_wobbles := 0
var stats_respawns := 0


func setup(network: RoadNetwork, p_player: TukController, p_camera: Camera3D, seed_value: int = 1) -> void:
	player = p_player
	camera = p_camera
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var spots := _spot_positions(network)
	for seg in network.segments:
		for side: float in [-1.0, 1.0]:
			if not seg.has_sidewalk(side) or nodes.size() >= MAX_PROPS:
				continue
			var s := 14.0 + rng.randf() * 10.0
			while s < seg.length - 10.0 and nodes.size() < MAX_PROPS:
				var near_crossing := false
				for cs in seg.crossing_s:
					if absf(cs - s) < 8.0:
						near_crossing = true
				var off := seg.outer_extent(s, side) - 0.45
				var p := seg.global_transform * (seg.local_center(s) + seg.local_right(s) * side * off)
				var clear := not near_crossing
				for sp in spots:
					if sp.distance_to(p) < 7.0:
						clear = false
				if clear:
					var facing := seg.global_transform.basis * (seg.local_right(s) * -side)
					_add(rng.randi() % Kind.size(), Transform3D(MathUtil.basis_from_forward(facing), Vector3(p.x, RoadSegment.KERB_HEIGHT, p.z)))
				s += rng.randf_range(26.0, 40.0)
	for i in DEBRIS_POOL:
		var d := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.28, 0.2, 0.28)
		d.mesh = m
		d.material_override = _material(Color(0.62, 0.45, 0.25))
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.visible = false
		add_child(d)
		_debris.append(d)
		_debris_vel.append(Vector3.ZERO)
		_debris_t.append(0.0)


func _spot_positions(node: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in node.get_children():
		if c is PedestrianSpot:
			out.append((c as Node3D).global_position)
		out.append_array(_spot_positions(c))
	return out


func _add(kind: int, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var color := Color.WHITE
	var r := 0.5
	match kind:
		Kind.SIGN:
			mesh.size = Vector3(0.7, 1.6, 0.08)
			color = Color(0.95, 0.85, 0.2)
			r = 0.4
		Kind.BOXES:
			mesh.size = Vector3(0.8, 0.9, 0.6)
			color = Color(0.62, 0.45, 0.25)
		Kind.CONE:
			mesh.size = Vector3(0.35, 0.7, 0.35)
			color = Color(1.0, 0.45, 0.1)
			r = 0.25
		Kind.STALL_BOARD:
			mesh.size = Vector3(1.2, 1.1, 0.1)
			color = Color(0.2, 0.55, 0.75)
			r = 0.6
		Kind.DISPLAY:
			mesh.size = Vector3(1.0, 0.8, 0.5)
			color = Color(0.75, 0.25, 0.3)
	mi.mesh = mesh
	mi.material_override = _material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var placed := xf.translated(Vector3.UP * mesh.size.y * 0.5)
	mi.transform = placed
	add_child(mi)
	WorldSurface.tag(mi, WorldSurface.Type.PROP)
	nodes.append(mi)
	kinds.append(kind)
	states.append(PropState.STANDING)
	home.append(placed)
	radius.append(r)
	vel.append(Vector3.ZERO)
	spin.append(Vector3.ZERO)
	timer.append(0.0)


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m


func active_debris() -> int:
	var n := 0
	for d in _debris:
		if d.visible:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	var ps := PerfSections.begin()
	_physics_process_body(delta)
	PerfSections.end(PerfSections.PROPS, ps)


func _physics_process_body(delta: float) -> void:
	if player == null:
		return
	var xf := player.global_transform
	var f3 := -xf.basis.z
	var f := Vector2(f3.x, f3.z).normalized()
	var c := Vector2(xf.origin.x, xf.origin.z)
	var ext := player.half_extents()
	for i in nodes.size():
		match states[i]:
			PropState.STANDING:
				var p := nodes[i].global_position
				var hp := Vector2(p.x, p.z)
				if hp.distance_squared_to(c) > 25.0:
					continue
				if OrientedRect.point_distance(hp, c, f, ext.x, ext.y) - radius[i] <= 0.0:
					hit(i, player.linear_velocity)
			PropState.WOBBLING:
				timer[i] -= delta
				var t := maxf(timer[i], 0.0)
				nodes[i].transform = home[i] * Transform3D(Basis(Vector3.FORWARD, sin(t * 22.0) * t * 0.35), Vector3.ZERO)
				if timer[i] <= 0.0:
					nodes[i].transform = home[i]
					states[i] = PropState.STANDING
			PropState.KNOCKED:
				vel[i] += Vector3(0, -9.8, 0) * delta
				var n := nodes[i]
				n.global_position += vel[i] * delta
				n.rotate(spin[i].normalized() if spin[i].length() > 0.01 else Vector3.RIGHT, spin[i].length() * delta)
				if n.global_position.y <= 0.15 and vel[i].y < 0.0:
					n.global_position.y = 0.15
					vel[i] = Vector3.ZERO
					states[i] = PropState.SETTLED
					timer[i] = 4.0
			PropState.SETTLED:
				timer[i] -= delta
				if timer[i] < 1.0:
					nodes[i].scale = Vector3.ONE * maxf(timer[i], 0.01)
				if timer[i] <= 0.0:
					nodes[i].visible = false
					states[i] = PropState.GONE
					timer[i] = RESPAWN_SECONDS
			PropState.GONE:
				timer[i] -= delta
				if timer[i] <= 0.0:
					var hp2 := home[i].origin
					var in_view := camera != null and camera.is_position_in_frustum(hp2) and hp2.distance_to(xf.origin) < 120.0
					if not in_view:
						nodes[i].transform = home[i]
						nodes[i].visible = true
						states[i] = PropState.STANDING
						stats_respawns += 1
					else:
						timer[i] = 2.0
	_tick_debris(delta)


## Applies a hit from something moving at `velocity` (m/s).
func hit(i: int, velocity: Vector3) -> void:
	var v := Vector3(velocity.x, 0.0, velocity.z)
	var kmh := v.length() * 3.6
	if kmh < KNOCK_MIN_KMH:
		states[i] = PropState.WOBBLING
		timer[i] = 0.8
		stats_wobbles += 1
		return
	states[i] = PropState.KNOCKED
	stats_knocked += 1
	vel[i] = v * 0.75 + Vector3.UP * clampf(kmh * 0.12, 2.0, 5.0)
	spin[i] = v.cross(Vector3.UP).normalized() * -clampf(kmh * 0.4, 4.0, 14.0)
	if kinds[i] == Kind.BOXES or kinds[i] == Kind.DISPLAY:
		for k in 3:
			_spawn_debris(nodes[i].global_position, v)
	EventBus.prop_knocked.emit(nodes[i].global_position, kinds[i])


func _spawn_debris(at: Vector3, v: Vector3) -> void:
	var idx := _next_debris
	_next_debris = (_next_debris + 1) % DEBRIS_POOL
	var d := _debris[idx]
	d.global_position = at + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
	d.scale = Vector3.ONE
	d.visible = true
	_debris_vel[idx] = v * randf_range(0.4, 0.9) + Vector3(randf_range(-1.5, 1.5), randf_range(2.0, 4.0), randf_range(-1.5, 1.5))
	_debris_t[idx] = 3.0


func _tick_debris(delta: float) -> void:
	for k in _debris.size():
		var d := _debris[k]
		if not d.visible:
			continue
		_debris_t[k] -= delta
		if d.global_position.y > 0.1:
			_debris_vel[k] += Vector3(0, -9.8, 0) * delta
			d.global_position += _debris_vel[k] * delta
		if _debris_t[k] < 0.6:
			d.scale = Vector3.ONE * maxf(_debris_t[k] / 0.6, 0.01)
		if _debris_t[k] <= 0.0:
			d.visible = false


func count_in_state(s: PropState) -> int:
	var n := 0
	for st in states:
		if st == s:
			n += 1
	return n
