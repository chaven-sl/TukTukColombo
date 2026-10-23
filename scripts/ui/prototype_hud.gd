class_name PrototypeHud
extends CanvasLayer
## Minimal driving HUD: score, speed, combo meter and restrained popups.
## Purely presentational — listens to EventBus and reads player telemetry.
## All player-facing text goes through translation keys.

const POPUP_COUNT := 4

var player: TukController
var scoring: ScoringSystem

var _score_label: Label
var _speed_label: Label
var _speed_unit: Label
var _combo_label: Label
var _combo_bar: ProgressBar
var _combo_root: Control
var _popups: Array[Label] = []
var _popup_index := 0
var _small_settings: LabelSettings
var _popup_settings: LabelSettings
var _gap_settings: LabelSettings
var _loss_settings: LabelSettings
var _combo_tween: Tween
var _touch_layout := false
var _touch_rects: Dictionary = {}
## HUD root inside the safe area (v0.03A2).
var safe_root: HudSafeArea
## Critical notifications suppress score popups (no stacking over warnings).
var notifications: NotificationPresenter


func setup(p_player: TukController, p_scoring: ScoringSystem) -> void:
	player = p_player
	scoring = p_scoring
	scoring.combo_lost.connect(_on_combo_lost)


func _ready() -> void:
	_build()
	EventBus.score_awarded.connect(_on_score_awarded)
	EventBus.combo_changed.connect(_on_combo_changed)
	_on_combo_changed(0, 1)


func _settings(size: int, color: Color, outline: int) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = Color(0, 0, 0, 0.85)
	return ls


func _build() -> void:
	_small_settings = _settings(22, Color(1, 1, 1), 6)
	_popup_settings = _settings(40, Color(1.0, 0.95, 0.75), 8)
	_gap_settings = _settings(54, Color(1.0, 0.62, 0.12), 10)
	_loss_settings = _settings(28, Color(1.0, 0.4, 0.35), 6)
	# v0.03A2: everything lives inside the safe area (cutouts, corners).
	safe_root = HudSafeArea.new()
	safe_root.name = "SafeArea"
	add_child(safe_root)
	var root: Control = safe_root

	_score_label = Label.new()
	_score_label.label_settings = _settings(22, Color(1, 1, 1, 0.9), 3)  # v0.03B1: score never competes with the road
	root.add_child(_score_label)

	_speed_label = Label.new()
	_speed_label.label_settings = _settings(54, Color(1, 1, 1), 4)
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_speed_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_speed_label)
	_speed_unit = Label.new()
	_speed_unit.label_settings = _small_settings
	_speed_unit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_speed_unit.text = tr("UI_KMH")
	root.add_child(_speed_unit)

	_combo_root = VBoxContainer.new()
	_combo_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(_combo_root, Vector2(0.5, 0.0), Rect2(-110, 64, 220, 46))  # below the GPS line
	root.add_child(_combo_root)
	_combo_label = Label.new()
	_combo_label.label_settings = _settings(34, Color(1.0, 0.85, 0.3), 8)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.pivot_offset = Vector2(110, 20)
	_combo_root.add_child(_combo_label)
	_combo_bar = ProgressBar.new()
	_combo_bar.custom_minimum_size = Vector2(220, 8)
	_combo_bar.show_percentage = false
	_combo_bar.max_value = 1.0
	_combo_bar.step = 0.0
	_combo_root.add_child(_combo_bar)

	for i in POPUP_COUNT:
		var popup := Label.new()
		popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		popup.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		popup.modulate.a = 0.0
		root.add_child(popup)
		_popups.append(popup)
	_apply_layout()


## Anchors `c` at (anchor.x, anchor.y) of the safe root with an offset rect.
static func place(c: Control, anchor: Vector2, r: Rect2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y


## Touch mode: score right of the pause button, speed above the steering pad,
## both derived from the actual touch-control rects (MobileControls).
func set_touch_layout(on: bool) -> void:
	_touch_layout = on
	_apply_layout()


func on_touch_controls_layout(rects: Dictionary) -> void:
	_touch_rects = rects
	_apply_layout()


func _apply_layout() -> void:
	if safe_root == null:
		return
	var score_x := 0.0
	var speed_bottom := 0.0
	if _touch_layout and not _touch_rects.is_empty():
		var pause: Rect2 = _touch_rects[TouchControlState.Pad.PAUSE]
		var steer: Rect2 = _touch_rects[TouchControlState.Pad.STEER]
		score_x = maxf(pause.end.x - safe_root.position.x + 14.0, 0.0)
		speed_bottom = minf(steer.position.y - 8.0 - safe_root.get_rect().end.y, 0.0)
	place(_score_label, Vector2.ZERO, Rect2(score_x, 2, 0, 0))  # sizes to its text
	place(_speed_unit, Vector2(0, 1), Rect2(4, speed_bottom - 26, 120, 26))
	place(_speed_label, Vector2(0, 1), Rect2(0, speed_bottom - 34 - 92, 180, 92))  # 64 px digits ≈ 88 tall; unit label ≈ 31


func _process(_delta: float) -> void:
	var ps := PerfSections.begin()
	_process_body(_delta)
	PerfSections.end(PerfSections.HUD, ps)


func _process_body(_delta: float) -> void:
	if player == null:
		return
	_speed_label.text = "%d" % roundi(player.speed_kmh)
	_score_label.text = "%s  %d" % [tr("UI_SCORE"), GameState.score]
	if scoring != null and scoring.combo.is_active():
		_combo_bar.value = scoring.combo.time_left / maxf(scoring.combo.timeout, 0.01)


func _on_combo_changed(chain: int, multiplier: int) -> void:
	_combo_root.visible = chain > 0
	if chain <= 0:
		return
	_combo_label.text = "%s ×%d" % [tr("UI_COMBO"), multiplier]
	if _combo_tween != null:
		_combo_tween.kill()
	_combo_label.scale = Vector2(1.18, 1.18)
	_combo_tween = create_tween()
	_combo_tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_score_awarded(event_type: int, points: int, multiplier: int, _total: int) -> void:
	var title := tr(SkillEvent.type_key(event_type))
	if multiplier > 1:
		title = "%s ×%d" % [title, multiplier]
	var strong := event_type == SkillEvent.Type.TIGHT_GAP
	_show_popup("%s\n+%d" % [title, points], _gap_settings if strong else _popup_settings, 1.35 if strong else 1.1)


func _on_combo_lost(reason: int) -> void:
	if reason == ScoringSystem.LossReason.COLLISION:
		_show_popup(tr("UI_COMBO_LOST"), _loss_settings, 0.9)


func _show_popup(text: String, settings: LabelSettings, punch: float) -> void:
	if notifications != null and notifications.critical_active():
		return  # never stack score popups over a critical warning
	var popup := _popups[_popup_index]
	_popup_index = (_popup_index + 1) % POPUP_COUNT
	popup.text = text
	popup.label_settings = settings
	var w := minf(600.0, safe_root.size.x)
	place(popup, Vector2(0.5, 0.0), Rect2(-w * 0.5, 260, w, 0))  # below the banner zone
	popup.pivot_offset = Vector2(w * 0.5, 40)
	popup.modulate.a = 1.0
	popup.scale = Vector2(punch, punch)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "position:y", 228.0, 1.1).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.5).set_delay(0.7)
