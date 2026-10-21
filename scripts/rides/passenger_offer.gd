class_name PassengerOffer
extends RefCounted
## One available job: who, from where, to where, and how far by road.

enum State { AVAILABLE, ACCEPTED, IN_RIDE, FINISHED }

var profile: PassengerProfile
var pickup: PedestrianSpot
var destination: PedestrianSpot
## Shortest route by road between pickup and destination (m).
var route_m := 0.0
var state: State = State.FINISHED
var passenger: HumanAgent = null
var respawn_timer := 0.0
