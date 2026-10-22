extends "res://tests/test_case.gd"
## v0.03A platform foundations: Android export preset, project settings,
## graphics profiles, input-mode selection and the qualitative passenger mood.

var _config: RideConfig = load("res://resources/rides/ride_config.tres")
var _rushed: PassengerProfile = load("res://resources/passengers/rushed.tres")
var _careful: PassengerProfile = load("res://resources/passengers/careful.tres")
var _thrill: PassengerProfile = load("res://resources/passengers/thrill_seeker.tres")


func test_android_export_preset() -> void:
	var cfg := ConfigFile.new()
	check_eq(cfg.load("res://export_presets.cfg"), OK, "export_presets.cfg parses")
	check_eq(cfg.get_value("preset.0", "name", ""), "Android Debug", "preset name")
	check_eq(cfg.get_value("preset.0", "platform", ""), "Android", "platform")
	check_eq(cfg.get_value("preset.0", "export_path", ""), "builds/android/tuktukcolombo-debug.apk", "output path")
	var excl: String = cfg.get_value("preset.0", "exclude_filter", "")
	check(excl.contains("tests/*") and excl.contains("docs/*") and excl.contains("tools/*"), "tests/docs/tools excluded")
	var o := "preset.0.options"
	check_eq(cfg.get_value(o, "package/unique_name", ""), "com.chavensl.tuktukcolombo", "package id")
	check_eq(str(cfg.get_value(o, "gradle_build/min_sdk", "")), "28", "min SDK 28")
	check_eq(str(cfg.get_value(o, "gradle_build/target_sdk", "")), "35", "target SDK 35")
	check_eq(cfg.get_value(o, "architectures/arm64-v8a", false), true, "arm64-v8a on")
	for abi in ["armeabi-v7a", "x86", "x86_64"]:
		check_eq(cfg.get_value(o, "architectures/" + abi, true), false, "%s off" % abi)
	var perms: PackedStringArray = cfg.get_value(o, "permissions/custom_permissions", PackedStringArray())
	check(perms.is_empty(), "no custom permissions")
	for key in cfg.get_section_keys(o):
		if key.begins_with("permissions/") and key != "permissions/custom_permissions":
			check_eq(cfg.get_value(o, key), false, "permission %s off" % key)
	for key in ["keystore/release", "keystore/release_password"]:
		check(str(cfg.get_value(o, key, "")).is_empty(), "no release signing (%s)" % key)


func test_mobile_project_settings() -> void:
	check_eq(bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)), false, "Back never quits")
	var o := int(ProjectSettings.get_setting("display/window/handheld/orientation"))
	check([0, 2, 4].has(o), "landscape family (%d)" % o)
	check_eq(bool(ProjectSettings.get_setting(InputMode.SETTING, true)), false, "force_touch_controls off by default")
	check_eq(InputMode.is_forced(), false, "touch not forced in this run")


func test_input_mode_selection() -> void:
	check_eq(InputMode.wants_touch(true), true, "forced → touch")
	check_eq(InputMode.wants_touch(false), OS.has_feature("mobile"), "not forced → touch only on mobile")


func test_graphics_profiles_load() -> void:
	var names := ["low", "medium", "high"]
	var prev_shadow := -1.0
	for i in names.size():
		var p := load("res://resources/platform/graphics_%s.tres" % names[i]) as GraphicsProfile
		check(p != null, "%s profile loads" % names[i])
		if p == null:
			continue
		check_eq(int(p.tier), i, "%s tier index" % names[i])
		check(p.render_scale >= 0.5 and p.render_scale <= 1.0, "%s render scale sane" % names[i])
		var shadow := p.shadow_max_distance if p.sun_shadows else 0.0
		check(shadow >= prev_shadow, "%s shadows not cheaper than lower tier" % names[i])
		prev_shadow = shadow
	var low := load("res://resources/platform/graphics_low.tres") as GraphicsProfile
	check(not low.sun_shadows and low.max_fps == 30, "LOW: no shadows, 30 FPS cap")


func _ride(kmh: float, seconds: float) -> RideTelemetry:
	var t := RideTelemetry.new()
	t.add_time_at(kmh, seconds)
	return t


func test_mood_is_qualitative_and_responds() -> void:
	var M := PassengerMood.Mood
	check_eq(PassengerMood.KEYS.size(), M.size(), "one key per mood")
	for k in PassengerMood.KEYS:
		check(String(k).begins_with("MOOD_"), "mood key %s" % k)
	# Brisk, clean ride, half way: rushed passenger is happy.
	var ok := _ride(_rushed.expected_speed_kmh * 1.1, 20.0)
	check_eq(PassengerMood.evaluate(ok, _rushed, 600.0, 300.0, _config), M.HAPPY, "brisk clean ride → HAPPY")
	# Crawling with most of the route left: rushed passenger is impatient.
	var slow := _ride(_rushed.expected_speed_kmh * 0.35, 40.0)
	var slow_mood := PassengerMood.evaluate(slow, _rushed, 600.0, 520.0, _config)
	check(slow_mood == M.IMPATIENT or slow_mood == M.UPSET, "slow ride → IMPATIENT/UPSET (%s)" % PassengerMood.KEYS[slow_mood])
	# Wild driving scares the careful passenger.
	var wild := _ride(55.0, 30.0)
	wild.two_wheel_events = 3
	wild.two_wheel_seconds = 2.5
	wild.extreme_roll_seconds = 3.0
	wild.close_calls = 4
	wild.hard_brakes = 3
	var wild_mood := PassengerMood.evaluate(wild, _careful, 600.0, 200.0, _config)
	check(wild_mood == M.NERVOUS or wild_mood == M.UPSET, "wild ride, careful passenger → NERVOUS/UPSET (%s)" % PassengerMood.KEYS[wild_mood])
	# The same wild driving thrills the thrill seeker.
	var thrill_mood := PassengerMood.evaluate(wild, _thrill, 600.0, 200.0, _config)
	check(thrill_mood == M.EXCITED or thrill_mood == M.HAPPY, "wild ride, thrill seeker → EXCITED/HAPPY (%s)" % PassengerMood.KEYS[thrill_mood])
	# Pedestrian danger always upsets.
	var danger := _ride(30.0, 20.0)
	danger.pedestrian_danger = 1
	check_eq(PassengerMood.evaluate(danger, _thrill, 600.0, 300.0, _config), M.UPSET, "pedestrian danger → UPSET")
