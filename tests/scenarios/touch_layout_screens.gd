extends Node
## Windowed only: screenshot of the real scene with touch controls forced on,
## saved to user://test_results/screens/touch_<w>x<h>.png. Run per aspect ratio:
##   godot --path . --resolution 1200x540 res://tests/scenarios/touch_layout_screens.tscn

func _ready() -> void:
	var main: Node3D = preload("res://scenes/prototype/prototype_main.tscn").instantiate()
	add_child(main)
	main.call("set_touch_mode", true)
	for i in 90:
		await get_tree().process_frame
	# The unfocused test window triggers the focus-loss pause; resume for the shot.
	GameState.set_paused(false)
	for i in 10:
		await get_tree().process_frame
	var hud := main.get_node("HUD") as PrototypeHud
	print("[TouchScreens] speed label rect %s text '%s'" % [hud.get("_speed_label").get_global_rect(), hud.get("_speed_label").text])
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://test_results/screens")
	var size := DisplayServer.window_get_size()
	var path := "user://test_results/screens/touch_%dx%d.png" % [size.x, size.y]
	img.save_png(path)
	var problems := MobileLayout.problems(get_viewport().get_visible_rect().size, (main.get_node("MobileControls") as MobileControls).safe_rect, (main.get_node("MobileControls") as MobileControls).rects)
	print("[TouchScreens] %s logical %s problems: %s" % [ProjectSettings.globalize_path(path), get_viewport().get_visible_rect().size, problems])
	get_tree().quit()
