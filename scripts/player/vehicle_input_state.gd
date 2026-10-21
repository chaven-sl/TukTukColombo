class_name VehicleInputState
extends RefCounted
## Device-independent driving intent. Keyboard, future touch controls,
## gamepads and test autopilots all write into this; the vehicle only reads it.

var throttle := 0.0   ## 0..1
var brake := 0.0      ## 0..1 — brakes while moving forward, reverses when stopped
var steer := 0.0      ## -1 (left) .. +1 (right)
var handbrake := false


func clear() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	handbrake = false
