class_name RideTelemetry
extends RefCounted
## Aggregate statistics for one passenger ride. Only running totals are kept —
## no per-frame history. Fed by RideManager (sample() each physics tick plus
## event callbacks). Speeds are stored in km/h. The data is profile-neutral:
## the same telemetry can be scored for any passenger.

const BUCKET_KMH := 5.0
const BUCKETS := 20

var elapsed := 0.0
var distance_m := 0.0
var max_speed_kmh := 0.0
## Seconds spent in each 5 km/h speed band (last band = 95+ km/h).
var speed_histogram := PackedFloat32Array()
var collisions := 0
var major_collisions := 0
var close_calls := 0
var tight_gaps := 0
var combo_peak := 0
var two_wheel_events := 0
var two_wheel_seconds := 0.0
var extreme_roll_seconds := 0.0
var rollovers := 0
var hard_brakes := 0
var pedestrian_danger := 0
var pedestrian_impacts := 0

var _was_two_wheel := false
var _was_hard_braking := false


func _init() -> void:
	speed_histogram.resize(BUCKETS)
	speed_histogram.fill(0.0)


## Seconds spent above a speed (km/h), from the histogram (band-linear).
func seconds_above(kmh: float) -> float:
	var total := 0.0
	for i in BUCKETS:
		var lo := i * BUCKET_KMH
		var hi := lo + BUCKET_KMH
		if lo >= kmh:
			total += speed_histogram[i]
		elif hi > kmh:
			total += speed_histogram[i] * (hi - kmh) / BUCKET_KMH
	return total


## Test/tool helper: add time at a constant speed.
func add_time_at(kmh: float, seconds: float) -> void:
	elapsed += seconds
	distance_m += kmh / 3.6 * seconds
	max_speed_kmh = maxf(max_speed_kmh, kmh)
	speed_histogram[mini(int(kmh / BUCKET_KMH), BUCKETS - 1)] += seconds


func average_speed_kmh() -> float:
	if elapsed <= 0.0:
		return 0.0
	return distance_m / elapsed * 3.6


## Per-tick sample of the vehicle. `two_wheel` and `rolled_deg` come from the
## tuk's roll telemetry; `longitudinal_g` is negative when braking.
func sample(delta: float, speed_kmh: float, two_wheel: bool, roll_deg: float, longitudinal_g: float,
		config: RideConfig) -> void:
	add_time_at(speed_kmh, delta)
	if two_wheel:
		two_wheel_seconds += delta
		if not _was_two_wheel:
			two_wheel_events += 1
	_was_two_wheel = two_wheel
	if absf(roll_deg) > config.extreme_roll_deg:
		extreme_roll_seconds += delta
	var braking_hard := longitudinal_g < -config.hard_brake_g
	if braking_hard and not _was_hard_braking:
		hard_brakes += 1
	_was_hard_braking = braking_hard


func record_collision(major: bool) -> void:
	collisions += 1
	if major:
		major_collisions += 1


func record_skill(event_type: int, chain: int) -> void:
	if event_type == SkillEvent.Type.TIGHT_GAP:
		tight_gaps += 1
	else:
		close_calls += 1
	combo_peak = maxi(combo_peak, chain)


func to_dictionary() -> Dictionary:
	return {
		"elapsed_s": snappedf(elapsed, 0.1), "distance_m": snappedf(distance_m, 1.0),
		"average_kmh": snappedf(average_speed_kmh(), 0.1), "max_kmh": snappedf(max_speed_kmh, 0.1),
		"collisions": collisions, "major_collisions": major_collisions, "close_calls": close_calls,
		"tight_gaps": tight_gaps, "combo_peak": combo_peak, "two_wheel_events": two_wheel_events,
		"two_wheel_s": snappedf(two_wheel_seconds, 0.01), "rollovers": rollovers,
		"hard_brakes": hard_brakes, "pedestrian_danger": pedestrian_danger,
		"pedestrian_impacts": pedestrian_impacts,
	}
