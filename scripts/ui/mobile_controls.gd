class_name MobileControls
extends CanvasLayer
## Prototype touch HUD: analog steering pad (left thumb), accelerator + brake
## (right thumb), horn, pause, and a contextual ACCEPT RIDE button. Handles
## raw InputEventScreenTouch/Drag itself so multitouch works regardless of
## Control focus rules, and feeds a TouchControlState that TouchInputSource
## copies into the vehicle input. Placeholder visuals only.
##
## Taps call the same paths as the keyboard: EventBus.horn_sounded,
## RideManager.request_accept(), GameState.set_paused().

signal layout_changed(rects: Dictionary)

@export var config: TouchControlsConfig

var state: TouchControlState
var rides: RideManager
var vehicle: TukController
var rects: Dictionary = {}
var safe_rect := Rect2()
var active := false

var _root: Control
var _panels: Dictionary = {}  # Control -> Panel
var _labels: Dictionary = {}
var _knob: Panel
var _styles: Dictionary = {}


func _ready() -> void:
	layer = 15
	if config == null:
		config = TouchControlsConfig.new()
	state = TouchControlState.new(config)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var C := TouchControlState.Pad
	_make_panel(C.STEER, "", Color(0.85, 0.9, 1.0))
	_make_panel(C.ACCELERATE, "UI_TOUCH_GO", Color(0.35, 0.95, 0.45))
	_make_panel(C.BRAKE, "UI_TOUCH_BRAKE", Color(1.0, 0.45, 0.35))
	_make_panel(C.HORN, "UI_TOUCH_HORN", Color(1.0, 0.85, 0.3))
	_make_panel(C.PAUSE, "UI_TOUCH_PAUSE", Color(0.9, 0.9, 0.9))
	_make_panel(C.ACCEPT, "UI_ACCEPT_RIDE_TOUCH", Color(0.3, 0.75, 1.0))
	_knob = Panel.new()
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_knob.add_theme_stylebox_override("panel", _style(Color(1, 1, 1), 0.85, 40))
	_root.add_child(_knob)
	get_viewport().size_changed.connect(relayout)
	# Never carry a held throttle/steer across a pause.
	GameState.pause_changed.connect(func(_p: bool) -> void: state.cancel_all())
	set_active(false)


func setup(p_vehicle: TukController, p_rides: RideManager) -> void:
	vehicle = p_vehicle
	rides = p_rides
	relayout()


func set_active(on: bool) -> void:
	active = on
	visible = on
	if not on:
		state.cancel_all()


func _style(color: Color, alpha: float, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, alpha * 0.45)
	sb.border_color = Color(color.r, color.g, color.b, alpha)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(radius)
	return sb


func _make_panel(c: int, label_key: String, color: Color) -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var idle := _style(color, config.idle_opacity, 18)
	var pressed := _style(color, config.pressed_opacity, 18)
	_styles[c] = [idle, pressed]
	panel.add_theme_stylebox_override("panel", idle)
	_root.add_child(panel)
	_panels[c] = panel
	if not label_key.is_empty():
		var label := Label.new()
		label.text = tr(label_key)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.add_theme_font_size_override("font_size", 26 if c != TouchControlState.Pad.PAUSE else 22)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("outline_size", 5)
		panel.add_child(label)
		_labels[c] = label


func relayout() -> void:
	var view := get_viewport().get_visible_rect().size
	safe_rect = MobileLayout.safe_rect_for(get_viewport())
	apply_layout(view, safe_rect)


## Separate from relayout() so tests can lay out for any size / safe area.
func apply_layout(view: Vector2, safe: Rect2) -> void:
	rects = MobileLayout.compute(view, safe, config)
	state.rects = rects
	var steer: Rect2 = rects[TouchControlState.Pad.STEER]
	state.steer_center_x = steer.get_center().x
	state.steer_half_width = steer.size.x * 0.5
	for c in _panels:
		var panel: Panel = _panels[c]
		var r: Rect2 = rects[c]
		panel.position = r.position
		panel.size = r.size
	layout_changed.emit(rects)


func _process(_delta: float) -> void:
	if not active:
		return
	var C := TouchControlState.Pad
	state.accept_available = rides != null and rides.state == RideManager.RideState.NO_RIDE and rides.nearby_offer != null
	(_panels[C.ACCEPT] as Panel).visible = state.accept_available
	for c in [C.ACCELERATE, C.BRAKE, C.HORN, C.STEER]:
		var styles: Array = _styles[c]
		(_panels[c] as Panel).add_theme_stylebox_override("panel", styles[1] if state.is_held(c) else styles[0])
	var steer: Rect2 = rects.get(C.STEER, Rect2())
	var knob := 72.0 * clampf(steer.size.y / 150.0, 0.8, 1.3)
	var knob_x := steer.get_center().x + state.steer * state.steer_half_width * config.full_lock_fraction
	_knob.size = Vector2(knob, knob)
	_knob.position = Vector2(knob_x - knob * 0.5, steer.get_center().y - knob * 0.5)
	_dispatch_taps()


func _dispatch_taps() -> void:
	var C := TouchControlState.Pad
	for c in state.take_pending():
		match c:
			C.HORN:
				if vehicle != null:
					EventBus.horn_sounded.emit(vehicle.global_position)
			C.ACCEPT:
				if rides != null:
					rides.request_accept()
			C.PAUSE:
				GameState.set_paused(true)


func _input(event: InputEvent) -> void:
	if not active:
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		var pos := touch.position
		if touch.pressed:
			if state.press(touch.index, pos) != TouchControlState.Pad.NONE:
				get_viewport().set_input_as_handled()
		else:
			state.release(touch.index)
		if touch.canceled:
			state.release(touch.index)
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		# Positions arrive in logical viewport units (stretch already applied).
		state.drag(drag.index, drag.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		state.cancel_all()
