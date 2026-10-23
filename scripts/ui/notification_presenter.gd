class_name NotificationPresenter
extends CanvasLayer
## One place for on-screen notices (v0.03A2), so systems never drop labels at
## arbitrary positions. Banners sit in a fixed zone below the GPS line, inside
## the safe area, width-capped and word-wrapped.
##
## Categories (style): SKILL, WARNING, INCIDENT, DAMAGE, RIDE.
## Priority: CRITICAL (pedestrian impact, tuk disabled, ride failed) >
## HIGH (pickup/destination, major incident) > NORMAL. At most two banners;
## a higher priority replaces a lower one, and while a CRITICAL banner is up
## PrototypeHud suppresses score popups (critical_active()).

enum Category { SKILL, WARNING, INCIDENT, DAMAGE, RIDE }
enum Priority { NORMAL, HIGH, CRITICAL }

const SLOTS := 2
const COLORS := {
	Category.SKILL: Color(1.0, 0.95, 0.75), Category.WARNING: Color(1.0, 0.4, 0.3),
	Category.INCIDENT: Color(1.0, 0.75, 0.3), Category.DAMAGE: Color(1.0, 0.3, 0.2),
	Category.RIDE: Color(0.55, 0.95, 1.0),
}

var safe_root: HudSafeArea
var _box: VBoxContainer
var _panels: Array[PanelContainer] = []
var _labels: Array[Label] = []
var _priority := PackedInt32Array()
var _time_left := PackedFloat32Array()
## Diagnostics (tests).
var shown := 0
var replaced := 0
var dropped := 0


func _ready() -> void:
	layer = 22
	safe_root = HudSafeArea.new()
	safe_root.name = "SafeArea"
	add_child(safe_root)
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 8)
	safe_root.add_child(_box)
	for i in SLOTS:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.07, 0.08, 0.8)
		style.set_corner_radius_all(10)
		style.border_width_bottom = 2
		style.border_color = Color(0.1, 0.62, 0.62, 0.9)  # v0.03B teal accent
		style.set_content_margin_all(10)
		panel.add_theme_stylebox_override("panel", style)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.visible = false
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 2
		var ls := LabelSettings.new()
		ls.font_size = 34
		ls.outline_size = 8
		ls.outline_color = Color(0, 0, 0, 0.9)
		label.label_settings = ls
		panel.add_child(label)
		_box.add_child(panel)
		_panels.append(panel)
		_labels.append(label)
		_priority.append(-1)
		_time_left.append(0.0)
	safe_root.resized.connect(layout)
	layout()
	EventBus.pedestrian_impact.connect(func(_e: PedestrianEvent) -> void:
		notify(tr("UI_UNSAFE_DRIVING"), Category.WARNING, Priority.CRITICAL, 2.5))
	EventBus.ride_finished.connect(func(r: RideResult) -> void:
		if r.outcome == RideResult.Outcome.FAILED:
			notify(tr("UI_RIDE_FAILED"), Category.RIDE, Priority.CRITICAL, 2.5))
	EventBus.ride_state_changed.connect(func(st: int) -> void:
		if st == RideManager.RideState.ACTIVE:
			notify(tr("UI_NOTIFY_ON_BOARD"), Category.RIDE, Priority.HIGH, 2.0))
	EventBus.traffic_incident_started.connect(func(tier: int, _p: Vector3) -> void:
		if tier == IncidentRules.Tier.MAJOR:
			notify(tr("UI_NOTIFY_MAJOR_INCIDENT"), Category.INCIDENT, Priority.HIGH, 2.0))
	EventBus.vehicle_damage_changed.connect(_on_damage)
	EventBus.vehicle_recovered.connect(func(reason: String) -> void:
		if reason == "void":
			notify(tr("UI_RESETTING_TO_ROAD"), Category.WARNING, Priority.HIGH, 1.6))


func _on_damage(st: int) -> void:
	if st == VehicleDamageState.State.DAMAGED:
		notify(tr("UI_TUK_DAMAGED"), Category.DAMAGE, Priority.HIGH, 2.0)
	elif st == VehicleDamageState.State.DISABLED:
		notify(tr("UI_TUK_DISABLED"), Category.DAMAGE, Priority.CRITICAL, 2.2)
		notify(tr("UI_RESETTING_TO_ROAD"), Category.DAMAGE, Priority.CRITICAL, 2.4)


## Centre column between the side cards (hire card left, ride panel right),
## below the GPS line (y 0–52) and the combo meter (64–110).
func layout() -> void:
	var sw := safe_root.size.x
	var card := minf(400.0, sw * 0.36)
	var w := clampf(sw - 2.0 * card - 32.0, 260.0, 560.0)
	PrototypeHud.place(_box, Vector2(0.5, 0.0), Rect2(-w * 0.5, 118, w, 0))
	for p in _panels:
		p.custom_minimum_size = Vector2(w, 0)


## Shows `text`. Replaces the lowest-priority banner if both slots are busy;
## a NORMAL notice is dropped while a CRITICAL one is showing.
func notify(text: String, category: Category, priority: Priority, seconds: float) -> void:
	if priority == Priority.NORMAL and critical_active():
		dropped += 1
		return
	var slot := -1
	for i in SLOTS:
		if _priority[i] < 0:
			slot = i
			break
	if slot < 0:
		var lowest := 0
		for i in SLOTS:
			if _priority[i] < _priority[lowest]:
				lowest = i
		if _priority[lowest] > priority:
			dropped += 1
			return
		slot = lowest
		replaced += 1
	_labels[slot].text = text
	_labels[slot].label_settings.font_color = COLORS[category]
	_priority[slot] = priority
	_time_left[slot] = seconds
	_panels[slot].visible = true
	shown += 1


func critical_active() -> bool:
	for i in SLOTS:
		if _priority[i] == Priority.CRITICAL:
			return true
	return false


func visible_panels() -> Array[PanelContainer]:
	var out: Array[PanelContainer] = []
	for p in _panels:
		if p.visible:
			out.append(p)
	return out


func _process(delta: float) -> void:
	var ps := PerfSections.begin()
	_process_body(delta)
	PerfSections.end(PerfSections.NOTIFICATIONS, ps)


func _process_body(delta: float) -> void:
	for i in SLOTS:
		if _priority[i] < 0:
			continue
		_time_left[i] -= delta
		if _time_left[i] <= 0.0:
			_priority[i] = -1
			_panels[i].visible = false
