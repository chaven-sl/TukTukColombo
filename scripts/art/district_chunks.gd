class_name DistrictChunks
extends RefCounted
## Spatial batching for district art (v0.03B). Everything static is written
## into per-cell builders (48 m cells) and committed as a few MeshInstances
## per cell:
##   Arch    plaster + glass + fabric + metal surfaces, casts shadows,
##           visibility range ~260 m (whole streets stay visible)
##   Detail  small clutter + wires, no shadows, culled at ~80 m
##   Lights  emissive bits, no shadows
##   Signs   sign quads sampling the shared SignAtlas texture
## → ≤ 7 draw calls per visible cell, frustum-culled per cell.

const CELL := 48.0

class Builders:
	var plaster := ArtMesh.new()
	var glass := ArtMesh.new()
	var fabric := ArtMesh.new()
	var metal := ArtMesh.new()
	var detail := ArtMesh.new()
	## v0.03B1 material separation for clutter: carts/tables, sacks/boxes,
	## and the static background crowd (all in the Detail layer: no shadow,
	## culled at the clutter range).
	var wood := ArtMesh.new()
	var goods := ArtMesh.new()
	var crowd := ArtMesh.new()
	var lights := ArtMesh.new()
	var signs := ArtMesh.new()

var cells: Dictionary = {}  # Vector2i -> Builders
## Vertices of baked background-crowd figures (diagnostics).
var crowd_figures := 0
var arch_range := 170.0
## Far/background batches (skyline): long range, no shadows.
var cast_shadows := true
var detail_range := 55.0
## Stats for the perf monitor / report.
var mesh_instances := 0
var triangles := 0


func at(pos: Vector3) -> Builders:
	var key := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
	if not cells.has(key):
		cells[key] = Builders.new()
	return cells[key]


func commit(parent: Node3D, sign_material: Material) -> void:
	for key: Vector2i in cells:
		var b: Builders = cells[key]
		# Re-centre on the cell so visibility ranges measure from the cell.
		var centre := Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)
		for m: ArtMesh in [b.plaster, b.glass, b.fabric, b.metal, b.detail, b.wood, b.goods, b.crowd, b.lights, b.signs]:
			m.translate(-centre)
		var arch := ArrayMesh.new()
		b.plaster.commit(ArtMaterials.get_material(&"plaster"), arch)
		b.glass.commit(ArtMaterials.get_material(&"glass"), arch)
		b.fabric.commit(ArtMaterials.get_material(&"fabric"), arch)
		b.metal.commit(ArtMaterials.get_material(&"metal"), arch)
		_instance(parent, "Arch_%d_%d" % [key.x, key.y], arch, cast_shadows, arch_range, centre)
		var detail := ArrayMesh.new()
		b.detail.commit(ArtMaterials.get_material(&"wire"), detail)
		b.wood.commit(ArtMaterials.get_material(&"wood"), detail)
		b.goods.commit(ArtMaterials.get_material(&"cardboard"), detail)
		b.crowd.commit(ArtMaterials.get_material(&"fabric"), detail)
		crowd_figures += b.crowd.vertex_count()
		_instance(parent, "Detail_%d_%d" % [key.x, key.y], detail, false, detail_range, centre)
		_instance(parent, "Lights_%d_%d" % [key.x, key.y], b.lights.commit(ArtMaterials.get_material(&"emissive")), false, detail_range * 1.5, centre)
		if sign_material != null:
			_instance(parent, "Signs_%d_%d" % [key.x, key.y], b.signs.commit(sign_material), false, arch_range * 0.6, centre)
		triangles += b.plaster.triangle_count() + b.glass.triangle_count() + b.fabric.triangle_count() + b.metal.triangle_count() \
				+ b.detail.triangle_count() + b.wood.triangle_count() + b.goods.triangle_count() + b.crowd.triangle_count() \
				+ b.lights.triangle_count() + b.signs.triangle_count()
	cells.clear()


func _instance(parent: Node3D, node_name: String, mesh: ArrayMesh, shadows: bool, range_end: float, centre: Vector3) -> void:
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = centre
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = range_end
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	parent.add_child(mi)
	mesh_instances += 1
