class_name TouchControlsConfig
extends Resource
## Touch control mapping and layout tunables. PROTOTYPE BASELINE v0.03A.
## Layout sizes are in logical UI units (the viewport is 720 units tall at any
## device resolution because of canvas_items/expand stretching).
## Vehicle physics are NOT tuned here — only how a thumb becomes −1…+1.

@export_group("Steering mapping")
## Fraction of the pad half-width around the centre that outputs 0.
@export_range(0.0, 0.5) var steer_dead_zone := 0.08
## 1.0 = linear. Slightly above 1 softens the centre for fine corrections
## without delaying full lock (kept mild: rapid countersteer matters).
@export_range(1.0, 2.0) var steer_exponent := 1.15
## Thumb travel (as a fraction of the pad half-width) that gives full lock.
@export_range(0.3, 1.0) var full_lock_fraction := 0.85

@export_group("Layout (logical units)")
@export var edge_padding := 24.0
## Steering pad visual width as a fraction of the viewport width (clamped).
@export var steer_pad_width_fraction := 0.24
@export var steer_pad_min_width := 300.0
@export var steer_pad_max_width := 440.0
@export var steer_pad_height := 150.0
## Extra invisible touch margin around the steering pad.
@export var steer_hit_margin := 60.0
@export var accelerator_size := Vector2(150, 200)
@export var brake_size := Vector2(140, 150)
@export var horn_size := Vector2(96, 76)
@export var pause_size := Vector2(72, 64)
@export var accept_size := Vector2(300, 96)
@export var control_gap := 18.0

@export_group("Look")
@export_range(0.0, 1.0) var idle_opacity := 0.5
@export_range(0.0, 1.0) var pressed_opacity := 0.78
