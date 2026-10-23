extends Node
## v0.03A2 HUD safe-area matrix in the real prototype scene (touch layout).
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/hud_safe_area_test.tscn
##
## For 5 Android aspect ratios × 6 safe-area cases, fills every HUD element
## with long (translation-length) text and checks: inside the safe rect with
## the inner margin, no overlap with touch controls, no overlap between cards
## shown together, and the result card + banners case.

const MAIN := preload("res://scenes/prototype/prototype_main.tscn")
## device px -> logical viewport (canvas_items / expand from 1280×720)
const DEVICES := {
	"1920x1080": Vector2(1280, 720), "2400x1080": Vector2(1600, 720), "2340x1080": Vector2(1560, 720),
	"2520x1080": Vector2(1680, 720), "1280x800": Vector2(1280, 800),
}
const LONG_NAME := "Grandmother From Kandy With Many Parcels"
const LONG_PLACE := "Galle Face Green Northern Promenade Entrance"
const LONG_NOTICE := "A very long translated warning message that must wrap inside the safe area"

var main: Node3D
var hud: PrototypeHud
var ride_hud: RideHud
var notes: NotificationPresenter
var controls: MobileControls
var _failures := 0
var _checks := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = MAIN.instantiate()
	var tm: TrafficManager = main.get_node("TrafficManager")
	var tcfg: TrafficConfig = tm.config.duplicate()
	tcfg.gameplay_density_target = 0
	tm.config = tcfg
	add_child(main)
	hud = main.get_node("HUD")
	ride_hud = main.get_node("RideHud")
	notes = main.get_node("Notifications")
	controls = main.get_node("MobileControls")
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		print("  [FAIL] %s  %s" % [label, detail])
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _safe_cases(view: Vector2) -> Dictionary:
	return {
		"full": Rect2(Vector2.ZERO, view),
		"left cutout": HudSafeArea.apply_insets(Rect2(Vector2.ZERO, view), Vector4(56, 0, 0, 0)),
		"right cutout": HudSafeArea.apply_insets(Rect2(Vector2.ZERO, view), Vector4(0, 0, 56, 0)),
		"both sides": HudSafeArea.apply_insets(Rect2(Vector2.ZERO, view), Vector4(48, 0, 48, 0)),
		"gesture bar": HudSafeArea.apply_insets(Rect2(Vector2.ZERO, view), Vector4(0, 0, 0, 28)),
		"asymmetric": HudSafeArea.apply_insets(Rect2(Vector2.ZERO, view), Vector4(64, 12, 24, 20)),
	}


func _apply(view: Vector2, safe: Rect2) -> void:
	for root: HudSafeArea in [hud.safe_root, ride_hud.safe_root, notes.safe_root]:
		root.apply_safe_rect(safe)
	controls.apply_layout(view, safe)


func _fill() -> void:
	ride_hud.set_process(false)  # keep the test content (normally driven by ride state)
	hud.set_process(false)
	hud.get("_score_label").text = "%s  %d" % [tr("UI_SCORE"), 1234567]
	hud.get("_speed_label").text = "188"
	# v0.03B1 compact card: worst case per field (long name, long route).
	(ride_hud.get("_offer_label") as Label).text = LONG_NAME.to_upper()
	(ride_hud.get("_offer_route") as Label).text = "%s → %s" % [LONG_PLACE, LONG_PLACE]
	(ride_hud.get("_offer_dist") as Label).text = "12.4 km"
	(ride_hud.get("_offer_chip_label") as Label).text = tr("PRIORITY_EXCITING")
	(ride_hud.get("_offer_hint") as Label).text = tr("UI_ACCEPT_HIRE") % "E"
	(ride_hud.get("_offer_hint") as Label).visible = true
	(ride_hud.get("_offer_panel") as Control).visible = true
	(ride_hud.get("_gps_label") as Label).text = "DESTINATION — 1160 m"
	(ride_hud.get("_gps_panel") as Control).visible = true
	(ride_hud.get("_ride_label") as Label).text = LONG_NAME.to_upper()
	(ride_hud.get("_ride_dest") as Label).text = "→ %s" % LONG_PLACE
	(ride_hud.get("_ride_dist") as Label).text = "1.2 km"
	(ride_hud.get("_ride_chip_label") as Label).text = tr("MOOD_IMPATIENT")
	(ride_hud.get("_ride_time") as Label).text = "12:34"
	(ride_hud.get("_ride_panel") as Control).visible = true
	var bubble: Label = ride_hud.get("_bubble")
	bubble.text = "“%s”" % LONG_NOTICE
	bubble.visible = true
	notes.notify(LONG_NOTICE, NotificationPresenter.Category.WARNING, NotificationPresenter.Priority.CRITICAL, 999.0)
	notes.notify(tr("UI_RESETTING_TO_ROAD"), NotificationPresenter.Category.DAMAGE, NotificationPresenter.Priority.CRITICAL, 999.0)


