class_name DriverBehaviour
extends RefCounted
## TRAFFIC_DRIVER role (v0.03A1). Owns EXITING_VEHICLE, APPROACHING_PLAYER,
## ARGUING and RETURNING_TO_VEHICLE. TrafficIncidentManager decides *when*
## (approach / argue / walk back); this object only moves the body.
##
##   (IN_VEHICLE, no agent) → EXITING_VEHICLE → APPROACHING_PLAYER → ARGUING
##   → RETURNING_TO_VEHICLE → released to the pool (back IN_VEHICLE)
##
## Non-violent by design: the driver stops at a talking distance, gestures
## (ANGRY indicator + bob) and shouts; there is no contact and no chase.

var door := Vector3.ZERO
var approach_target := Vector3.ZERO
var face_target := Vector3.ZERO
var exit_seconds := 0.7
var arrived := false
var back_in_vehicle := false


func tick(a: HumanAgent, delta: float, _mgr: HumanManager) -> void:
	a.state_timer += delta
	match a.state:
		HumanAgent.State.EXITING_VEHICLE:
			a.is_moving = false
			if a.visual != null:
				a.visual.scale = Vector3.ONE * lerpf(0.6, 1.0, clampf(a.state_timer / maxf(exit_seconds, 0.01), 0.0, 1.0))
		HumanAgent.State.APPROACHING_PLAYER:
			arrived = a.step_towards(approach_target, delta)
		HumanAgent.State.ARGUING:
			a.is_moving = false
			var to := face_target - a.global_position
			to.y = 0.0
			a.face(to)
			# Placeholder gesture: an agitated bob until real animation exists.
			if a.visual != null:
				a.visual.position.y = absf(sin(a.state_timer * 9.0)) * 0.08
		HumanAgent.State.RETURNING_TO_VEHICLE:
			if a.step_towards(door, delta):
				back_in_vehicle = true
