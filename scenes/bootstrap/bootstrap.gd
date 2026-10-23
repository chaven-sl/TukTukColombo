extends Node
## Entry scene. Global services (autoloads) are ready by now; hand over to
## the HOME / GARAGE screen (v0.04). A device perf test (flag file / args)
## goes straight to the Fort–Pettah street so the benchmark stays unchanged.

const FIRST_SCENE := "res://scenes/garage/garage.tscn"  # v0.04 home / garage
const STREET_SCENE := "res://scenes/districts/fort_pettah/fort_pettah_slice.tscn"


func _ready() -> void:
	# v0.03B1 startup analysis: engine + autoloads ready (ms since engine start).
	Engine.set_meta("startup_boot_ms", Time.get_ticks_msec())
	get_tree().change_scene_to_file.call_deferred(STREET_SCENE if DevicePerfTest.is_requested() else FIRST_SCENE)
