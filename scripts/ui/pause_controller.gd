class_name PauseController
extends CanvasLayer
## Pause screen and app-lifecycle safety. Runs while the tree is paused.
##
## - Esc / the touch pause button pause; Esc or Resume resume.
## - Android Back (NOTIFICATION_WM_GO_BACK_REQUEST; quit_on_go_back is off):
##   gameplay → pause, paused → resume. Back never quits the app.
## - Losing focus / going to the home screen pauses (the tuk never drives on
##   unseen) and flushes the save. Returning does NOT auto-resume: the player
##   resumes deliberately. Active rides are left untouched.

signal perf_test_requested()
## v0.04: the player asked to return to the garage (only offered when safe).
signal garage_requested()

## Returns true when leaving for the garage is safe (no hire, tuk stopped).
var garage_check: Callable
var _garage: Button
var _garage_hint: Label

var _overlay: Control
var _resume: Button
var _telemetry: Button
var _perf: Button
var lifecycle_pauses := 0
var _hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.5)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-260, -170)
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 14)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = tr("UI_PAUSED")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)
	_resume = _button(box, "UI_RESUME", 32)
	_resume.pressed.connect(func() -> void: GameState.set_paused(false))
	_garage = _button(box, "UI_RETURN_TO_GARAGE", 28)
	_garage.pressed.connect(func() -> void:
		if garage_check.is_valid() and garage_check.call():
			_garage.disabled = true  # one request only
			garage_requested.emit())
	_garage_hint = Label.new()
	_garage_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_garage_hint.add_theme_font_size_override("font_size", 18)
	_garage_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	box.add_child(_garage_hint)
	_telemetry = _button(box, "UI_DEV_TELEMETRY", 22)
	_telemetry.pressed.connect(func() -> void: GameState.toggle_debug_hud())
	_perf = _button(box, "UI_DEV_PERF_TEST", 22)
	_perf.pressed.connect(func() -> void:
		GameState.set_paused(false)
		perf_test_requested.emit())
	# Developer-only entries never appear in release builds.
	_telemetry.visible = OS.is_debug_build()
	_perf.visible = OS.is_debug_build()
	_hint = Label.new()
	_hint.text = tr("UI_PAUSE_HINT")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 20)
	box.add_child(_hint)
	_overlay.visible = false
	GameState.pause_changed.connect(_on_pause_changed)


func _button(parent: Control, key: String, size: int) -> Button:
	var b := Button.new()
	b.text = tr(key)
	b.custom_minimum_size = Vector2(0, 76 if size >= 30 else 60)
	b.add_theme_font_size_override("font_size", size)
	parent.add_child(b)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameState.set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			handle_back()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			handle_focus_lost()


## Keyboard shortcut hints make no sense on a phone.
func set_keyboard_hints(on: bool) -> void:
	_hint.visible = on


## Android Back: pause first, resume from the pause screen. Never quits.
func handle_back() -> void:
	GameState.set_paused(not get_tree().paused)


func handle_focus_lost() -> void:
	if not get_tree().paused:
		lifecycle_pauses += 1
		GameState.set_paused(true)


func _on_pause_changed(paused: bool) -> void:
	_overlay.visible = paused
	if paused and _garage != null:
		var ok: bool = garage_check.is_valid() and garage_check.call()
		_garage.visible = garage_check.is_valid()
		_garage.disabled = not ok
		_garage_hint.visible = garage_check.is_valid() and not ok
		_garage_hint.text = tr("UI_GARAGE_NOT_NOW")
	if paused and _resume != null:
		_resume.grab_focus.call_deferred()
