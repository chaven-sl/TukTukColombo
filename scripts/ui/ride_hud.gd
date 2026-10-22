class_name RideHud
extends CanvasLayer
## Lightweight ride UI: offer card + accept prompt, pickup hint, active-ride
## panel, passenger reaction bubble, ride result card, unsafe-driving notice,
## and simple world beacons (pickups while available, destination during a
## ride). Presentation only; all text via translation keys; speeds in km/h.

var rides: RideManager
var offers: PassengerOfferManager
var world: Node3D

var _offer_panel: PanelContainer
var _offer_label: Label
var _ride_panel: PanelContainer
var _ride_label: Label
var _bubble: Label
var _notice: Label
var _result_panel: PanelContainer
var _result_label: Label
var _result_timer := 0.0
var _notice_timer := 0.0
var _mood_timer := 0.0
var _mood_state: PassengerMood.Mood = PassengerMood.Mood.HAPPY
var _pickup_beacons: Dictionary = {}  # PassengerOffer -> MeshInstance3D
var _dest_beacon: MeshInstance3D


func setup(p_rides: RideManager, p_offers: PassengerOfferManager, p_world: Node3D) -> void:
	rides = p_rides
	offers = p_offers
	world = p_world
	rides.result_ready.connect(_on_result)
	rides.reaction.connect(_on_reaction)
	EventBus.pedestrian_impact.connect(_on_pedestrian_impact)
	for offer in offers.offers:
		_pickup_beacons[offer] = _beacon(offer.profile.marker_color, 0.18)
	_dest_beacon = _beacon(Color(0.2, 1.0, 0.45), 0.35)


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_offer_panel = _panel(root, Control.PRESET_CENTER_BOTTOM, Vector2(-230, -190), Vector2(460, 0))
	_offer_label = _label(_offer_panel, 22)
	_ride_panel = _panel(root, Control.PRESET_TOP_RIGHT, Vector2(-380, 18), Vector2(360, 0))
	_ride_label = _label(_ride_panel, 20)
	_result_panel = _panel(root, Control.PRESET_CENTER, Vector2(-250, -190), Vector2(500, 0))
	_result_label = _label(_result_panel, 22)
	_bubble = Label.new()
	_bubble.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bubble.position = Vector2(-350, -260)
	_bubble.custom_minimum_size = Vector2(700, 0)
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.label_settings = _settings(30, Color(1, 1, 1))
	root.add_child(_bubble)
	_notice = Label.new()
	_notice.set_anchors_preset(Control.PRESET_CENTER)
	_notice.position = Vector2(-350, -40)
	_notice.custom_minimum_size = Vector2(700, 0)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.label_settings = _settings(44, Color(1.0, 0.35, 0.3))
	root.add_child(_notice)
	_offer_panel.visible = false
	_ride_panel.visible = false
	_result_panel.visible = false


func _settings(size: int, color: Color) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.9)
	return ls


