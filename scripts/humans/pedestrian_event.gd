class_name PedestrianEvent
extends RefCounted
## A pedestrian-safety incident caused by the player. Deliberately separate from
## SkillEvent: these feed passenger safety and incident stats, never rewards.

enum Kind { DANGER, IMPACT }
enum Cause { CLOSE_PASS, FORCED_HURRY, SIDEWALK_DRIVING, CONTACT }

var kind: Kind = Kind.DANGER
var cause: Cause = Cause.CLOSE_PASS
var human_id := -1
## Edge-to-edge distance between tuk footprint and person (m).
var clearance := 0.0
## Player speed at the moment of the incident (km/h).
var player_speed_kmh := 0.0
var position := Vector3.ZERO
var timestamp := 0.0
