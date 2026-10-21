extends "res://tests/test_case.gd"

const PATHS := [
	"res://resources/passengers/rushed.tres",
	"res://resources/passengers/careful.tres",
	"res://resources/passengers/thrill_seeker.tres",
]


func test_profiles_load_and_validate() -> void:
	var ids := {}
	for path in PATHS:
		var profile := load(path) as PassengerProfile
		check(profile != null, "%s loads as PassengerProfile" % path)
		if profile == null:
			continue
		check(profile.validate().is_empty(), "%s valid: %s" % [path, profile.validate()])
		check(not ids.has(profile.id), "id %s unique" % profile.id)
		ids[profile.id] = true
		var w := profile.normalised_weights()
		check_near(w.x + w.y + w.z + w.w, 1.0, 0.0001, "%s weights normalise" % path)


func test_profiles_are_meaningfully_different() -> void:
	var rushed := load(PATHS[0]) as PassengerProfile
	var careful := load(PATHS[1]) as PassengerProfile
	var thrill := load(PATHS[2]) as PassengerProfile
	check(rushed.time_weight > careful.time_weight, "rushed values time more than careful")
	check(careful.safety_weight > thrill.safety_weight, "careful values safety more than thrill seeker")
	check(thrill.close_call_preference > 0.5 and careful.close_call_preference < 0.0, "close-call preference sign")
	check(careful.collision_penalty_multiplier > rushed.collision_penalty_multiplier, "careful punishes collisions more")


func test_display_names_are_translation_keys() -> void:
	for path in PATHS:
		var profile := load(path) as PassengerProfile
		check(profile.display_name_key.begins_with("PASSENGER_"), "%s uses a translation key" % path)


func test_invalid_profile_reports_problems() -> void:
	var p := PassengerProfile.new()
	p.time_weight = 0.0
	p.safety_weight = 0.0
	p.comfort_weight = 0.0
	check(p.validate().size() >= 3, "empty id, key and zero weights all reported")
