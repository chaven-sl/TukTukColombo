class_name VehicleDamageState
extends RefCounted
## Pure crash-consequence state (v0.03A2), unit tested:
##
##   HEALTHY ──HARD──▶ DAMAGED (engine cut briefly, then limp) ──timer──▶ HEALTHY
##      │                 │
##      └──DISABLING──▶ DISABLED ◀──HARD while DAMAGED
##                         └── recovery (road reset) ──▶ HEALTHY
##
## Only solid world structures (BUILDING / WALL / PROP) damage the tuk.
## Kerbs, forecourt and traffic never do (traffic has its own incident system).

enum State { HEALTHY, DAMAGED, DISABLED }
enum Tier { NONE, LIGHT, HARD, DISABLING }

var config: VehicleDamageConfig
var state: State = State.HEALTHY
var immobilised_left := 0.0
var limp_left := 0.0
var grace_left := 0.0


func _init(p_config: VehicleDamageConfig = null) -> void:
	config = p_config if p_config != null else VehicleDamageConfig.new()


static func tier_for(event: CollisionEvent, cfg: VehicleDamageConfig) -> Tier:
	if event == null or event.kind != CollisionEvent.Kind.WORLD:
		return Tier.NONE
	if not WorldSurface.is_solid_structure(WorldSurface.of_body(event.other_body)):
		return Tier.NONE
	var kmh := event.impact_speed_kmh()
	if kmh >= cfg.disabling_min_kmh:
		return Tier.DISABLING
	if kmh >= cfg.hard_min_kmh:
		return Tier.HARD
	return Tier.LIGHT


## Applies an impact; returns true if the state changed.
func on_impact(tier: Tier) -> bool:
	if grace_left > 0.0 or state == State.DISABLED:
		return false
	match tier:
		Tier.DISABLING:
			state = State.DISABLED
			return true
		Tier.HARD:
			if state == State.DAMAGED:
				state = State.DISABLED
			else:
				state = State.DAMAGED
				immobilised_left = config.immobilised_seconds
				limp_left = config.limp_seconds
			return true
	return false


## Advances timers; returns true if the state changed (DAMAGED → HEALTHY).
func tick(delta: float) -> bool:
	grace_left = maxf(grace_left - delta, 0.0)
	if state != State.DAMAGED:
		return false
	immobilised_left = maxf(immobilised_left - delta, 0.0)
	limp_left -= delta
	if limp_left <= 0.0:
		state = State.HEALTHY
		return true
	return false


## Multiplier applied to the driver's throttle input (input layer only —
## vehicle physics are untouched).
func throttle_scale() -> float:
	match state:
		State.DISABLED:
			return 0.0
		State.DAMAGED:
			return 0.0 if immobilised_left > 0.0 else config.limp_throttle
	return 1.0


func recovered() -> void:
	state = State.HEALTHY
	immobilised_left = 0.0
	limp_left = 0.0
	grace_left = config.post_reset_grace
