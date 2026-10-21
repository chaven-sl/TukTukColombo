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

# --- v0.02 human world and rides ---
## Player drove dangerously near a pedestrian. NEVER a reward: no score, combo,
## fare or passenger excitement may ever be granted from this event.
signal pedestrian_danger(event: PedestrianEvent)
## Player made significant contact with a pedestrian (non-graphic handling).
signal pedestrian_impact(event: PedestrianEvent)
## RideManager lifecycle changed.
signal ride_state_changed(state: int)
## A ride ended (completed or failed) with its evaluated result.
signal ride_finished(result: RideResult)
## The current passenger reacted (translation key of the line).
signal passenger_reaction(reaction_key: String, profile_id: StringName)

