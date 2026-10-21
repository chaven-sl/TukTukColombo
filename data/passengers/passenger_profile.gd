class_name PassengerProfile
extends Resource
## Data-only passenger personality. STUB: nothing in v0.01 reads these at
## runtime. They exist to prove the passenger layer will be data-driven:
## Player Tuk -> Passenger Profile -> Fare/Mission -> Traffic Skill ->
## Satisfaction -> Reward -> Progression.

@export var id: StringName = &""
## Translation key for the profile name (e.g. PASSENGER_RUSHED_NAME).
@export var display_name_key := ""

@export_group("Satisfaction weights")
## Relative importance of arriving quickly / safely / smoothly. 0..1 each.
@export_range(0.0, 1.0) var time_weight := 0.34
@export_range(0.0, 1.0) var safety_weight := 0.33
@export_range(0.0, 1.0) var comfort_weight := 0.33

@export_group("Risk")
## 0 = hates any risk, 1 = loves it.
@export_range(0.0, 1.0) var risk_tolerance := 0.5
## Scales satisfaction loss from collisions.
@export var collision_penalty_multiplier := 1.0
## -1 = close calls upset them, +1 = close calls delight them.
@export_range(-1.0, 1.0) var close_call_preference := 0.0

@export_group("Speed")
@export var speed_preference_kmh := 40.0
## Comfortable band around the preferred speed.
@export var speed_tolerance_kmh := 10.0


## Returns a list of human-readable problems (empty when valid).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id is empty")
	if display_name_key.is_empty():
		problems.append("display_name_key is empty")
	var weight_sum := time_weight + safety_weight + comfort_weight
	if weight_sum <= 0.0:
		problems.append("satisfaction weights sum to zero")
	if collision_penalty_multiplier < 0.0:
		problems.append("collision_penalty_multiplier is negative")
	if speed_preference_kmh <= 0.0 or speed_tolerance_kmh <= 0.0:
		problems.append("speed preference/tolerance must be positive")
	return problems


## Weights rescaled to sum to 1 (for future satisfaction maths).
func normalised_weights() -> Vector3:
	var total := time_weight + safety_weight + comfort_weight
	if total <= 0.0:
		return Vector3(1.0, 1.0, 1.0) / 3.0
	return Vector3(time_weight, safety_weight, comfort_weight) / total
