class_name HumanAgent
extends Node3D
## Shared foundation for every person in the world (pooled, no physics body).
##
## Logic: explicit State with a whitelist of transitions (TRANSITIONS); the
## per-state behaviour lives in a role object (PedestrianBehaviour,
## PassengerBehaviour) that owns the transitions between its own states.
## HumanManager owns INACTIVE and RETURNING_TO_POOL.
## Presentation: primitive capsule + head placeholders built once; a future
## animated character only needs to replace `visual` and read `state` /
## `reaction` / `is_moving`.
##
## Deliberately not a CharacterBody3D or RigidBody3D: people never push the
## tuk around; contact is a gameplay event (PEDESTRIAN_IMPACT) decided by
## HumanManager from cheap footprint checks.

signal state_changed(agent: HumanAgent, from_state: State, to_state: State)

enum State {
	INACTIVE, IDLE, WALKING, WAITING_TO_CROSS, CROSSING, REACTING,
	WAITING_FOR_PICKUP, APPROACHING_TUK, BOARDING, RIDING, EXITING, RETURNING_TO_POOL,
	# v0.03A1 traffic drivers (only in the world during an incident; while
	# driving they are logically IN_VEHICLE and have no HumanAgent).
	EXITING_VEHICLE, APPROACHING_PLAYER, ARGUING, RETURNING_TO_VEHICLE,
	# v0.03A2 emergency escape from a tuk heading at them (any role).
	EVADING,
}
enum Role { NONE, SIDEWALK_WALKER, CROSSING_PEDESTRIAN, WAITING_PEDESTRIAN, GROUP_MEMBER, PASSENGER, TRAFFIC_DRIVER }
enum Reaction { NONE, HESITATE, STEP_BACK, HURRY, FREEZE, ANGRY, EVADE, DIVE }

const TRANSITIONS := {
	State.INACTIVE: [State.IDLE, State.WALKING, State.WAITING_FOR_PICKUP, State.EXITING_VEHICLE],
	State.IDLE: [State.WALKING, State.REACTING, State.RETURNING_TO_POOL, State.EVADING],
	State.WALKING: [State.IDLE, State.WAITING_TO_CROSS, State.REACTING, State.RETURNING_TO_POOL, State.EVADING],
	State.WAITING_TO_CROSS: [State.CROSSING, State.WALKING, State.REACTING, State.RETURNING_TO_POOL, State.EVADING],
	State.CROSSING: [State.WALKING, State.IDLE, State.RETURNING_TO_POOL],
	State.REACTING: [State.WALKING, State.IDLE, State.WAITING_TO_CROSS, State.WAITING_FOR_PICKUP, State.RETURNING_TO_POOL, State.EVADING],
	State.WAITING_FOR_PICKUP: [State.APPROACHING_TUK, State.REACTING, State.RETURNING_TO_POOL, State.EVADING],
	State.APPROACHING_TUK: [State.BOARDING, State.WAITING_FOR_PICKUP, State.RETURNING_TO_POOL],
	State.BOARDING: [State.RIDING, State.WAITING_FOR_PICKUP, State.RETURNING_TO_POOL],
	State.RIDING: [State.EXITING, State.RETURNING_TO_POOL],
	State.EXITING: [State.RETURNING_TO_POOL, State.WALKING, State.EVADING],
	State.RETURNING_TO_POOL: [State.INACTIVE],
	State.EXITING_VEHICLE: [State.APPROACHING_PLAYER, State.RETURNING_TO_VEHICLE, State.RETURNING_TO_POOL, State.EVADING],
	State.APPROACHING_PLAYER: [State.ARGUING, State.RETURNING_TO_VEHICLE, State.RETURNING_TO_POOL, State.EVADING],
	State.ARGUING: [State.RETURNING_TO_VEHICLE, State.RETURNING_TO_POOL, State.EVADING],
	State.RETURNING_TO_VEHICLE: [State.RETURNING_TO_POOL, State.EVADING],
	# Evading people return to their own role's state (pedestrians IDLE,
	# waiting passengers WAITING_FOR_PICKUP, exiting passengers EXITING,
	# drivers RETURNING_TO_VEHICLE).
	State.EVADING: [State.IDLE, State.WAITING_FOR_PICKUP, State.EXITING, State.RETURNING_TO_VEHICLE, State.RETURNING_TO_POOL],
}

## Counts rejected transitions (tests and the soak assert this stays 0).
static var invalid_transitions := 0

var human_id := -1
var role: Role = Role.NONE
var state: State = State.INACTIVE
var reaction: Reaction = Reaction.NONE
var behaviour: RefCounted = null
var is_pooled_active := false

# Movement / path (node ids in PedestrianNetwork).
var path := PackedInt32Array()
var path_index := 0
var current_node := -1
## Internal m/s; use walk_speed_kmh() for anything human-readable.
var walk_speed := 1.25
var speed_multiplier := 1.0
var is_moving := false
var destination := Vector3.ZERO
var home_spot: PedestrianSpot = null

