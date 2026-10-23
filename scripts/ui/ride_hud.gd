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
var _offer_label: Label
var _ride_panel: PanelContainer
var _ride_label: Label
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
	_offer_label = _label(_offer_panel, 21)
	_gps_panel = _panel(root)
	_gps_label = _label(_gps_panel, 30)
	_gps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(_gps_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0.02, 0.18, 0.28, 0.82)
	_ride_panel = _panel(root)
	_ride_label = _label(_ride_panel, 20)
	_result_panel = _panel(root)
	_result_label = _label(_result_panel, 22)
	_result_label.max_lines_visible = 16
	_offer_label.max_lines_visible = 7  # key facts first; long names wrap, never reach the speed readout
	_ride_label.max_lines_visible = 8
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
	var card := minf(400.0, w * 0.36)
	PrototypeHud.place(_offer_panel, Vector2.ZERO, Rect2(0, 76, card, 0))  # under score and the touch pause button
	var gps := minf(440.0, w - 2.0 * card - 24.0)
	PrototypeHud.place(_gps_panel, Vector2(0.5, 0.0), Rect2(-gps * 0.5, 0, gps, 0))
	PrototypeHud.place(_ride_panel, Vector2(1.0, 0.0), Rect2(-card, 0, card, 0))
	# Result card takes the right column (the ride panel is gone by then),
	# leaving the centre column to the banners.
	PrototypeHud.place(_result_panel, Vector2(1.0, 0.0), Rect2(-card, 0, card, 0))
	# Passenger line: centre column near the bottom, between the steering pad
	# and the pedals, below the banners.
	var bubble := clampf(w - 2.0 * card - 32.0, 260.0, 700.0)
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
	style.bg_color = Color(0.06, 0.07, 0.08, 0.72)
	style.set_corner_radius_all(10)
	style.border_width_bottom = 2
	style.border_color = Color(0.1, 0.62, 0.62, 0.9)  # v0.03B teal accent
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


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
	var lines := PackedStringArray()
	match rides.state:
		RideManager.RideState.NO_RIDE:
			if offer != null:
				lines.append(tr("UI_HIRE_AVAILABLE"))
				lines.append(tr(offer.profile.display_name_key).to_upper())
				lines.append("%s: %s" % [tr("UI_PICKUP"), tr(offer.pickup.display_name_key)])
				lines.append("%s: %s" % [tr("UI_DESTINATION"), tr(offer.destination.display_name_key)])
				lines.append("%s: %s" % [tr("UI_TRIP"), km(offer.route_m)])
				lines.append("%s: %s" % [tr("UI_PRIORITY"), tr(offer.profile.priority_key)])
				if not touch_mode:
					lines.append(tr("UI_ACCEPT_HIRE") % interact_key_label())
		RideManager.RideState.EN_ROUTE_TO_PICKUP:
			lines.append(tr("UI_PICKUP_HINT") % tr(rides.offer.profile.display_name_key))
			lines.append("%s: %s" % [tr("UI_PICKUP"), tr(rides.offer.pickup.display_name_key)])
		RideManager.RideState.BOARDING:
			lines.append(tr("UI_BOARDING"))
	_offer_panel.visible = not lines.is_empty()
	_offer_label.text = "\n".join(lines)


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
	var lines := PackedStringArray()
	lines.append(tr(rides.offer.profile.display_name_key).to_upper())
	lines.append("%s: %s" % [tr("UI_DESTINATION"), tr(rides.offer.destination.display_name_key)])
	var remaining := guidance.remaining_m if guidance != null and guidance.plan != null else rides.remaining_m
	lines.append("%s: %s" % [tr("UI_REMAINING"), km(remaining)])
	lines.append("%s: %s" % [tr("UI_PASSENGER_MOOD"), tr(PassengerMood.KEYS[_mood_state])])
	lines.append("%s: %d:%02d" % [tr("UI_RIDE_TIME"), int(t.elapsed) / 60, int(t.elapsed) % 60])
	_ride_label.text = "\n".join(lines)


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
