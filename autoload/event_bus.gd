extends Node
## Global gameplay event channel.
##
## Only meaningful cross-system gameplay events live here. Systems that talk to
## a direct neighbour (player -> camera, detector internals, UI widgets) keep
## using local signals instead of routing through this bus.

## A detected driving skill (close call, tight gap). Emitted by NearMissDetector.
signal skill_event(event: SkillEvent)
## Player contact with traffic or the world. Emitted by TukController.
signal collision_event(event: CollisionEvent)
## Points awarded after combo maths. Emitted by ScoringSystem; consumed by UI.
signal score_awarded(event_type: int, points: int, multiplier: int, total_score: int)
## Combo chain/multiplier changed, including the reset to zero.
signal combo_changed(chain: int, multiplier: int)
## AdaptiveTrafficBudget changed its performance ceiling.
signal performance_budget_changed(performance_ceiling: int, actual_target: int)
## Player vehicle was reset or auto-recovered.
signal player_reset()
## Horn placeholder. Future: traffic reactions, passenger mood, audio.
signal horn_sounded(world_position: Vector3)
