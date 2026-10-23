class_name RideHud
extends CanvasLayer
## Lightweight ride UI: hire card + ACCEPT HIRE prompt, GPS instruction,
## selected-passenger marker, active-ride panel, passenger reaction bubble,
## ride result card, unsafe-driving notice, and world beacons. Presentation
## only; all text via translation keys; speeds in km/h.
##
## v0.03A1 hire UX: the offered hire is named on a card (passenger type,
## pickup, destination, trip, priority). Once accepted, the selected
## passenger's beacon dominates, every other offer is muted, and an overhead
## "PICK UP / <type> / <distance>" marker follows them; RouteGuidance draws
## the road route and the top-centre instruction.

var rides: RideManager
var offers: PassengerOfferManager
var world: Node3D
var guidance: RouteGuidance
## Touch mode hides the keyboard hint (the ACCEPT HIRE button replaces it).
var touch_mode := false

var _offer_panel: PanelContainer
## v0.03B1 compact hierarchy: headline (passenger type), route line,
## distance + priority chip, small accept hint.
var _offer_label: Label
var _offer_route: Label
var _offer_dist: Label
var _offer_chip: PanelContainer
var _offer_chip_label: Label
var _offer_hint: Label
var _ride_panel: PanelContainer
## Ride card: passenger, → destination, remaining + mood chip, small timer.
var _ride_label: Label
var _ride_dest: Label
var _ride_dist: Label
var _ride_chip: PanelContainer
var _ride_chip_label: Label
var _ride_time: Label
var _bubble: Label
## HUD root inside the safe area (v0.03A2).
var safe_root: HudSafeArea
var _result_panel: PanelContainer
var _result_label: Label
var _result_timer := 0.0
var _mood_timer := 0.0
var _mood_state: PassengerMood.Mood = PassengerMood.Mood.HAPPY
var _pickup_beacons: Dictionary = {}  # PassengerOffer -> MeshInstance3D
var _dest_beacon: MeshInstance3D
var _gps_panel: PanelContainer
var _gps_label: Label
var _pickup_tag: Label3D
var _text_timer := 0.0


func setup(p_rides: RideManager, p_offers: PassengerOfferManager, p_world: Node3D, p_guidance: RouteGuidance = null) -> void:
	rides = p_rides
	offers = p_offers
	world = p_world
	guidance = p_guidance
	rides.result_ready.connect(_on_result)
	rides.reaction.connect(_on_reaction)
	for offer in offers.offers:
		_pickup_beacons[offer] = _beacon(offer.profile.marker_color, 0.18)
	_dest_beacon = _beacon(Color(0.2, 1.0, 0.45), 0.35)
	_pickup_tag = Label3D.new()
	_pickup_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pickup_tag.no_depth_test = true
	_pickup_tag.fixed_size = true
	_pickup_tag.pixel_size = 0.0011
	_pickup_tag.font_size = 30
	_pickup_tag.outline_size = 10
	_pickup_tag.modulate = Color(1.0, 0.95, 0.4)
	_pickup_tag.render_priority = 10
	_pickup_tag.visible = false
	world.add_child(_pickup_tag)


func _ready() -> void:
	layer = 20
	# v0.03A2: all cards live inside the safe area and wrap their text.
	safe_root = HudSafeArea.new()
	safe_root.name = "SafeArea"
	add_child(safe_root)
	var root: Control = safe_root
	_offer_panel = _panel(root)
	var ov := _vbox(_offer_panel)
	_offer_label = _label(ov, 20)
	_offer_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
	_offer_route = _label(ov, 15)
	_offer_route.add_theme_color_override("font_color", Color(0.86, 0.88, 0.9))
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 10)
	ov.add_child(orow)
	_offer_dist = _label(orow, 18)
	_offer_dist.autowrap_mode = TextServer.AUTOWRAP_OFF
	_offer_chip = _chip(orow)
	_offer_chip_label = _offer_chip.get_child(0) as Label
	_offer_hint = _label(ov, 13)
	_offer_hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.74))
	_gps_panel = _panel(root)
	_gps_label = _label(_gps_panel, 24)
	_gps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(_gps_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0.02, 0.18, 0.28, 0.82)
	_ride_panel = _panel(root)
	var rv := _vbox(_ride_panel)
	_ride_label = _label(rv, 17)
	_ride_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
	_ride_dest = _label(rv, 15)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 10)
	rv.add_child(rrow)
	_ride_dist = _label(rrow, 18)
	_ride_dist.autowrap_mode = TextServer.AUTOWRAP_OFF
	_ride_chip = _chip(rrow)
	_ride_chip_label = _ride_chip.get_child(0) as Label
	_ride_time = _label(rv, 12)
	_ride_time.add_theme_color_override("font_color", Color(0.65, 0.67, 0.7))
	_result_panel = _panel(root)
	_result_label = _label(_result_panel, 22)
	_result_label.max_lines_visible = 16
	_offer_label.max_lines_visible = 2  # compact card: long names wrap to 2 lines, never reach the speed readout
	_offer_route.max_lines_visible = 2
	_offer_hint.max_lines_visible = 1
	_ride_dest.max_lines_visible = 2
	_ride_label.max_lines_visible = 2
	_bubble = Label.new()
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.max_lines_visible = 2
	_bubble.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bubble.label_settings = _settings(30, Color(1, 1, 1))
	root.add_child(_bubble)
	_offer_panel.visible = false
	_gps_panel.visible = false
	_ride_panel.visible = false
	_result_panel.visible = false
	_bubble.visible = false
	safe_root.resized.connect(layout)
	layout()


