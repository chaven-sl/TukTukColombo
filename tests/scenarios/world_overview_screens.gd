extends Node
## Windowed only: top-down orthographic overview of the district (boundary
## ring, shopfronts, props) + one street-level shot. user://test_results/screens/
##   godot --path . --resolution 1000x1000 res://tests/scenarios/world_overview_screens.tscn

const MAIN := preload("res://scenes/prototype/prototype_main.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var main: Node3D = MAIN.instantiate()
	add_child(main)
	var road: RoadNetwork = main.get_node("TestTrack")
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var r := road.district_rect.grow(20.0)
	cam.size = maxf(r.size.x, r.size.y)
	add_child(cam)
	cam.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3(r.get_center().x, 300.0, r.get_center().y))
	cam.far = 1000.0
	cam.current = true
	(main.get_node("WorldEnvironment") as WorldEnvironment).environment.fog_enabled = false
	for c in main.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	print("[World] district %s" % road.district_rect)
	await _frames(20)
	await _shot("v003a2_world_topdown")
	# Street level: shopfront row + props on the east pavement.
	cam.current = false
	for c in main.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = true
	(main.get_node("WorldEnvironment") as WorldEnvironment).environment.fog_enabled = true
	var player: TukController = main.get_node("PlayerTuk")
	player.get_node("PlayerInput").set("enabled", false)
	player.teleport(Transform3D(MathUtil.basis_from_forward(Vector3(0.25, 0, -1).normalized()), Vector3(4.0, 0.4, -150.0)))
	player.input.handbrake = true
	await _frames(40)
	await _shot("v003a2_street_pavement")
	# Disabling crash into a boundary building.
	var b := road.get_node("DistrictBoundary/BoundaryBuildings").get_child(5) as CollisionShape3D
	var out := -b.global_transform.basis.z
	player.teleport(Transform3D(MathUtil.basis_from_forward(out), b.global_position - out * 18.0 + Vector3.DOWN * (b.global_position.y - 0.4)))
	player.linear_velocity = out * 45.0 / 3.6
	(main.get_node("VehicleDamage") as VehicleDamageManager).state.grace_left = 0.0
	player.input.handbrake = false
	await _frames(70)
	await _shot("v003a2_crash_disabled")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
	GameState.set_paused(false)


func _shot(name: String) -> void:
	GameState.set_paused(false)
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://test_results/screens")
	img.save_png("user://test_results/screens/%s.png" % name)
	print("[Screens] %s" % name)
