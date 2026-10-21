class_name PassengerProfile
extends Resource
## Data-only passenger personality. PassengerSatisfaction combines the shared
## subscores (time, safety, comfort, excitement) using these weights and
## preferences — there is no per-passenger scoring code.
## Player Tuk -> Passenger Profile -> Fare/Mission -> Traffic Skill ->
## Satisfaction -> Reward -> Progression.
##
## Schema is backward-safe: fields added in v0.02 default to neutral values,
## so v0.01 profile resources still load, validate and normalise.

@export var id: StringName = &""
## Translation key for the profile name (e.g. PASSENGER_RUSHED_NAME).
@export var display_name_key := ""
## Translation key for the one-word priority shown on the offer card.
@export var priority_key := ""
## Marker colour above the waiting passenger (presentation only).
@export var marker_color := Color(1.0, 0.85, 0.2)

@export_group("Satisfaction weights")
## Relative importance of arriving quickly / safely / smoothly / excitingly.
## Any non-negative values; they are normalised to sum to 1.
@export_range(0.0, 1.0) var time_weight := 0.34
@export_range(0.0, 1.0) var safety_weight := 0.33
@export_range(0.0, 1.0) var comfort_weight := 0.33
## v0.02. 0 = indifferent to excitement (v0.01 default).
@export_range(0.0, 1.0) var excitement_weight := 0.0

@export_group("Risk")
## 0 = every vehicle near-miss feels like danger, 1 = vehicle risk is fun.
## Never applies to pedestrians.
@export_range(0.0, 1.0) var risk_tolerance := 0.5
## Scales satisfaction loss from collisions.
@export var collision_penalty_multiplier := 1.0
## -1 = close calls / tight gaps upset them, +1 = close calls delight them.
@export_range(-1.0, 1.0) var close_call_preference := 0.0
## v0.02. -1 = two-wheel moments terrify them, +1 = controlled two-wheel
## vehicle moments are thrilling.
@export_range(-1.0, 1.0) var two_wheel_preference := 0.0
## v0.02. Multiplies the (always negative) pedestrian-danger penalty.
## Must be positive for every profile: nobody enjoys endangering people.
@export var pedestrian_danger_sensitivity := 1.0

@export_group("Speed")
@export var speed_preference_kmh := 40.0
## Comfortable band around the preferred speed.
@export var speed_tolerance_kmh := 10.0
## v0.02. Average journey speed this passenger considers "on time".
@export var expected_speed_kmh := 30.0


## Returns a list of human-readable problems (empty when valid).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id is empty")
	if display_name_key.is_empty():
		problems.append("display_name_key is empty")
	var weight_sum := time_weight + safety_weight + comfort_weight + excitement_weight
	if weight_sum <= 0.0:
		problems.append("satisfaction weights sum to zero")
	if excitement_weight < 0.0:
		problems.append("excitement_weight is negative")
	if collision_penalty_multiplier < 0.0:
		problems.append("collision_penalty_multiplier is negative")
	if pedestrian_danger_sensitivity <= 0.0:
		problems.append("pedestrian_danger_sensitivity must be positive (pedestrian danger is never rewarded)")
	if speed_preference_kmh <= 0.0 or speed_tolerance_kmh <= 0.0 or expected_speed_kmh <= 0.0:
		problems.append("speed preference/tolerance/expected speed must be positive")
	return problems


## Weights rescaled to sum to 1: (time, safety, comfort, excitement).
func normalised_weights() -> Vector4:
	var total := time_weight + safety_weight + comfort_weight + excitement_weight
	if total <= 0.0:
		return Vector4(1.0, 1.0, 1.0, 0.0) / 3.0
	return Vector4(time_weight, safety_weight, comfort_weight, excitement_weight) / total
