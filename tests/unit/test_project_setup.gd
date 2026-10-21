extends "res://tests/test_case.gd"

const ACTIONS := ["accelerate", "brake_reverse", "steer_left", "steer_right", "handbrake", "horn",
		"reset_vehicle", "pause", "debug_toggle_hud", "debug_toggle_traffic", "debug_toggle_vehicle"]
const UI_KEYS := ["UI_SCORE", "UI_SPEED", "UI_KMH", "UI_COMBO", "UI_COMBO_LOST", "UI_CLOSE_CALL",
		"UI_TIGHT_GAP", "UI_PAUSED", "UI_PAUSE_HINT"]


func test_input_actions_exist_with_bindings() -> void:
	for action in ACTIONS:
		check(InputMap.has_action(action), "action %s exists" % action)
		if InputMap.has_action(action):
			check(not InputMap.action_get_events(action).is_empty(), "action %s has a binding" % action)


func test_fixed_stack_settings() -> void:
	check_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "mobile", "Mobile renderer")
	check_eq(ProjectSettings.get_setting("physics/3d/physics_engine"), "Jolt Physics", "Jolt physics")
	check_eq(int(ProjectSettings.get_setting("display/window/handheld/orientation")), 0, "landscape")


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


func test_traffic_classes_cover_four_types_with_varied_speeds() -> void:
	var kinds := {}
	var pool := 0
	for name in ["car", "bus", "motorcycle", "tuk"]:
		var cls := load("res://resources/traffic/%s.tres" % name) as TrafficVehicleClass
		check(cls != null, "%s class loads" % name)
		if cls == null:
			continue
		kinds[cls.kind] = true
		pool += cls.pool_count
		check(cls.max_speed_kmh - cls.min_speed_kmh >= 15.0, "%s has a wide speed range" % name)
	check_eq(kinds.size(), 4, "four logical traffic types")
	check_eq(pool, 24, "pool capacity 24")