func _elements() -> Dictionary:
	var d := {
		"score": hud.get("_score_label"), "speed": hud.get("_speed_label"), "km/h": hud.get("_speed_unit"),
		"hire card": ride_hud.get("_offer_panel"), "gps": ride_hud.get("_gps_panel"), "ride card": ride_hud.get("_ride_panel"),
		"passenger bubble": ride_hud.get("_bubble"),
	}
	var i := 0
	for p in notes.visible_panels():
		d["banner %d" % i] = p
		i += 1
	return d


func _run() -> void:
	main.call("set_touch_mode", true)
	_fill()
	for device in DEVICES:
		var view: Vector2 = DEVICES[device]
		var cases := _safe_cases(view)
		for case_name in cases:
			var safe: Rect2 = cases[case_name]
			_apply(view, safe)
			await _frames(3)
			var tag := "%s / %s" % [device, case_name]
			var inner := safe.grow(-HudSafeArea.MARGIN + 1.0)
			var els := _elements()
			for k in els:
				var r := (els[k] as Control).get_global_rect()
				_check("%s: %s inside safe area (+margin)" % [tag, k], inner.encloses(r), "%s vs %s" % [r, inner])
				for c in controls.rects:
					if c == TouchControlState.Pad.ACCEPT:
						continue  # hidden while not offered
					var cr: Rect2 = controls.rects[c]
					_check("%s: %s clear of %s" % [tag, k, TouchControlState.Pad.keys()[c]], not r.intersects(cr), "%s vs %s" % [r, cr])
			var keys := els.keys()
			for a in keys.size():
				for b in range(a + 1, keys.size()):
					var ra := (els[keys[a]] as Control).get_global_rect()
					var rb := (els[keys[b]] as Control).get_global_rect()
					_check("%s: %s vs %s no overlap" % [tag, keys[a], keys[b]], not ra.intersects(rb), "%s / %s" % [ra, rb])
			# Result card (after a ride) shown with the banners.
			var result: Control = ride_hud.get("_result_panel")
			# v0.04 worst case: every payout line on a PREMIUM ride.
			ride_hud.call("_show_result", _worst_case_result())
			await _frames(2)
			result.visible = true
			await _frames(3)
			var rr := result.get_global_rect()
			_check("%s: result card inside safe area" % tag, inner.encloses(rr), "%s vs %s" % [rr, inner])
			for p in notes.visible_panels():
				_check("%s: result card clear of banners" % tag, not rr.intersects(p.get_global_rect()), "%s / %s" % [rr, p.get_global_rect()])
			result.visible = false
	# Left-edge alignment: pause, score and hire card share the safe left column.
	var safe0 := _safe_cases(Vector2(1600, 720))["left cutout"] as Rect2
	_apply(Vector2(1600, 720), safe0)
	await _frames(3)
	var pause: Rect2 = controls.rects[TouchControlState.Pad.PAUSE]
	var card := (ride_hud.get("_offer_panel") as Control).get_global_rect()
	var steer: Rect2 = controls.rects[TouchControlState.Pad.STEER]
	var speed := (hud.get("_speed_label") as Control).get_global_rect()
	_check("left column aligned (pause / hire card)", absf(pause.position.x - card.position.x) < 1.0, "%.1f vs %.1f" % [pause.position.x, card.position.x])
	_check("speed aligned with the steering pad", absf(speed.position.x - steer.position.x) < 1.0, "%.1f vs %.1f" % [speed.position.x, steer.position.x])
	_check("left column starts past the cutout + margin", card.position.x >= safe0.position.x + HudSafeArea.MARGIN - 0.5)
	print("")
	print("=== HUD SAFE AREA: %s — %d checks, %d failures ===" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _worst_case_result() -> RideResult:
	var r := RideResult.new()
	r.outcome = RideResult.Outcome.COMPLETED
	r.profile = load("res://resources/passengers/rushed.tres")
	r.telemetry = RideTelemetry.new()
	r.satisfaction = PassengerSatisfaction.new()
	r.satisfaction.final_score = 88.0
	r.style_key = "STYLE_SMOOTH"
	r.job_tier = JobTiers.Tier.PREMIUM
	r.payout_lines = [["PAY_BASE_FARE", 1640], ["PAY_PASSENGER_RATING", 210], ["PAY_CLEAN_RIDE", 140], ["PAY_SMOOTH_STOP", 70],
			["PAY_FAST_FARE", 110], ["PAY_SKILL", 280], ["PAY_COLLISIONS", -140], ["PAY_MAJOR_COLLISIONS", -280], ["PAY_JOB_BONUS", 1230]]
	r.cash_earned = 3260
	r.reputation_earned = 12
	return r
