extends Node
## Entry scene. Global services (autoloads) are ready by now; hand over to
## the Fort–Pettah district slice (the greybox prototype stays for tests). Future: splash, settings application, menu.

const FIRST_SCENE := "res://scenes/districts/fort_pettah/fort_pettah_slice.tscn"  # v0.03B production slice


func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred(FIRST_SCENE)