## Positions every card relative to the safe root; widths shrink on narrow
## safe areas so nothing reaches the screen edge.
func layout() -> void:
	var w := safe_root.size.x
	var card := minf(310.0, w * 0.28)  # v0.03B1: compact cards, more road visible
	PrototypeHud.place(_offer_panel, Vector2.ZERO, Rect2(0, 76, card, 0))  # under score and the touch pause button
	var gps := minf(440.0, w - 2.0 * card - 24.0)
	PrototypeHud.place(_gps_panel, Vector2(0.5, 0.0), Rect2(-gps * 0.5, 0, gps, 0))
	PrototypeHud.place(_ride_panel, Vector2(1.0, 0.0), Rect2(-card, 0, card, 0))
	# Result card takes the right column (the ride panel is gone by then),
	# leaving the centre column to the banners.
	PrototypeHud.place(_result_panel, Vector2(1.0, 0.0), Rect2(-card, 0, card, 0))
	# Passenger line: centre column near the bottom, between the steering pad
	# and the pedals, below the banners.
	# The bubble keeps its v0.03A2 width reservation (clear of the touch
	# steering pad and pedals), independent of the narrower cards.
	var bubble := clampf(w - 2.0 * minf(400.0, w * 0.36) - 32.0, 260.0, 700.0)
	PrototypeHud.place(_bubble, Vector2(0.5, 1.0), Rect2(-bubble * 0.5, -196, bubble, 40))


func _settings(size: int, color: Color) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.9)
	return ls


func _panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.07, 0.6)
	style.set_corner_radius_all(10)
	style.border_width_bottom = 2
	style.border_color = Color(0.1, 0.62, 0.62, 0.85)  # v0.03B teal accent
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _vbox(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	return v


## Small rounded status chip (priority / mood).
func _chip(parent: Control) -> PanelContainer:
	var chip := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.2, 0.6, 0.35)
	st.set_corner_radius_all(8)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 1
	st.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", st)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	chip.add_child(l)
	parent.add_child(chip)
	return chip


