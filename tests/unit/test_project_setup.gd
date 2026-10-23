extends "res://tests/test_case.gd"

const ACTIONS := ["accelerate", "brake_reverse", "steer_left", "steer_right", "handbrake", "horn",
		"reset_vehicle", "pause", "debug_toggle_hud", "debug_toggle_traffic", "debug_toggle_vehicle",
		"interact", "debug_toggle_humans"]
const UI_KEYS := ["UI_SCORE", "UI_SPEED", "UI_KMH", "UI_COMBO", "UI_COMBO_LOST", "UI_CLOSE_CALL",
		"UI_TIGHT_GAP", "UI_PAUSED", "UI_PAUSE_HINT", "UI_ACCEPT_RIDE", "UI_DESTINATION", "UI_DISTANCE", "UI_PRIORITY",
		"UI_PICKUP_HINT", "UI_REMAINING", "UI_PASSENGER_MOOD", "UI_RIDE_TIME", "UI_UNSAFE_DRIVING", "UI_RIDE_COMPLETE",
		"UI_RIDE_FAILED", "UI_BASE_FARE", "UI_ADJUSTMENT", "UI_FINAL_FARE", "PASSENGER_RUSHED_NAME", "PASSENGER_CAREFUL_NAME",
		"PASSENGER_THRILL_SEEKER_NAME", "PRIORITY_FAST", "PRIORITY_SAFE", "PRIORITY_EXCITING", "DEST_MARKET", "DEST_TEMPLE",
		"DEST_SOUTH_JUNCTION", "DEST_CENTRAL_STOP", "REACT_HURRY_UP", "REACT_TOO_FAST", "REACT_CLOSE_CALL_POS",
		"REACT_CLOSE_CALL_NEG", "REACT_PEDESTRIAN_DANGER", "REACT_ARRIVAL_SUCCESS", "REACT_ARRIVAL_POOR", "STYLE_SMOOTH"]


func test_input_actions_exist_with_bindings() -> void:
	for action in ACTIONS:
		check(InputMap.has_action(action), "action %s exists" % action)
		if InputMap.has_action(action):
			check(not InputMap.action_get_events(action).is_empty(), "action %s has a binding" % action)


func test_fixed_stack_settings() -> void:
	check_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "mobile", "Mobile renderer")
	check_eq(ProjectSettings.get_setting("physics/3d/physics_engine"), "Jolt Physics", "Jolt physics")
	check([0, 2, 4].has(int(ProjectSettings.get_setting("display/window/handheld/orientation"))), "landscape (landscape / reverse / sensor landscape)")


func test_english_translations_complete() -> void:
	TranslationServer.set_locale("en")
	for key in UI_KEYS:
		var text := TranslationServer.translate(key)
		check(text != key and not String(text).is_empty(), "%s translated in en (%s)" % [key, text])


func test_sinhala_and_tamil_load_with_fallback() -> void:
	var locales := TranslationServer.get_loaded_locales()
	check(locales.has("si"), "si translation loaded")
	check(locales.has("ta"), "ta translation loaded")
	TranslationServer.set_locale("si")
	check(TranslationServer.translate("UI_SCORE") != "UI_SCORE", "si has a test string")
	check(TranslationServer.translate("UI_TIGHT_GAP") != "UI_TIGHT_GAP", "missing si string falls back to English")
	TranslationServer.set_locale("en")


func test_traffic_classes_cover_five_types_with_varied_speeds() -> void:
	var kinds := {}
	var pool := 0
	for name in ["car", "bus", "motorcycle", "tuk", "van"]:
		var cls := load("res://resources/traffic/%s.tres" % name) as TrafficVehicleClass
		check(cls != null, "%s class loads" % name)
		if cls == null:
			continue
		kinds[cls.kind] = true
		pool += cls.pool_count
		check(cls.max_speed_kmh - cls.min_speed_kmh >= 15.0, "%s has a wide speed range" % name)
	check_eq(kinds.size(), 5, "five logical traffic types (v0.03B adds the van)")
	check_eq(pool, 24, "pool capacity still 24")


func test_new_keys_exist_in_every_catalogue() -> void:
	# Sinhala/Tamil may leave msgstr empty (English fallback) but the key must exist.
	for lang in ["en", "si", "ta"]:
		var text := FileAccess.get_file_as_string("res://locale/%s.po" % lang)
		for key in UI_KEYS:
			check(text.contains('msgid "%s"' % key), "%s present in %s.po" % [key, lang])

