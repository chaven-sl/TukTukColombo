extends Node3D
## Windowed only: art review shots of the hero tuk, its driver, a seated
## passenger and the character variants, under the district lighting.
##   godot --path . --resolution 1280x720 res://tests/scenarios/art_preview_screens.tscn

const TUK := preload("res://scenes/player/player_tuk.tscn")


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = DistrictLighting.make_environment()
	add_child(env)
	var sun := DistrictLighting.make_sun()
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.3, 0.31)
	ground.material_override = gm
	add_child(ground)
	var tuk: TukController = TUK.instantiate()
	tuk.freeze = true
	add_child(tuk)
	tuk.global_position = Vector3(0, 0.05, 0)  # wheels touching the ground (frozen body)
	tuk.rotation.y = deg_to_rad(-35)
	# Seated passenger in the rear.
	var passenger := CharacterRig.new(4)
	passenger.mode = CharacterRig.Mode.SEATED
	tuk.get_node("SeatMarker").add_child(passenger)
	passenger.transform = PassengerBehaviour.SEATED_OFFSET
	var people: Array[CharacterRig] = []
	var modes := [CharacterRig.Mode.IDLE, CharacterRig.Mode.WALK, CharacterRig.Mode.WAIT, CharacterRig.Mode.RUN,
			CharacterRig.Mode.ARGUE, CharacterRig.Mode.WALK, CharacterRig.Mode.IDLE, CharacterRig.Mode.HURRY,
			CharacterRig.Mode.IDLE, CharacterRig.Mode.WAIT, CharacterRig.Mode.WALK, CharacterRig.Mode.DIVE]
	for i in CharacterBuilder.variant_count():
		var r := CharacterRig.new(i)
		r.mode = modes[i]
		add_child(r)
		r.position = Vector3(-6.6 + i * 1.2, 0, -3.5)
		r.rotation.y = PI + 0.25  # face the camera
		people.append(r)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50
	cam.current = true
	for i in 30:
		await get_tree().process_frame
		for r in people:
			r.animate(1.0 / 60.0, cam.global_position)
		passenger.animate(1.0 / 60.0, cam.global_position)
	cam.look_at_from_position(Vector3(4.2, 2.2, 3.6), Vector3(0, 0.9, 0.1))
	await _shot("v003b1_art_hero_tuk")
	cam.look_at_from_position(Vector3(-2.8, 1.7, 5.0), Vector3(0, 1.0, 0.6))
	await _shot("v003b1_art_hero_rear")
	cam.look_at_from_position(Vector3(0, 1.4, 4.5), Vector3(0, 1.0, -3.5))
	await _shot("v003b1_art_characters")
	print("[Art] hero tuk triangles %d" % (tuk.get_node("Visual/HeroArt") as HeroTukVisual).triangle_count())
	for i in CharacterBuilder.variant_count():
		print("[Art] character %d triangles %d" % [i, CharacterBuilder.mesh_for(i).surface_get_array_len(0) / 3])
	get_tree().quit()


func _shot(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://test_results/screens")
	img.save_png("user://test_results/screens/%s.png" % name)
	print("[Screens] %s" % name)
