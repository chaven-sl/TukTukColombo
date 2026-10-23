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


# --- v0.03A1 traffic incidents (audio/presentation hooks; never a reward) ---
## A traffic collision reaction began. `tier` is IncidentRules.Tier.
signal traffic_incident_started(tier: int, world_position: Vector3)
## The incident is over and the traffic vehicle is moving again.
signal traffic_incident_resolved(tier: int)
## A traffic horn. `pattern` is TrafficIncidentManager.Horn (ANGRY, REPEATED, NEARBY).
signal traffic_horn(world_position: Vector3, pattern: int)
## A driver shouted a line (translation key) — bubble now, voice later.
signal driver_shout(world_position: Vector3, line_key: String)

# --- v0.03A2 world consequences (presentation/audio hooks; never a reward) ---
## A world impact was classified. `tier` is VehicleDamageState.Tier, `surface` WorldSurface.Type.
signal world_impact(tier: int, world_position: Vector3, surface: int)
## VehicleDamageState changed (HEALTHY / DAMAGED / DISABLED).
signal vehicle_damage_changed(state: int)
## WorldRecoveryManager placed the tuk back on the road. `reason` e.g. "disabled", "void".
signal vehicle_recovered(reason: String)
## An ImpactProp was knocked (light street clutter).
signal prop_knocked(world_position: Vector3, kind: int)
