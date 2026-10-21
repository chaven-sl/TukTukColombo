class_name ScoringSystem
extends Node
## Consumes skill and collision events, applies combo rules, records score in
## GameState and announces awards. Detection lives in NearMissDetector and
## presentation in the HUD; this node only decides value.

signal combo_lost(reason: int)

enum LossReason { TIMEOUT, COLLISION, PEDESTRIAN }

@export var config: ScoringConfig

var combo: ComboManager


func _ready() -> void:
	if config == null:
		config = ScoringConfig.new()
	combo = ComboManager.new(config.max_multiplier, config.combo_timeout)
	EventBus.skill_event.connect(_on_skill_event)
	EventBus.collision_event.connect(_on_collision_event)
	# Pedestrian incidents can only ever cost the player: an impact resets the
	# combo. PEDESTRIAN_DANGER is deliberately not connected — it must never
	# touch score or combo in either direction.
	EventBus.pedestrian_impact.connect(_on_pedestrian_impact)


func _physics_process(delta: float) -> void:
	if combo.update(delta):
		EventBus.combo_changed.emit(0, 1)
		combo_lost.emit(LossReason.TIMEOUT)


func _on_skill_event(event: SkillEvent) -> void:
	var points := combo.register_event(config.points_for(event.type))
	GameState.add_score(points)
	GameState.record_skill(event.type)
	GameState.record_chain(combo.chain)
	EventBus.combo_changed.emit(combo.chain, combo.multiplier())
	EventBus.score_awarded.emit(event.type, points, combo.multiplier(), GameState.score)


func _on_collision_event(event: CollisionEvent) -> void:
	if int(event.severity) < config.combo_reset_min_severity:
		return
	if combo.reset():
		EventBus.combo_changed.emit(0, 1)
		combo_lost.emit(LossReason.COLLISION)


func _on_pedestrian_impact(_event: PedestrianEvent) -> void:
	combo.reset()
	EventBus.combo_changed.emit(0, 1)
	combo_lost.emit(LossReason.PEDESTRIAN)

