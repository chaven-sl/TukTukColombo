class_name RoadChain
extends Node3D
## Lays out its child road elements (RoadSegment, IntersectionController)
## end to end. Editing one segment's length re-flows everything after it.
## A chain can start at an intersection arm and can end in a tunnel portal
## that hides traffic sources/sinks.

@export var closed_loop := false
## Optional: start this chain at an arm of an intersection laid out earlier.
@export var attach_intersection: NodePath
@export_range(-1, 3) var attach_arm := -1
## Build a tunnel portal over the last part of the chain (traffic source/sink).
@export var end_cap_tunnel := false
@export var tunnel_depth := 22.0

var end_local := Transform3D.IDENTITY


func layout() -> void:
	if attach_arm >= 0 and not attach_intersection.is_empty():
		var ix := get_node_or_null(attach_intersection) as IntersectionController
		if ix != null:
			global_transform = ix.arm_transform(attach_arm)
	var cursor := Transform3D.IDENTITY
	for child in get_children():
		if child.has_method("chain_place"):
			cursor = child.call("chain_place", cursor)
	end_local = cursor
	if closed_loop:
		var gap := cursor.origin.length()
		if gap > 0.5:
			push_warning("[RoadChain] %s does not close: gap %.2f m" % [name, gap])


func last_segment() -> RoadSegment:
	for i in range(get_child_count() - 1, -1, -1):
		var seg := get_child(i) as RoadSegment
		if seg != null:
			return seg
	return null


func build_end_cap(materials: Dictionary) -> void:
	if not end_cap_tunnel:
		return
	var seg := last_segment()
	if seg == null:
		return
	var half := seg.half_width(seg.length) + 0.6
	var cap := Node3D.new()
	cap.name = "TunnelPortal"
	cap.transform = end_local
	add_child(cap)
	var depth := tunnel_depth
	var height := 5.5
	var body := StaticBody3D.new()
	body.name = "TunnelCollision"
	WorldSurface.tag(body, WorldSurface.Type.WALL)
	body.collision_layer = 1
	body.collision_mask = 0
	cap.add_child(body)
	# Interior (unshaded black) so spawning/despawning inside is not visible.
	_box(cap, body, Vector3(1.0, height, depth + 2.0), Vector3(-half - 0.5, height * 0.5, depth * 0.5 - 1.0), materials["tunnel"], true)
	_box(cap, body, Vector3(1.0, height, depth + 2.0), Vector3(half + 0.5, height * 0.5, depth * 0.5 - 1.0), materials["tunnel"], true)
	_box(cap, body, Vector3(half * 2.0 + 2.0, 1.0, depth + 2.0), Vector3(0.0, height + 0.5, depth * 0.5 - 1.0), materials["tunnel"], false)
	_box(cap, body, Vector3(half * 2.0 + 2.0, height + 1.0, 1.0), Vector3(0.0, (height + 1.0) * 0.5, -1.5), materials["tunnel"], true)
	_box(cap, null, Vector3(half * 2.0, 0.02, depth + 1.0), Vector3(0.0, 0.03, depth * 0.5 - 1.0), materials["tunnel"], false)
	# Concrete portal frame at the mouth.
	_box(cap, body, Vector3(2.0, height + 1.5, 1.2), Vector3(-half - 1.0, (height + 1.5) * 0.5, depth), materials["concrete"], true)
	_box(cap, body, Vector3(2.0, height + 1.5, 1.2), Vector3(half + 1.0, (height + 1.5) * 0.5, depth), materials["concrete"], true)
	_box(cap, null, Vector3(half * 2.0 + 4.0, 1.5, 1.2), Vector3(0.0, height + 0.75, depth), materials["concrete"], false)


func _box(parent: Node3D, body: StaticBody3D, size: Vector3, pos: Vector3, material: Material, collide: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if collide and body != null:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = pos
		body.add_child(shape)
