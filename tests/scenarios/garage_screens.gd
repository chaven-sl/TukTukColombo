extends Node
## Windowed only: v0.04 garage screenshots → user://test_results/screens/v004_*.png
##   godot --path . --resolution 1280x720 res://tests/scenarios/garage_screens.tscn -- --save-slot=screens

const GARAGE := preload("res://scenes/garage/garage.tscn")


func _ready() -> void:
	# A believable mid-career state on a throwaway save slot.
	var c := GameState.career
	c.data["cash"] = 2850
	c.data["reputation"] = 64
	c.data["successful_rides"] = 9
	c.data["total_earned"] = 2400
	c.upgrade_levels()["engine"] = 1
	var g: Garage = GARAGE.instantiate()
	add_child(g)
	await _frames(40)
	await _shot("v004_garage")
	g._select(&"brakes")
	await _frames(4)
	g.buy(&"brakes")
	await _frames(10)
	await _shot("v004_garage_purchase")
	GameState.session_cash = 1240
	GameState.session_reputation = 38
	GameState.session_rides_completed = 5
	GameState.session_best_chain = 4
	GameState.session_collisions = 2
	g._show_summary()
	await _frames(6)
	await _shot("v004_garage_summary")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://test_results/screens")
	img.save_png("user://test_results/screens/%s.png" % name)
	print("[Screens] %s" % name)