func _set_chip(chip: PanelContainer, label: Label, text: String, color: Color) -> void:
	label.text = text
	(chip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = color
	chip.visible = not text.is_empty()


const PRIORITY_COLORS := {"PRIORITY_SAFE": Color(0.18, 0.55, 0.32), "PRIORITY_FAST": Color(0.8, 0.45, 0.1), "PRIORITY_EXCITING": Color(0.7, 0.2, 0.55)}
const MOOD_COLORS := [Color(0.18, 0.55, 0.32), Color(0.8, 0.55, 0.1), Color(0.75, 0.5, 0.15), Color(0.15, 0.55, 0.7), Color(0.4, 0.42, 0.45), Color(0.75, 0.18, 0.15)]


func _label(parent: Control, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long (translated) text wraps, never overflows
	parent.add_child(label)
	return label


## v0.03B: a soft translucent light pillar + ground ring instead of a box —
## readable from the chase camera without looking like debug geometry.
func _beacon(color: Color, width: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = width * 0.9
	mesh.bottom_radius = width * 1.6
	mesh.height = 7.0
	mesh.radial_segments = 12
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.95
	torus.rings = 24
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = mat
	ring.position = Vector3(0, -3.45, 0)
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(ring)
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
	var ps := PerfSections.begin()
	_process_body(delta)
	PerfSections.end(PerfSections.HUD, ps)


func _process_body(delta: float) -> void:
	if rides == null:
		return
	_update_beacons()
	# Text cards refresh at 10 Hz (v0.03B1): rebuilding strings every frame
	# was measurable HUD cost for content that changes at most every 100 ms.
	_text_timer -= delta
	if _text_timer <= 0.0:
		_text_timer = 0.1
		_update_offer_panel()
		_update_gps()
	_update_ride_panel(delta)
	if _result_timer > 0.0:
		_result_timer -= delta
		if _result_timer <= 0.0:
			_result_panel.visible = false
	_bubble.visible = rides.current_reaction_time > 0.0


func _unhandled_input(event: InputEvent) -> void:
	if _result_panel != null and _result_panel.visible and event.is_action_pressed("interact"):
		_result_panel.visible = false
		_result_timer = 0.0


func _update_beacons() -> void:
	var selected: PassengerOffer = rides.offer if rides.state == RideManager.RideState.EN_ROUTE_TO_PICKUP \
			or rides.state == RideManager.RideState.BOARDING else null
	var highlighted: PassengerOffer = rides.nearby_offer if rides.state == RideManager.RideState.NO_RIDE else null
	var hire_taken := rides.state != RideManager.RideState.NO_RIDE
	for offer in _pickup_beacons.keys():
		var beacon: MeshInstance3D = _pickup_beacons[offer]
		var o: PassengerOffer = offer
		# Once a hire is taken only the selected passenger keeps a beacon.
		beacon.visible = o == selected or (not hire_taken and o.state == PassengerOffer.State.AVAILABLE)
		if o.passenger != null:
			if hire_taken and o != selected:
				o.passenger.hide_passenger_marker()
			elif o.state == PassengerOffer.State.AVAILABLE or o == selected:
				o.passenger.show_passenger_marker(o.profile.marker_color)
		if not beacon.visible:
			continue
		var emphasis := 3.0 if o == selected else (1.8 if o == highlighted else 1.0)
		beacon.scale = Vector3(emphasis, 1.0 + (emphasis - 1.0) * 0.6, emphasis)
		var anchor := o.passenger.global_position if o.passenger != null else o.pickup.global_position
		beacon.global_position = anchor + Vector3(0, 3.5 * beacon.scale.y, 0)
	var show_dest := rides.state == RideManager.RideState.ACTIVE and rides.offer != null
	_dest_beacon.visible = show_dest
	if show_dest:
		_dest_beacon.global_position = rides.offer.destination.global_position + Vector3(0, 3.5, 0)
	_update_pickup_tag(selected)


func _update_pickup_tag(selected: PassengerOffer) -> void:
	var agent := selected.passenger if selected != null else null
	_pickup_tag.visible = agent != null and rides.state == RideManager.RideState.EN_ROUTE_TO_PICKUP
	if not _pickup_tag.visible:
		return
	var dist := guidance.remaining_m if guidance != null and guidance.plan != null else agent.global_position.distance_to(rides.player.global_position)
	_pickup_tag.text = "%s\n%s\n%d m" % [tr("UI_PICK_UP_MARKER"), tr(selected.profile.display_name_key).to_upper(), RoutePlan.display_distance(dist)]
	_pickup_tag.global_position = agent.global_position + Vector3(0, 2.6, 0)


func _update_offer_panel() -> void:
	var offer := rides.nearby_offer
	var show := false
	_offer_route.visible = true
	_offer_hint.visible = false
	match rides.state:
		RideManager.RideState.NO_RIDE:
			if offer != null:
				show = true
				_offer_label.text = tr(offer.profile.display_name_key).to_upper()
				_offer_route.text = "%s → %s" % [tr(offer.pickup.display_name_key), tr(offer.destination.display_name_key)]
				_offer_dist.text = km(offer.route_m)
				_set_chip(_offer_chip, _offer_chip_label, tr(offer.profile.priority_key), PRIORITY_COLORS.get(offer.profile.priority_key, Color(0.3, 0.35, 0.4)))
				_offer_dist.get_parent().visible = true
				if not touch_mode:
					_offer_hint.visible = true
					_offer_hint.text = tr("UI_ACCEPT_HIRE") % interact_key_label()
		RideManager.RideState.EN_ROUTE_TO_PICKUP:
			show = true
			_offer_label.text = tr("UI_PICKUP_HINT") % tr(rides.offer.profile.display_name_key)
			_offer_route.text = tr(rides.offer.pickup.display_name_key)
			_offer_dist.get_parent().visible = false
		RideManager.RideState.BOARDING:
			show = true
			_offer_label.text = tr("UI_BOARDING")
			_offer_route.visible = false
			_offer_dist.get_parent().visible = false
	_offer_panel.visible = show


func _update_gps() -> void:
	var text := guidance.instruction_text() if guidance != null else ""
	_gps_panel.visible = not text.is_empty()
	_gps_label.text = text


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
	_ride_label.text = tr(rides.offer.profile.display_name_key).to_upper()
	_ride_dest.text = "→ %s" % tr(rides.offer.destination.display_name_key)
	var remaining := guidance.remaining_m if guidance != null and guidance.plan != null else rides.remaining_m
	_ride_dist.text = km(remaining)
	_set_chip(_ride_chip, _ride_chip_label, tr(PassengerMood.KEYS[_mood_state]), MOOD_COLORS[_mood_state])
	_ride_time.text = "%d:%02d" % [int(t.elapsed) / 60, int(t.elapsed) % 60]


func _on_reaction(key: String) -> void:
	_bubble.text = "“%s”" % tr(key)


func _on_result(result: RideResult) -> void:
	var t := result.telemetry
	var lines := PackedStringArray()
	if result.outcome == RideResult.Outcome.COMPLETED:
		lines.append(tr("UI_RIDE_COMPLETE"))
	else:
		lines.append(tr("UI_RIDE_FAILED"))
		match result.fail_reason:
			RideResult.FailReason.PEDESTRIAN_IMPACT:
				lines.append(tr("FAIL_PEDESTRIAN"))
			RideResult.FailReason.VEHICLE_DISABLED:
				lines.append(tr("FAIL_VEHICLE_DISABLED"))
			_:
				lines.append(tr("FAIL_ROLLOVER"))
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
