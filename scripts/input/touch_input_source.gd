class_name TouchInputSource
extends Node
## Touch equivalent of PlayerInputSource: copies the TouchControlState into the
## vehicle's VehicleInputState before the vehicle runs (negative priority).
## TouchInputSource → VehicleInputState → TukController. It never touches
## physics directly and has no tuning of its own.

@export var enabled := false

var vehicle: TukController
var state: TouchControlState


func _ready() -> void:
	process_physics_priority = -10


func _physics_process(_delta: float) -> void:
	if not enabled or vehicle == null or state == null:
		return
	var input := vehicle.input
	input.steer = state.steer
	input.throttle = state.throttle()
	input.brake = state.brake()
	input.handbrake = false
