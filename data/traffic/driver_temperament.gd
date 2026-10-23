class_name DriverTemperament
extends Resource
## How a traffic driver responds to being hit by the player (v0.03A1).
## Collision severity always dominates; temperament only shifts the odds,
## the argument length and the intensity. PROTOTYPE BASELINE.

@export var id: StringName = &""
## Relative chance of a driver having this temperament.
@export var weight := 1.0
## LIGHT contact: chance of an angry horn (otherwise a shout only).
@export_range(0.0, 1.0) var horn_chance := 0.6
## LIGHT contact: chance to escalate to stopping and yelling (no exit).
@export_range(0.0, 1.0) var escalate_light_chance := 0.0
## MODERATE collision: chance the driver gets out.
@export_range(0.0, 1.0) var exit_chance_moderate := 0.3
## MAJOR collision: chance the driver gets out (raised to the config floor).
@export_range(0.0, 1.0) var exit_chance_major := 0.9
## Argument duration range (s) before walking back.
@export var argue_seconds := Vector2(2.0, 3.0)
## 0–1: how often they shout during an argument and how insistently they horn.
@export_range(0.0, 1.0) var intensity := 0.4
## Lines (translation keys) shouted while arguing. Sri Lankan English
## placeholders now; colloquial Sinhala/Tamil + VO in the audio sprint.
@export var argue_keys: PackedStringArray = ["DRIVER_ARGUE_LOOK", "DRIVER_ARGUE_WHO_TAUGHT"]
