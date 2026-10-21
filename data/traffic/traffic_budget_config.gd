class_name TrafficBudgetConfig
extends Resource
## AdaptiveTrafficBudget thresholds. Hysteresis is deliberate: dropping is
## quicker than recovering and both need sustained evidence.

@export var min_ceiling := 8
@export var max_ceiling := 20
## Ceiling at startup (normally the gameplay density target).
@export var initial_ceiling := 14

@export var low_fps_threshold := 27.0
@export var high_fps_threshold := 50.0
## Seconds below low_fps_threshold before stepping down.
@export var low_sustain_seconds := 3.0
## Seconds above high_fps_threshold before stepping up.
@export var high_sustain_seconds := 10.0
@export var step_down := 2
@export var step_up := 1
## Minimum seconds between two ceiling changes.
@export var change_cooldown := 4.0
## FPS is averaged over windows of this length (s).
@export var sample_window := 0.5