func _panel(parent: Control, preset: Control.LayoutPreset, pos: Vector2, min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.72)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(preset)
	panel.position = pos
	panel.custom_minimum_size = min_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _label(parent: Control, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func _beacon(color: Color, width: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 7.0, width)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	world.add_child(mi)
	return mi


static func interact_key_label() -> String:
	var events := InputMap.action_get_events("interact")
	for ev in events:
		var key := ev as InputEventKey
		if key != null:
			return OS.get_keycode_string(key.physical_keycode if key.physical_keycode != 0 else key.keycode)
	return "?"


static func km(meters: float) -> String:
	return "%.1f km" % (meters / 1000.0)


func _process(delta: float) -> void:
	if rides == null:
		return
	_update_beacons()
	_update_offer_panel()
	_update_ride_panel(delta)
	if _result_timer > 0.0:
		_result_timer -= delta
		if _result_timer <= 0.0:
			_result_panel.visible = false
	_bubble.visible = rides.current_reaction_time > 0.0
	if _notice_timer > 0.0:
		_notice_timer -= delta
	_notice.visible = _notice_timer > 0.0


func _unhandled_input(event: InputEvent) -> void:
	if _result_panel != null and _result_panel.visible and event.is_action_pressed("interact") and rides.nearby_offer == null:
		_result_panel.visible = false
		_result_timer = 0.0


func _update_beacons() -> void:
	for offer in _pickup_beacons.keys():
		var beacon: MeshInstance3D = _pickup_beacons[offer]
		var o: PassengerOffer = offer
		beacon.visible = o.state == PassengerOffer.State.AVAILABLE or (o == rides.offer and rides.state == RideManager.RideState.EN_ROUTE_TO_PICKUP)
		if beacon.visible:
			beacon.global_position = o.pickup.global_position + Vector3(0, 3.5, 0)
	var show_dest := rides.state == RideManager.RideState.ACTIVE and rides.offer != null
	_dest_beacon.visible = show_dest
	if show_dest:
		_dest_beacon.global_position = rides.offer.destination.global_position + Vector3(0, 3.5, 0)


func _update_offer_panel() -> void:
	var offer := rides.nearby_offer
	var lines := PackedStringArray()
	match rides.state:
		RideManager.RideState.NO_RIDE:
			if offer != null:
				lines.append(tr(offer.profile.display_name_key).to_upper())
				lines.append("%s: %s" % [tr("UI_DESTINATION"), tr(offer.destination.display_name_key)])
				lines.append("%s: %s" % [tr("UI_DISTANCE"), km(offer.route_m)])
				lines.append("%s: %s" % [tr("UI_PRIORITY"), tr(offer.profile.priority_key)])
				lines.append("")
				lines.append(tr("UI_ACCEPT_RIDE") % interact_key_label())
		RideManager.RideState.EN_ROUTE_TO_PICKUP:
			lines.append(tr("UI_PICKUP_HINT") % tr(rides.offer.profile.display_name_key))
		RideManager.RideState.BOARDING:
			lines.append(tr("UI_BOARDING"))
	_offer_panel.visible = not lines.is_empty()
	_offer_label.text = "\n".join(lines)


func _update_ride_panel(delta: float) -> void:
	var active := rides.state == RideManager.RideState.ACTIVE and rides.telemetry != null
	_ride_panel.visible = active
	if not active:
		return
	_mood_timer -= delta
	if _mood_timer <= 0.0:
		_mood_timer = 0.5
		_mood_state = PassengerMood.evaluate(rides.telemetry, rides.offer.profile, rides.offer.route_m, rides.remaining_m, rides.config)
	var t := rides.telemetry
	var lines := PackedStringArray()
	lines.append(tr(rides.offer.profile.display_name_key).to_upper())
	lines.append("%s: %s" % [tr("UI_DESTINATION"), tr(rides.offer.destination.display_name_key)])
	lines.append("%s: %s" % [tr("UI_REMAINING"), km(rides.remaining_m)])
	lines.append("%s: %s" % [tr("UI_PASSENGER_MOOD"), tr(PassengerMood.KEYS[_mood_state])])
	lines.append("%s: %d:%02d" % [tr("UI_RIDE_TIME"), int(t.elapsed) / 60, int(t.elapsed) % 60])
	_ride_label.text = "\n".join(lines)


func _on_reaction(key: String) -> void:
	_bubble.text = "“%s”" % tr(key)


func _on_pedestrian_impact(_event: PedestrianEvent) -> void:
	_notice.text = tr("UI_UNSAFE_DRIVING")
	_notice_timer = 2.5


func _on_result(result: RideResult) -> void:
	var t := result.telemetry
	var lines := PackedStringArray()
	if result.outcome == RideResult.Outcome.COMPLETED:
		lines.append(tr("UI_RIDE_COMPLETE"))
	else:
		lines.append(tr("UI_RIDE_FAILED"))
		lines.append(tr("FAIL_PEDESTRIAN") if result.fail_reason == RideResult.FailReason.PEDESTRIAN_IMPACT else tr("FAIL_ROLLOVER"))
	lines.append("")
	lines.append("%-20s %s" % [tr("UI_PASSENGER"), tr(result.profile.display_name_key)])
	lines.append("%-20s %s" % [tr("UI_DISTANCE"), km(t.distance_m)])
	lines.append("%-20s %d:%02d" % [tr("UI_RIDE_TIME"), int(t.elapsed) / 60, int(t.elapsed) % 60])
	lines.append("%-20s %d km/h" % [tr("UI_AVERAGE_SPEED"), roundi(t.average_speed_kmh())])
	lines.append("%-20s %s" % [tr("UI_DRIVING_STYLE"), tr(result.style_key)])
	lines.append("%-20s %d%%" % [tr("UI_PASSENGER_RATING"), roundi(result.satisfaction.final_score)])
	if result.outcome == RideResult.Outcome.COMPLETED:
		lines.append("")
		lines.append("%-20s Rs. %d" % [tr("UI_BASE_FARE"), result.base_fare])
		lines.append("%-20s %sRs. %d" % [tr("UI_ADJUSTMENT"), "+" if result.adjustment >= 0 else "−", absi(result.adjustment)])
		lines.append("%-20s Rs. %d" % [tr("UI_FINAL_FARE"), result.final_fare])
	_result_label.text = "\n".join(lines)
	_result_panel.visible = true
	_result_timer = rides.config.result_display_seconds
