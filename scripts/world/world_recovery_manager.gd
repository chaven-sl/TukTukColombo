class_name WorldRecoveryManager
extends Node
## Puts the tuk back on a sensible road position (v0.03A2).
##
## Owns TukController.reset_pose_provider: every reset (R, tipped auto-recover,
## DISABLED crash, failsafe) picks the nearest legal lane, a little BEHIND the
## crash point, upright and facing the lane direction, clear of traffic and of
## people crossing. Never the world origin.
##
## Failsafe (bug protection, should almost never fire): below the world,
## outside the district envelope.

const CHECK_INTERVAL := 0.25
const BEHIND_OFFSETS: Array[float] = [-10.0, -18.0, -4.0, -26.0, 6.0, 14.0, -34.0, 22.0]

var network: RoadNetwork
var player: TukController
var traffic: TrafficManager
var humans: HumanManager

var stats_failsafe := 0
var stats_recoveries := 0
var last_reason := ""
var _timer := 0.0
var _pending_reason := ""
## Set by safe_reset_pose(): only resets that went through the provider (R,
## tipped auto-recover, DISABLED, failsafe) count — plain teleports don't.
var _resetting := false


func setup(p_network: RoadNetwork, p_player: TukController, p_traffic: TrafficManager, p_humans: HumanManager) -> void:
	network = p_network
	player = p_player
	traffic = p_traffic
	humans = p_humans
	player.reset_pose_provider = safe_reset_pose
	player.was_reset.connect(_on_was_reset)


## Requests a reset with a reason (shown/recorded); the pose comes from safe_reset_pose().
func recover(reason: String) -> void:
	_pending_reason = reason
	player.request_reset()


func _on_was_reset() -> void:
	if not _resetting:
		return
	_resetting = false
	stats_recoveries += 1
	last_reason = _pending_reason if not _pending_reason.is_empty() else "reset"
	_pending_reason = ""
	EventBus.vehicle_recovered.emit(last_reason)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	var p := player.global_position
	var outside := not network.district_rect.grow(3.0).has_point(Vector2(p.x, p.z))
	if p.y < -4.0 or outside:
		stats_failsafe += 1
		recover("void")


## Upright transform on the nearest lane, behind `from_pos` along the lane,
## clear of traffic and crossing pedestrians.
func safe_reset_pose(from_pos: Vector3) -> Transform3D:
	_resetting = true
	var candidates: Array = []
	for lane in network.lanes:
		if lane.is_connector or lane.length < 12.0:
			continue
		var s := lane.closest_s(from_pos)
		var d := lane.sample_position(s).distance_to(Vector3(from_pos.x, 0.0, from_pos.z))
		candidates.append([d, lane, s])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in mini(candidates.size(), 4):
		var lane: Lane = candidates[i][1]
		var s0: float = candidates[i][2]
		for off in BEHIND_OFFSETS:
			var s := s0 + off
			if s < 4.0 or s > lane.length - 4.0:
				continue
			var p := lane.sample_position(s)
			if is_clear(p):
				return Transform3D(MathUtil.basis_from_forward(lane.sample_tangent(s)), p + Vector3.UP * 0.35)
	return network.find_reset_transform(from_pos)


func is_clear(p: Vector3) -> bool:
	for ix in network.intersections:
		var d := Vector2(p.x - ix.global_position.x, p.z - ix.global_position.z)
		if absf(d.x) < ix.size * 0.5 + 3.0 and absf(d.y) < ix.size * 0.5 + 3.0:
			return false
	if traffic != null:
		for a in traffic.active_agents:
			if a.global_position.distance_squared_to(p) < 81.0:
				return false
	if humans != null:
		for h in humans.active:
			if h.visible and h.global_position.distance_squared_to(p) < 25.0:
				return false
	return true
