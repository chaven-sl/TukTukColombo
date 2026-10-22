class_name TouchControlState
extends RefCounted
## Multitouch bookkeeping, independent of any UI node so it can be unit tested.
##
## Each finger (touch index) is captured by the control it first lands on and
## keeps driving that control until it lifts — so a steering thumb sliding
## onto the brake area keeps steering, and a throttle finger never steals the
## steering. Holds work simultaneously (steer + throttle, steer + brake).
## Taps (horn, accept, pause) are reported once as pending actions.

enum Pad { NONE, STEER, ACCELERATE, BRAKE, HORN, ACCEPT, PAUSE }

var config: TouchControlsConfig
## Control rectangles (logical units). Set by the layout.
var rects: Dictionary = {}
## Steering pad centre/half-width used for the analog mapping.
var steer_center_x := 0.0
var steer_half_width := 150.0
## Whether the contextual ACCEPT RIDE button is currently shown.
var accept_available := false

var steer := 0.0
var _owner: Dictionary = {}  # touch index -> Pad
var _steer_index := -1
var _pending: Array[int] = []


func _init(p_config: TouchControlsConfig = null) -> void:
	config = p_config if p_config != null else TouchControlsConfig.new()


func control_at(pos: Vector2) -> Pad:
	# Priority: small/explicit buttons first, then the big steering zone.
	for c in [Pad.PAUSE, Pad.ACCEPT, Pad.HORN, Pad.ACCELERATE, Pad.BRAKE]:
		if c == Pad.ACCEPT and not accept_available:
			continue
		var r: Rect2 = rects.get(c, Rect2())
		if r.has_area() and r.has_point(pos):
			return c
	var steer_rect: Rect2 = rects.get(Pad.STEER, Rect2())
	if steer_rect.grow(config.steer_hit_margin).has_point(pos):
		return Pad.STEER
	return Pad.NONE


func press(index: int, pos: Vector2) -> Pad:
	var c := control_at(pos)
	if c == Pad.NONE:
		return c
	if c == Pad.STEER and _steer_index >= 0 and _steer_index != index:
		return Pad.NONE  # one steering thumb at a time
	_owner[index] = c
	match c:
		Pad.STEER:
			_steer_index = index
			steer = TouchSteeringMapper.map(pos.x - steer_center_x, steer_half_width, config)
		Pad.HORN, Pad.ACCEPT, Pad.PAUSE:
			_pending.append(c)
	return c


func drag(index: int, pos: Vector2) -> void:
	if index == _steer_index:
		steer = TouchSteeringMapper.map(pos.x - steer_center_x, steer_half_width, config)


func release(index: int) -> void:
	if index == _steer_index:
		_steer_index = -1
		steer = 0.0
	_owner.erase(index)


## Lost focus, app paused, or the OS cancelled touches: let go of everything.
func cancel_all() -> void:
	_owner.clear()
	_steer_index = -1
	steer = 0.0
	_pending.clear()


func is_held(c: Pad) -> bool:
	for index in _owner:
		if _owner[index] == c:
			return true
	return false


func throttle() -> float:
	return 1.0 if is_held(Pad.ACCELERATE) else 0.0


func brake() -> float:
	return 1.0 if is_held(Pad.BRAKE) else 0.0


## Returns and clears tap actions (HORN / ACCEPT / PAUSE) since last call.
func take_pending() -> Array[int]:
	var out := _pending.duplicate()
	_pending.clear()
	return out


func active_touch_count() -> int:
	return _owner.size()