# Crossing.
var crossing: CrossingZone = null
var crossing_from := Vector3.ZERO
var crossing_to := Vector3.ZERO
var crossing_progress := 0.0
var crossing_margin := 2.0
var wait_time := 0.0

# Timers / reaction bookkeeping.
var idle_timer := 0.0
var reaction_timer := 0.0
var resume_state: State = State.IDLE
var awareness_timer := 0.0
var danger_cooldown_until := -100.0
## Direction to step when reacting: away from the threat's line of travel.
var react_dir := Vector3.ZERO
var stuck_time := 0.0

# Emergency evasion (v0.03A2).
var evade_target := Vector3.ZERO
var evade_speed := 4.5
var evade_settle := 1.5
var evade_dive := false
var evade_resume: State = State.IDLE

# Passenger role.
var passenger_profile: PassengerProfile = null
var boarding_target := Vector3.ZERO
var state_timer := 0.0

var visual: Node3D
var _body: MeshInstance3D
var _marker: MeshInstance3D
var _indicator: MeshInstance3D
var debug_label: Label3D
var _bob_phase := 0.0


func walk_speed_kmh() -> float:
	return walk_speed * speed_multiplier * 3.6


## Validated state change. Returns false (and counts it) when not allowed.
func set_state(to: State) -> bool:
	if to == state:
		return true
	var allowed: Array = TRANSITIONS.get(state, [])
	if not allowed.has(to):
		invalid_transitions += 1
		push_warning("[HumanAgent %d] invalid transition %s -> %s" % [human_id, State.keys()[state], State.keys()[to]])
		return false
	var from := state
	_on_leave(from)
	state = to
	state_timer = 0.0
	state_changed.emit(self, from, to)
	return true


func _on_leave(from: State) -> void:
	if crossing == null:
		return
	if from == State.WAITING_TO_CROSS:
		crossing.waiting_count = maxi(crossing.waiting_count - 1, 0)
	elif from == State.CROSSING:
		crossing.occupied_count = maxi(crossing.occupied_count - 1, 0)
		crossing = null
		speed_multiplier = 1.0


func set_reaction(r: Reaction) -> void:
	reaction = r
	if _indicator == null:
		return
	_indicator.visible = r != Reaction.NONE
	if r != Reaction.NONE:
		_indicator.material_override = HumanAgentFactory.reaction_material(r)


func is_on_road() -> bool:
	return state == State.CROSSING


func show_passenger_marker(color: Color) -> void:
	if _marker != null:
		_marker.visible = true
		_marker.material_override = HumanAgentFactory.marker_material(color)


func hide_passenger_marker() -> void:
	if _marker != null:
		_marker.visible = false


func set_body_color(color: Color) -> void:
	if _body != null:
		_body.material_override = HumanAgentFactory.body_material(color)


## Called by the factory once at pool creation.
func attach_visual(root: Node3D, body: MeshInstance3D, marker: MeshInstance3D, indicator: MeshInstance3D, label: Label3D) -> void:
	visual = root
	_body = body
	_marker = marker
	_indicator = indicator
	debug_label = label


## Moves towards `target` at the current speed. Returns true on arrival.
func step_towards(target: Vector3, delta: float) -> bool:
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	var stride := walk_speed * speed_multiplier * delta
	if dist <= stride or dist < 0.01:
		global_position = Vector3(target.x, target.y, target.z)
		is_moving = false
		return true
	var dir := to / dist
	var p := global_position + dir * stride
	p.y = lerpf(global_position.y, target.y, clampf(stride / dist, 0.0, 1.0))
	global_position = p
	face(dir)
	is_moving = true
	return false


func face(dir: Vector3) -> void:
	if dir.length_squared() > 0.0001:
		basis = MathUtil.basis_from_forward(dir)


## Cheap placeholder motion: a little bob while walking.
func update_visual(delta: float) -> void:
	if visual == null:
		return
	if is_moving:
		_bob_phase += delta * walk_speed * speed_multiplier * 7.0
		visual.position.y = absf(sin(_bob_phase)) * 0.05
	else:
		visual.position.y = move_toward(visual.position.y, 0.0, delta)
	if _marker != null and _marker.visible:
		_marker.rotation.y += delta * 2.0


func reset_for_pool() -> void:
	path = PackedInt32Array()
	path_index = 0
	current_node = -1
	role = Role.NONE
	reaction = Reaction.NONE
	behaviour = null
	crossing = null
	speed_multiplier = 1.0
	passenger_profile = null
	home_spot = null
	wait_time = 0.0
	stuck_time = 0.0
	is_moving = false
	set_reaction(Reaction.NONE)
	hide_passenger_marker()
	if visual != null:
		visual.scale = Vector3.ONE
