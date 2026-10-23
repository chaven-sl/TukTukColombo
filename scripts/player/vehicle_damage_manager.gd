class_name VehicleDamageManager
extends Node
## Crash consequences for the player tuk (v0.03A2). Listens to
## EventBus.collision_event (WORLD hits only; the body is classified by
## WorldSurface), drives VehicleDamageState, and applies the result in the
## INPUT layer (throttle cut / limp scale, engine off when DISABLED) — the
## approved vehicle physics are not touched.
##
## DISABLED → the tuk comes to rest → ~2 s recovery presentation → road
## reset via WorldRecoveryManager → HEALTHY (+ short grace, no reset loops).
## An active ride fails (RideManager listens to vehicle_damage_changed).

@export var config: VehicleDamageConfig

var player: TukController
var recovery: WorldRecoveryManager
var state: VehicleDamageState
var last_tier: VehicleDamageState.Tier = VehicleDamageState.Tier.NONE
var disabled_time := 0.0

# Diagnostics.
var stats_light := 0
var stats_hard := 0
var stats_disabling := 0
var stats_resets := 0

var _effects: CrashEffects


func _ready() -> void:
	# After the input sources (-10), before the vehicle (0).
	process_physics_priority = -5
	if config == null:
		config = VehicleDamageConfig.new()
	state = VehicleDamageState.new(config)


func setup(p_player: TukController, p_recovery: WorldRecoveryManager, p_effects: CrashEffects) -> void:
	player = p_player
	recovery = p_recovery
	_effects = p_effects
	EventBus.collision_event.connect(on_collision)
	player.was_reset.connect(_on_reset)  # any reset/teleport: back to HEALTHY


func on_collision(event: CollisionEvent) -> void:
	var tier := VehicleDamageState.tier_for(event, config)
	if tier == VehicleDamageState.Tier.NONE:
		return
	last_tier = tier
	match tier:
		VehicleDamageState.Tier.LIGHT:
			stats_light += 1
		VehicleDamageState.Tier.HARD:
			stats_hard += 1
		VehicleDamageState.Tier.DISABLING:
			stats_disabling += 1
	EventBus.world_impact.emit(int(tier), event.position, int(WorldSurface.of_body(event.other_body)))
	if _effects != null:
		_effects.impact(tier, event.position, event.impulse_direction)
	if state.on_impact(tier):
		if state.state == VehicleDamageState.State.DISABLED:
			disabled_time = 0.0
		EventBus.vehicle_damage_changed.emit(int(state.state))
		if _effects != null:
			_effects.set_smoke(player, state.state != VehicleDamageState.State.HEALTHY)


func _physics_process(delta: float) -> void:
	var ps := PerfSections.begin()
	_physics_process_body(delta)
	PerfSections.end(PerfSections.DAMAGE_RECOVERY, ps)


func _physics_process_body(delta: float) -> void:
	if player == null:
		return
	if state.tick(delta):
		EventBus.vehicle_damage_changed.emit(int(state.state))
		if _effects != null:
			_effects.set_smoke(player, false)
	var input := player.input
	input.throttle *= state.throttle_scale()
	if state.state == VehicleDamageState.State.DISABLED:
		input.throttle = 0.0
		input.steer = 0.0
		input.brake = 0.0
		input.handbrake = true
		disabled_time += delta
		if disabled_time >= config.recovery_delay and (player.speed_kmh < 3.0 or disabled_time > config.recovery_delay + 2.0):
			stats_resets += 1
			disabled_time = -1000.0  # one reset per disable
			recovery.recover("disabled")


func _on_reset() -> void:
	var was := state.state
	state.recovered()
	if _effects != null:
		_effects.set_smoke(player, false)
	if was != VehicleDamageState.State.HEALTHY:
		EventBus.vehicle_damage_changed.emit(int(state.state))


func state_name() -> String:
	return VehicleDamageState.State.keys()[state.state]
