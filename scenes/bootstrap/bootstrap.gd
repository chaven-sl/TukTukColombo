extends Node
## Entry scene. Global services (autoloads) are ready by now; hand over to
## the prototype level. Future: splash, settings application, menu.

const FIRST_SCENE := "res://scenes/prototype/prototype_main.tscn"


func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred(FIRST_SCENE)
