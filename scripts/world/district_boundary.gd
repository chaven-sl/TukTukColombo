class_name DistrictBoundary
extends RefCounted
## Builds the physical envelope of the playable district (v0.03A2): a
## continuous ring of grey-box buildings and compound walls just outside the
## road network's footprint, so driving off-road always ends at a structure
## instead of empty world. No invisible walls beside roads — the open ground
## between the roads and this ring stays drivable (forecourts, lots).
##
## One MultiMesh for the visuals, one StaticBody with box shapes (tagged
## BUILDING / WALL) for collision.

const BLOCK_DEPTH := 10.0


## Returns the block transforms (basis scaled to size) so a district dresser
## can draw them; with `visuals` false only the colliders are built here.
func build(network: RoadNetwork, rect: Rect2, seed_value: int, visuals: bool = true) -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var root := Node3D.new()
	root.name = "DistrictBoundary"
	network.add_child(root)
	var buildings := StaticBody3D.new()
	buildings.name = "BoundaryBuildings"
	buildings.collision_layer = 1
	buildings.collision_mask = 0
	WorldSurface.tag(buildings, WorldSurface.Type.BUILDING)
	root.add_child(buildings)
	var walls := StaticBody3D.new()
	walls.name = "BoundaryWalls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	WorldSurface.tag(walls, WorldSurface.Type.WALL)
	root.add_child(walls)
	var xfs: Array[Transform3D] = []
	var colors := PackedColorArray()
	# Four sides; each block sits outside the rect with its inner face on the edge.
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var along := (b - a).normalized()
		var outward := Vector2(along.y, -along.x)  # rect corners run clockwise in x/z
		if outward.dot((a + b) * 0.5 - rect.get_center()) < 0.0:
			outward = -outward
		var total := a.distance_to(b) + BLOCK_DEPTH * 2.0
		var start := a - along * BLOCK_DEPTH
		var d := 0.0
		while d < total:
			var w := minf(rng.randf_range(12.0, 24.0), total - d)
			var centre2 := start + along * (d + w * 0.5) + outward * (BLOCK_DEPTH * 0.5)
			var is_wall := rng.randf() < 0.22
			var h := rng.randf_range(2.6, 3.2) if is_wall else rng.randf_range(6.0, 18.0)
			var depth := 1.2 if is_wall else BLOCK_DEPTH
			if is_wall:
				centre2 = start + along * (d + w * 0.5) + outward * 0.6
			var basis := MathUtil.basis_from_forward(Vector3(outward.x, 0.0, outward.y))
			var size := Vector3(w + 0.4, h, depth)
			var xf := Transform3D(basis * Basis.from_scale(size), Vector3(centre2.x, h * 0.5, centre2.y))  # local scale
			xfs.append(xf)
			var tone := rng.randf_range(0.5, 0.72) if not is_wall else 0.8
			colors.append(Color(tone, tone * 0.97, tone * 0.9))
			_collider(walls if is_wall else buildings, size, xf.origin, basis)
			d += w
	if not visuals:
		return xfs
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = unit
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		mm.set_instance_color(k, colors[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BoundaryBlocks"
	mmi.multimesh = mm
	mmi.material_override = network.materials["scenery"]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return xfs


func _collider(body: StaticBody3D, size: Vector3, pos: Vector3, basis: Basis) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = Transform3D(basis, pos)
	body.add_child(shape)
