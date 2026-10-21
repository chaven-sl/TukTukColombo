class_name ScenerySpawner
extends RefCounted
## Grey-box roadside dressing for speed perception: blocks, trees and lamp
## posts. Uses one MultiMeshInstance3D per kind (a handful of draw calls) and
## simple box colliders for the solid pieces. Placement never overlaps any
## road surface. Placeholder only — not Colombo art.

const ROAD_SAMPLE_SPACING := 4.0

var _road_samples := PackedVector3Array()   # x, z = centre; y = half width
var _rng := RandomNumberGenerator.new()


func populate(network: RoadNetwork, seed_value: int) -> void:
	_rng.seed = seed_value
	_collect_road_samples(network)
	var buildings: Array[Transform3D] = []
	var building_colors := PackedColorArray()
	var trees: Array[Transform3D] = []
	var lamps: Array[Transform3D] = []
	for seg in network.segments:
		if seg.scenery_density <= 0.0:
			continue
		for side in [-1.0, 1.0]:
			_place_along(seg, side, buildings, building_colors, trees, lamps)
	var root := Node3D.new()
	root.name = "Scenery"
	network.add_child(root)
	var body := StaticBody3D.new()
	body.name = "SceneryCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)

	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	_multimesh(root, "Buildings", unit_box, buildings, building_colors, network.materials["scenery"])
	for xf in buildings:
		_collider(body, xf.basis.get_scale(), xf.origin + Vector3.UP * 0.0, xf.basis.orthonormalized())

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.25
	trunk.height = 2.6
	trunk.radial_segments = 6
	trunk.rings = 1
	var canopy := SphereMesh.new()
	canopy.radius = 1.9
	canopy.height = 3.2
	canopy.radial_segments = 8
	canopy.rings = 4
	var trunk_xfs: Array[Transform3D] = []
	var canopy_xfs: Array[Transform3D] = []
	var trunk_colors := PackedColorArray()
	var canopy_colors := PackedColorArray()
	for xf in trees:
		trunk_xfs.append(xf.translated(Vector3.UP * 1.3))
		canopy_xfs.append(xf.translated(Vector3.UP * 3.6))
		trunk_colors.append(Color(0.35, 0.25, 0.17))
		canopy_colors.append(Color(0.18, 0.38 + _rng.randf() * 0.12, 0.16))
		_collider(body, Vector3(0.5, 2.6, 0.5), xf.origin + Vector3.UP * 1.3, Basis.IDENTITY)
	_multimesh(root, "TreeTrunks", trunk, trunk_xfs, trunk_colors, network.materials["scenery"])
	_multimesh(root, "TreeCanopies", canopy, canopy_xfs, canopy_colors, network.materials["scenery"])

	var pole := BoxMesh.new()
	pole.size = Vector3(0.14, 6.0, 0.14)
	var lamp_xfs: Array[Transform3D] = []
	var lamp_colors := PackedColorArray()
	for xf in lamps:
		lamp_xfs.append(xf.translated(Vector3.UP * 3.0))
		lamp_colors.append(Color(0.45, 0.45, 0.47))
		_collider(body, Vector3(0.2, 6.0, 0.2), xf.origin + Vector3.UP * 3.0, Basis.IDENTITY)
	_multimesh(root, "LampPosts", pole, lamp_xfs, lamp_colors, network.materials["scenery"])


func _collect_road_samples(network: RoadNetwork) -> void:
	for seg in network.segments:
		var steps := maxi(2, int(ceil(seg.length / ROAD_SAMPLE_SPACING)))
		for k in steps + 1:
			var s := seg.length * float(k) / float(steps)
			var p := seg.global_transform * seg.local_center(s)
			var extent := maxf(seg.outer_extent(s, -1.0), seg.outer_extent(s, 1.0))
			_road_samples.append(Vector3(p.x, extent + 0.5, p.z))
	# Keep pedestrian spots (bus stop, shop fronts, pickups) clear of dressing.
	for sp in _spot_positions(network):
		_road_samples.append(Vector3(sp.x, 7.0, sp.z))
	for ix in network.intersections:
		var p := ix.global_position
		_road_samples.append(Vector3(p.x, ix.size * 0.75, p.z))
	for chain in network.chains:
		if chain.end_cap_tunnel:
			var e := chain.global_transform * chain.end_local
			for k in 4:
				var p := e.origin + e.basis.z * (k * chain.tunnel_depth / 3.0)
				_road_samples.append(Vector3(p.x, 9.0, p.z))


func _spot_positions(node: Node) -> PackedVector3Array:
	var result := PackedVector3Array()
	for child in node.get_children():
		if child is PedestrianSpot:
			result.append((child as Node3D).global_position)
		result.append_array(_spot_positions(child))
	return result


func _clear_of_roads(p: Vector3, radius: float) -> bool:
	for sample in _road_samples:
		var dx := p.x - sample.x
		var dz := p.z - sample.z
		var limit := sample.y + radius
		if dx * dx + dz * dz < limit * limit:
			return false
	return true


func _place_along(seg: RoadSegment, side: float, buildings: Array[Transform3D], building_colors: PackedColorArray,
		trees: Array[Transform3D], lamps: Array[Transform3D]) -> void:
	var xf := seg.global_transform
	# Lamp posts every ~28 m: at the back of a sidewalk, else just past the kerb.
	var s := 6.0
	while s < seg.length:
		var off := seg.half_width(s) + 1.1
		if seg.has_sidewalk(side):
			off = seg.outer_extent(s, side) - 0.3
		var p := xf * (seg.local_center(s) + seg.local_right(s) * side * off)
		if _clear_of_roads(p, 0.3):
			lamps.append(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.z)))
		s += 28.0
	# Trees and blocks with random spacing.
	s = _rng.randf_range(2.0, 10.0)
	while s < seg.length:
		var basis := MathUtil.basis_from_forward(xf.basis * seg.local_tangent(s))
		if _rng.randf() < 0.45:
			var off := seg.outer_extent(s, side) + _rng.randf_range(1.5, 4.0)
			var p := xf * (seg.local_center(s) + seg.local_right(s) * side * off)
			if _clear_of_roads(p, 2.0):
				trees.append(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.z)))
			s += _rng.randf_range(7.0, 14.0)
		else:
			var width := _rng.randf_range(8.0, 18.0)
			var depth := _rng.randf_range(8.0, 16.0)
			var height := _rng.randf_range(4.0, 14.0)
			var off := seg.outer_extent(s, side) + _rng.randf_range(5.0, 10.0) + depth * 0.5
			var p := xf * (seg.local_center(s) + seg.local_right(s) * side * off)
			if _clear_of_roads(p, maxf(width, depth) * 0.6):
				var b := basis.scaled(Vector3(width, height, depth))
				buildings.append(Transform3D(b, Vector3(p.x, height * 0.5, p.z)))
				var tone := _rng.randf_range(0.55, 0.8)
				building_colors.append(Color(tone, tone * _rng.randf_range(0.93, 1.0), tone * _rng.randf_range(0.85, 0.98)))
			s += width + _rng.randf_range(2.0, 9.0)


func _multimesh(parent: Node3D, node_name: String, mesh: Mesh, xfs: Array[Transform3D], colors: PackedColorArray, material: Material) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, colors[i] if i < colors.size() else Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


func _collider(body: StaticBody3D, size: Vector3, pos: Vector3, basis: Basis) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = Transform3D(basis, pos)
	body.add_child(shape)
