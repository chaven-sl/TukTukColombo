class_name RideManager
extends Node
## The passenger ride lifecycle as an explicit, validated state machine:
##
##   NO_RIDE → OFFER_SELECTED → EN_ROUTE_TO_PICKUP → BOARDING → ACTIVE
##   ACTIVE → ARRIVED → COMPLETED → EXITING → RETURN_TO_IDLE → NO_RIDE
##   ACTIVE → FAILED → EXITING …
##
## Failure rules (v0.02): PEDESTRIAN_IMPACT always fails an active ride; a
## confirmed rollover (ROLLOVER collision event) fails it when
## RideConfig.fail_on_rollover. Minor/major collisions never fail a ride —
## they only lower satisfaction.
##
## Input: request_accept() is called by the "interact" action here, and can
## be called by a future touch button without changes.

signal state_changed(state: RideState)
signal reaction(reaction_key: String)
signal result_ready(result: RideResult)

enum RideState {
	NO_RIDE, OFFER_SELECTED, EN_ROUTE_TO_PICKUP, BOARDING, ACTIVE, ARRIVED, COMPLETED, FAILED, EXITING, RETURN_TO_IDLE,
}

const TRANSITIONS := {
	RideState.NO_RIDE: [RideState.OFFER_SELECTED],
	RideState.OFFER_SELECTED: [RideState.EN_ROUTE_TO_PICKUP, RideState.NO_RIDE],
	RideState.EN_ROUTE_TO_PICKUP: [RideState.BOARDING, RideState.NO_RIDE],
	RideState.BOARDING: [RideState.ACTIVE, RideState.EN_ROUTE_TO_PICKUP, RideState.NO_RIDE],
	RideState.ACTIVE: [RideState.ARRIVED, RideState.FAILED],
	RideState.ARRIVED: [RideState.COMPLETED],
	RideState.COMPLETED: [RideState.EXITING],
	RideState.FAILED: [RideState.EXITING],
	RideState.EXITING: [RideState.RETURN_TO_IDLE],
	RideState.RETURN_TO_IDLE: [RideState.NO_RIDE],
}

@export var config: RideConfig

var player: TukController
var offers: PassengerOfferManager
var humans: HumanManager
var road: RoadNetwork
var scoring: ScoringSystem

var state: RideState = RideState.NO_RIDE
var offer: PassengerOffer = null
var nearby_offer: PassengerOffer = null
var telemetry: RideTelemetry = null
var reactions: PassengerReactionSystem = null
var last_result: RideResult = null
var remaining_m := 0.0
var invalid_transitions := 0
var current_reaction_key := ""
var current_reaction_time := 0.0

var _remaining_timer := 0.0
var _seat: Node3D
var _boarding_point: Node3D


func setup(p_player: TukController, p_offers: PassengerOfferManager, p_humans: HumanManager,
		p_road: RoadNetwork, p_scoring: ScoringSystem) -> void:
	player = p_player
	offers = p_offers
	humans = p_humans
	road = p_road
	scoring = p_scoring
	if config == null:
		config = RideConfig.new()
	_seat = player.get_node_or_null("SeatMarker")
	_boarding_point = player.get_node_or_null("BoardingPoint")
	EventBus.skill_event.connect(_on_skill)
	EventBus.collision_event.connect(_on_collision)
	EventBus.pedestrian_danger.connect(_on_pedestrian_danger)
	EventBus.pedestrian_impact.connect(_on_pedestrian_impact)
	player.roll_state_changed.connect(_on_roll_state)


func set_state(to: RideState) -> bool:
	if to == state:
		return true
	var allowed: Array = TRANSITIONS.get(state, [])
	if not allowed.has(to):
		invalid_transitions += 1
		push_warning("[RideManager] invalid transition %s -> %s" % [RideState.keys()[state], RideState.keys()[to]])
		return false
	state = to
	state_changed.emit(to)
	EventBus.ride_state_changed.emit(int(to))
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		request_accept()


## Accepts the nearby offer (or dismisses a finished result).
func request_accept() -> bool:
	if state != RideState.NO_RIDE or nearby_offer == null:
		return false
	offer = nearby_offer
	offers.mark(offer, PassengerOffer.State.ACCEPTED)
	set_state(RideState.OFFER_SELECTED)
	set_state(RideState.EN_ROUTE_TO_PICKUP)
	return true


func passenger_agent() -> HumanAgent:
	return offer.passenger if offer != null else null


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if current_reaction_time > 0.0:
		current_reaction_time -= delta
	match state:
		RideState.NO_RIDE:
			nearby_offer = offers.offer_near(player.global_position, config.accept_radius)
		RideState.EN_ROUTE_TO_PICKUP:
			_tick_en_route()
		RideState.BOARDING:
			_tick_boarding()
		RideState.ACTIVE:
			_tick_active(delta)
		RideState.EXITING:
			_tick_exiting()
		RideState.RETURN_TO_IDLE:
			offer = null
			set_state(RideState.NO_RIDE)


func _tick_en_route() -> void:
	var agent := passenger_agent()
	if agent == null:
		_cancel_offer()
		return
	var d := agent.global_position.distance_to(player.global_position)
	if d > config.cancel_distance:
		offers.release_back(offer)
		_cancel_offer()
		return
	if d <= config.pickup_radius and player.speed_kmh <= config.pickup_max_speed_kmh and not player.is_tipped:
		var behaviour := agent.behaviour as PassengerBehaviour
		behaviour.begin_boarding(agent, _seat, _boarding_point, config.boarding_seconds)
		set_state(RideState.BOARDING)


