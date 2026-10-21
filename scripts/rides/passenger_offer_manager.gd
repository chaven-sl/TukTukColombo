class_name PassengerOfferManager
extends Node
## Keeps one passenger offer per configured pickup spot. Each offer has a
## profile, a destination (DROPOFF spot) and a lane-graph route distance, and a
## physical passenger HumanAgent waiting at the pickup. Finished offers come
## back after a delay with a new destination.

signal offers_changed()

## Paired by index: profiles[i] waits at the PICKUP spot pickup_spot_ids[i]
## and is first sent to initial_destination_ids[i].
@export var profiles: Array[PassengerProfile] = []
@export var pickup_spot_ids: Array[StringName] = []
@export var initial_destination_ids: Array[StringName] = []
@export var config: RideConfig

var offers: Array[PassengerOffer] = []
var network: PedestrianNetwork
var road: RoadNetwork
var humans: HumanManager
var rng := RandomNumberGenerator.new()


func setup(p_network: PedestrianNetwork, p_road: RoadNetwork, p_humans: HumanManager, seed_value: int = 0) -> void:
	network = p_network
	road = p_road
	humans = p_humans
	if config == null:
		config = RideConfig.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	humans.passenger_lost.connect(_on_passenger_lost)
	for i in profiles.size():
		var pickup := network.find_spot(pickup_spot_ids[i]) if i < pickup_spot_ids.size() else null
		if pickup == null:
			push_warning("[PassengerOfferManager] no pickup spot for %s" % profiles[i].id)
			continue
		var offer := PassengerOffer.new()
		offer.profile = profiles[i]
		offer.pickup = pickup
		var first := network.find_spot(initial_destination_ids[i]) if i < initial_destination_ids.size() else null
		_assign_destination(offer, first)
		offers.append(offer)
		_spawn_passenger(offer)


func _assign_destination(offer: PassengerOffer, preferred: PedestrianSpot) -> void:
	var options := network.spots_of_kind(PedestrianSpot.Kind.DROPOFF)
	var chosen: PedestrianSpot = preferred
	if chosen == null:
		var valid: Array[PedestrianSpot] = []
		for spot in options:
			if spot == offer.destination:
				continue
			if road.route_distance(offer.pickup.global_position, spot.global_position) >= config.min_offer_route_m:
				valid.append(spot)
		if valid.is_empty():
			valid = options
		chosen = valid[rng.randi() % valid.size()]
	offer.destination = chosen
	offer.route_m = road.route_distance(offer.pickup.global_position, chosen.global_position)


func _spawn_passenger(offer: PassengerOffer) -> bool:
	var agent := humans.acquire_passenger(offer.profile, offer.pickup)
	if agent == null:
		return false
	offer.passenger = agent
	offer.state = PassengerOffer.State.AVAILABLE
	offers_changed.emit()
	return true


## Nearest AVAILABLE offer whose passenger is within `radius` of `pos`.
func offer_near(pos: Vector3, radius: float) -> PassengerOffer:
	var best: PassengerOffer = null
	var best_d := radius * radius
	for offer in offers:
		if offer.state != PassengerOffer.State.AVAILABLE or offer.passenger == null:
			continue
		var d := offer.passenger.global_position.distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best = offer
	return best


func available_count() -> int:
	var n := 0
	for offer in offers:
		if offer.state == PassengerOffer.State.AVAILABLE:
			n += 1
	return n


func mark(offer: PassengerOffer, state: PassengerOffer.State) -> void:
	offer.state = state
	offers_changed.emit()


## Ride over (completed, failed or cancelled after the passenger left).
func finish(offer: PassengerOffer) -> void:
	offer.state = PassengerOffer.State.FINISHED
	offer.passenger = null
	offer.respawn_timer = config.offer_respawn_seconds
	offers_changed.emit()


## Cancelled before boarding: the same passenger keeps waiting.
func release_back(offer: PassengerOffer) -> void:
	offer.state = PassengerOffer.State.AVAILABLE
	offers_changed.emit()


func _on_passenger_lost(agent: HumanAgent) -> void:
	for offer in offers:
		if offer.passenger == agent:
			finish(offer)


func _physics_process(delta: float) -> void:
	for offer in offers:
		if offer.state != PassengerOffer.State.FINISHED:
			continue
		offer.respawn_timer -= delta
		if offer.respawn_timer > 0.0:
			continue
		# Don't pop a passenger into view right in front of the player.
		var spot_pos := offer.pickup.global_position
		if humans.is_in_view(spot_pos) and spot_pos.distance_to(humans.player_position) < 60.0:
			offer.respawn_timer = 1.0
			continue
		_assign_destination(offer, null)
		if not _spawn_passenger(offer):
			offer.respawn_timer = 2.0
