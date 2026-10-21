class_name PauseController
extends CanvasLayer
## Esc toggles pause. Runs while the tree is paused.

var _overlay: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.45)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-300, -60)
	box.custom_minimum_size = Vector2(600, 0)
	_overlay.add_child(box)
	var title := Label.new()
	title.text = tr("UI_PAUSED")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)
	var hint := Label.new()
	hint.text = tr("UI_PAUSE_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	box.add_child(hint)
	_overlay.visible = false
	GameState.pause_changed.connect(_on_pause_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameState.set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func _on_pause_changed(paused: bool) -> void:
	_overlay.visible = paused
