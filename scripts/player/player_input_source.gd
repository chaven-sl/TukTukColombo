class_name PlayerInputSource
extends Node
## Maps InputMap actions to the vehicle's VehicleInputState.
## Runs before the vehicle each physics tick (negative priority) so there is
## no frame of input lag. A touch-control source can replace this later.

@export var enabled := true

@onready var _vehicle: TukController = get_parent() as TukController


func _ready() -> void:
	process_physics_priority = -10


func _physics_process(_delta: float) -> void:
	if not enabled or _vehicle == null:
		return
	var state := _vehicle.input
	state.throttle = Input.get_action_strength("accelerate")
	state.brake = Input.get_action_strength("brake_reverse")
	state.steer = Input.get_axis("steer_left", "steer_right")
	state.handbrake = Input.is_action_pressed("handbrake")


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or _vehicle == null:
		return
	if event.is_action_pressed("reset_vehicle"):
		_vehicle.request_reset()
	elif event.is_action_pressed("horn"):
		EventBus.horn_sounded.emit(_vehicle.global_position)
