class_name PassengerReactionSystem
extends RefCounted
## Chooses short passenger lines (translation keys) from ride events and
## state, using the profile's preferences — not per-passenger scripts.
## Rate limited by a global cooldown, a per-key cooldown and priorities so the
## passenger comments now and then rather than every second.

const PRIORITY := {
	"REACT_PEDESTRIAN_DANGER": 100, "REACT_COLLISION": 90, "REACT_TWO_WHEEL_NEG": 70,
	"REACT_TWO_WHEEL_POS": 60, "REACT_TIGHT_GAP_POS": 55, "REACT_TIGHT_GAP_NEG": 55,
	"REACT_CLOSE_CALL_POS": 50, "REACT_CLOSE_CALL_NEG": 50, "REACT_TOO_FAST": 40,
	"REACT_HURRY_UP": 35, "REACT_GOOD_SPEED": 20,
}

var profile: PassengerProfile
var config: RideConfig
var _global_cooldown := 0.0
var _key_cooldowns: Dictionary = {}
var _slow_time := 0.0
var _fast_time := 0.0
var _good_time := 0.0
var _pending := ""


func _init(p_profile: PassengerProfile, p_config: RideConfig) -> void:
	profile = p_profile
	config = p_config


## Event hooks. They queue a candidate; tick() decides whether to say it.
func on_skill(event_type: int) -> void:
	var pref := profile.close_call_preference
	if event_type == SkillEvent.Type.TIGHT_GAP:
		if pref > 0.3:
			_offer("REACT_TIGHT_GAP_POS")
		elif pref < -0.3:
			_offer("REACT_TIGHT_GAP_NEG")
	else:
		if pref > 0.3:
			_offer("REACT_CLOSE_CALL_POS")
		elif pref < -0.3:
			_offer("REACT_CLOSE_CALL_NEG")


func on_collision() -> void:
	_offer("REACT_COLLISION")


func on_two_wheel() -> void:
	if profile.two_wheel_preference > 0.3:
		_offer("REACT_TWO_WHEEL_POS")
	elif profile.two_wheel_preference < 0.0:
		_offer("REACT_TWO_WHEEL_NEG")


## Every profile reacts negatively to pedestrian danger.
func on_pedestrian_danger() -> void:
	_offer("REACT_PEDESTRIAN_DANGER")


## Call every physics tick during an active ride. Returns a key to show or "".
func tick(delta: float, speed_kmh: float, ride_elapsed: float) -> String:
	_global_cooldown = maxf(_global_cooldown - delta, 0.0)
	for key in _key_cooldowns.keys():
		_key_cooldowns[key] = maxf(float(_key_cooldowns[key]) - delta, 0.0)
	_update_speed_moods(delta, speed_kmh, ride_elapsed)
	if _pending.is_empty() or _global_cooldown > 0.0:
		return ""
	var key := _pending
	_pending = ""
	if float(_key_cooldowns.get(key, 0.0)) > 0.0:
		return ""
	_global_cooldown = config.reaction_global_cooldown
	_key_cooldowns[key] = config.reaction_key_cooldown
	return key


func arrival_key(final_score: float) -> String:
	return "REACT_ARRIVAL_SUCCESS" if final_score >= 60.0 else "REACT_ARRIVAL_POOR"


func _update_speed_moods(delta: float, speed_kmh: float, ride_elapsed: float) -> void:
	var too_fast := profile.speed_preference_kmh + profile.speed_tolerance_kmh
	var time_focused := profile.time_weight >= profile.safety_weight and profile.time_weight >= profile.comfort_weight
	_slow_time = _slow_time + delta if speed_kmh < config.hurry_speed_kmh and ride_elapsed > 4.0 else 0.0
	_fast_time = _fast_time + delta if speed_kmh > too_fast else 0.0
	_good_time = _good_time + delta if speed_kmh >= profile.speed_preference_kmh - profile.speed_tolerance_kmh * 0.5 else 0.0
	if time_focused and _slow_time > config.hurry_after_seconds:
		_offer("REACT_HURRY_UP")
		_slow_time = 0.0
	if _fast_time > 2.0 and profile.safety_weight > profile.time_weight:
		_offer("REACT_TOO_FAST")
		_fast_time = 0.0
	if time_focused and _good_time > 6.0:
		_offer("REACT_GOOD_SPEED")
		_good_time = 0.0


func _offer(key: String) -> void:
	if _pending.is_empty() or int(PRIORITY.get(key, 0)) > int(PRIORITY.get(_pending, 0)):
		_pending = key