func _tick_boarding() -> void:
	var agent := passenger_agent()
	if agent == null:
		set_state(RideState.NO_RIDE)
		offer = null
		return
	var behaviour := agent.behaviour as PassengerBehaviour
	if behaviour.boarded:
		_start_ride()
		return
	# Tuk drove off before the passenger got in: back to waiting.
	if agent.global_position.distance_to(player.global_position) > config.pickup_radius + 4.0 \
			or player.speed_kmh > config.pickup_max_speed_kmh * 3.0:
		behaviour.cancel_boarding(agent)
		set_state(RideState.EN_ROUTE_TO_PICKUP)


func _start_ride() -> void:
	telemetry = RideTelemetry.new()
	reactions = PassengerReactionSystem.new(offer.profile, config)
	offers.mark(offer, PassengerOffer.State.IN_RIDE)
	remaining_m = offer.route_m
	_remaining_timer = 0.0
	set_state(RideState.ACTIVE)


func _tick_active(delta: float) -> void:
	var two_wheel := player.roll_state == TukController.RollState.TWO_WHEEL
	telemetry.sample(delta, player.speed_kmh, two_wheel, player.roll_deg, player.longitudinal_accel / 9.81, config)
	var key := reactions.tick(delta, player.speed_kmh, telemetry.elapsed)
	if not key.is_empty():
		_say(key)
	_remaining_timer -= delta
	if _remaining_timer <= 0.0:
		_remaining_timer = 1.0
		remaining_m = road.route_distance(player.global_position, offer.destination.global_position)
	var to_dest := player.global_position.distance_to(offer.destination.global_position)
	if to_dest <= config.arrive_radius and player.speed_kmh <= config.arrive_max_speed_kmh and not player.is_tipped:
		set_state(RideState.ARRIVED)
		_finish(RideResult.Outcome.COMPLETED, RideResult.FailReason.NONE)


func _finish(outcome: RideResult.Outcome, reason: RideResult.FailReason) -> void:
	var result := RideResult.new()
	result.outcome = outcome
	result.fail_reason = reason
	result.profile = offer.profile
	result.destination_key = offer.destination.display_name_key
	result.route_distance_m = offer.route_m
	result.telemetry = telemetry
	result.satisfaction = PassengerSatisfaction.evaluate(telemetry, offer.profile, offer.route_m, config)
	result.style_key = RideResult.style_for(telemetry, result.satisfaction)
	if outcome == RideResult.Outcome.COMPLETED:
		result.base_fare = RideResult.calculate_base_fare(offer.route_m, config)
		result.adjustment = RideResult.calculate_adjustment(result.base_fare, result.satisfaction.final_score, config)
		result.final_fare = maxi(result.base_fare + result.adjustment, 0)
		_say(reactions.arrival_key(result.satisfaction.final_score))
		set_state(RideState.COMPLETED)
	else:
		_say("REACT_COLLISION" if reason == RideResult.FailReason.ROLLOVER else "REACT_PEDESTRIAN_DANGER")
		set_state(RideState.FAILED)
	last_result = result
	result_ready.emit(result)
	EventBus.ride_finished.emit(result)
	_begin_exit(outcome == RideResult.Outcome.COMPLETED)


func _begin_exit(at_destination: bool) -> void:
	var agent := passenger_agent()
	if agent == null:
		set_state(RideState.EXITING)
		return
	var from := _boarding_point.global_position if _boarding_point != null else player.global_position
	from.y = maxf(from.y, 0.0)
	var target := humans.network.node_pos[offer.destination.node_id] if at_destination \
			else humans.network.node_pos[humans.network.nearest_node(from)]
	(agent.behaviour as PassengerBehaviour).begin_exit(agent, from, target)
	set_state(RideState.EXITING)


func _tick_exiting() -> void:
	var agent := passenger_agent()
	if agent != null:
		var behaviour := agent.behaviour as PassengerBehaviour
		if not behaviour.exited:
			return
		humans.release(agent)
	offers.finish(offer)
	set_state(RideState.RETURN_TO_IDLE)


func _cancel_offer() -> void:
	offer = null
	set_state(RideState.NO_RIDE)


func _say(key: String) -> void:
	current_reaction_key = key
	current_reaction_time = 3.0
	reaction.emit(key)
	EventBus.passenger_reaction.emit(key, offer.profile.id if offer != null else &"")


# --- Event hooks ---

func _on_skill(event: SkillEvent) -> void:
	if state != RideState.ACTIVE:
		return
	telemetry.record_skill(event.type, scoring.combo.chain if scoring != null else 0)
	reactions.on_skill(event.type)


func _on_collision(event: CollisionEvent) -> void:
	if state != RideState.ACTIVE:
		return
	if event.kind == CollisionEvent.Kind.ROLLOVER:
		telemetry.rollovers += 1
		if config.fail_on_rollover:
			_finish(RideResult.Outcome.FAILED, RideResult.FailReason.ROLLOVER)
		return
	telemetry.record_collision(event.severity == CollisionEvent.Severity.MAJOR)
	reactions.on_collision()


## Pedestrian danger: recorded as a safety incident. Never a reward.
func _on_pedestrian_danger(_event: PedestrianEvent) -> void:
	if state != RideState.ACTIVE:
		return
	telemetry.pedestrian_danger += 1
	reactions.on_pedestrian_danger()


func _on_pedestrian_impact(_event: PedestrianEvent) -> void:
	if state == RideState.ACTIVE:
		telemetry.pedestrian_impacts += 1
		_finish(RideResult.Outcome.FAILED, RideResult.FailReason.PEDESTRIAN_IMPACT)


func _on_roll_state(roll_state: TukController.RollState) -> void:
	if state == RideState.ACTIVE and roll_state == TukController.RollState.TWO_WHEEL:
		reactions.on_two_wheel()
