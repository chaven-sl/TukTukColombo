class_name ComboManager
extends RefCounted
## Pure combo rules (no nodes, no UI) so they can be unit tested.
##
## Each valid skill event extends the chain and refreshes the timeout. The
## multiplier equals the chain length capped at max_multiplier (1x..5x). The
## chain ends when the timeout runs out or reset() is called (collisions).

var max_multiplier := 5
var timeout := 3.0
var chain := 0
var time_left := 0.0


func _init(p_max_multiplier: int = 5, p_timeout: float = 3.0) -> void:
	max_multiplier = p_max_multiplier
	timeout = p_timeout


func multiplier() -> int:
	return clampi(chain, 1, max_multiplier)


func is_active() -> bool:
	return chain > 0


## Registers a skill event and returns the points it is worth.
func register_event(base_points: int) -> int:
	chain += 1
	time_left = timeout
	return base_points * multiplier()


## Advances the timer. Returns true when the combo expired this call.
func update(delta: float) -> bool:
	if chain == 0:
		return false
	time_left -= delta
	if time_left <= 0.0:
		chain = 0
		time_left = 0.0
		return true
	return false


## Ends the combo immediately. Returns true if one was running.
func reset() -> bool:
	var had_combo := chain > 0
	chain = 0
	time_left = 0.0
	return had_combo
