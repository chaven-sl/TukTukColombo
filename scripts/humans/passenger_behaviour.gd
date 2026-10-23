class_name PassengerBehaviour
extends RefCounted
## PASSENGER role. Owns WAITING_FOR_PICKUP, APPROACHING_TUK, BOARDING, RIDING
## and EXITING. RideManager drives it through begin_boarding() /
## begin_exit(); this object only moves the body and reports progress.

const APPROACH_SPEED := 1.9  # internal m/s (≈ 6.8 km/h, a brisk walk)
## v0.03B: seated presentation relative to SeatMarker (rig origin = feet;
## hips rest ≈ 0.91 m above it, the seat cushion top ≈ marker + 0.05 m).
const SEATED_OFFSET := Transform3D(Basis.IDENTITY, Vector3(0.18, 0.12 - 0.91, 0.0))

var seat: Node3D
var boarding_point: Node3D
var exit_target := Vector3.ZERO
var boarding_seconds := 0.8
var boarded := false
var exited := false


func begin_boarding(a: HumanAgent, p_seat: Node3D, p_boarding_point: Node3D, seconds: float) -> void:
	seat = p_seat
	boarding_point = p_boarding_point
	boarding_seconds = seconds
	boarded = false
	a.speed_multiplier = APPROACH_SPEED / maxf(a.walk_speed, 0.3)
	a.set_state(HumanAgent.State.APPROACHING_TUK)


## Tuk left before boarding finished: wait at the pickup again.
func cancel_boarding(a: HumanAgent) -> void:
	a.speed_multiplier = 1.0
	a.detach_presentation()
	a.visible = true
	if a.visual != null:
		a.visual.scale = Vector3.ONE
	a.set_state(HumanAgent.State.WAITING_FOR_PICKUP)


func begin_exit(a: HumanAgent, from: Vector3, target: Vector3) -> void:
	exited = false
	a.detach_presentation()  # back to a normal walking presentation
	a.global_position = from
	a.visible = true
	if a.visual != null:
		a.visual.scale = Vector3.ONE
	exit_target = target
	a.speed_multiplier = 1.0
	a.reset_physics_interpolation()
	a.set_state(HumanAgent.State.EXITING)


func tick(a: HumanAgent, delta: float, mgr: HumanManager) -> void:
	a.state_timer += delta
	match a.state:
		HumanAgent.State.WAITING_FOR_PICKUP:
			if a.reaction != HumanAgent.Reaction.NONE:
				a.reaction_timer -= delta
				if a.reaction_timer <= 0.0:
					a.set_reaction(HumanAgent.Reaction.NONE)
			var home := mgr.network.node_pos[a.current_node] if a.current_node >= 0 else a.global_position
			if a.global_position.distance_to(home) > 0.2:
				a.step_towards(home, delta)
			else:
				a.is_moving = false
				var out := mgr.network.node_out[a.current_node] if a.current_node >= 0 else Vector3.FORWARD
				a.face(-out)
		HumanAgent.State.APPROACHING_TUK:
			var target := boarding_point.global_position
			target.y = maxf(target.y, 0.0)
			if a.step_towards(target, delta) or a.global_position.distance_to(target) < 0.5:
				a.set_state(HumanAgent.State.BOARDING)
		HumanAgent.State.BOARDING:
			a.is_moving = false
			var t := clampf(a.state_timer / maxf(boarding_seconds, 0.01), 0.0, 1.0)
			# v0.03B: step up into the tuk instead of shrinking away.
			if seat != null and a.presentation_attached_to == null:
				a.global_position = boarding_point.global_position.lerp(seat.global_position, t)
				a.face(-seat.global_transform.basis.z)
			if t >= 1.0:
				a.hide_passenger_marker()
				# Visible for the whole ride, seated on SeatMarker.
				a.attach_presentation(seat, SEATED_OFFSET)
				boarded = true
				a.set_state(HumanAgent.State.RIDING)
		HumanAgent.State.RIDING:
			if seat != null:
				a.global_position = seat.global_position
		HumanAgent.State.EXITING:
			if a.step_towards(exit_target, delta) or a.state_timer > 20.0:
				exited = true
