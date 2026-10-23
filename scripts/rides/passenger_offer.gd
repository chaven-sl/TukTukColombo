class_name PassengerOffer
extends RefCounted
## One available job: who, from where, to where, and how far by road.

enum State { AVAILABLE, ACCEPTED, IN_RIDE, FINISHED }

var profile: PassengerProfile
## v0.04: the passenger's own personality; `profile` is this job's copy with
## the job tier's expectations layered on (JobTiers.profile_for).
var base_profile: PassengerProfile
var tier: int = 0
var pickup: PedestrianSpot
var destination: PedestrianSpot
## Shortest route by road between pickup and destination (m).
var route_m := 0.0
var state: State = State.FINISHED
var passenger: HumanAgent = null
var respawn_timer := 0.0
