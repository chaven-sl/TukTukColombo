class_name NearMissDetector
extends Node
## Detects CLOSE_CALL and TIGHT_GAP events. Never touches UI or score.
##
## Not a trigger volume: a pass must be earned.
##   1. CANDIDATE  – moving traffic enters proximity with meaningful relative
##                   speed while the player is driving.
##   2. TRACK      – closest edge-to-edge clearance (oriented rectangles) and
##                   side are tracked; staying alongside too long expires it.
##   3. CROSS      – the agent's centre crosses the player's reference plane.
##   4. CONFIRM    – wait briefly / until fully clear to make sure no contact
##                   happened, then classify and emit on EventBus.
## A TIGHT_GAP is two qualifying threat passes on opposite sides within
## tight_gap_window. Each agent has a cooldown so one car can't be farmed.

const STATE_IDLE := 0
const STATE_TRACKING := 1
const STATE_CONFIRMING := 2

@export var config: ScoringConfig

var player: TukController
var traffic: TrafficManager

# Diagnostics.
var candidate_count := 0
var events_close_call := 0
var events_tight_gap := 0
var rejected_collision := 0
var rejected_clearance := 0
var rejected_speed := 0
var expired := 0

# Per-agent candidate state, indexed by agent_id (fixed size = pool capacity).
var _state := PackedByteArray()
var _suppressed := PackedByteArray()
var _min_clearance := PackedFloat32Array()
var _time_tracked := PackedFloat32Array()
var _slow_alongside := PackedFloat32Array()
var _start_time := PackedFloat32Array()
var _cross_time := PackedFloat32Array()
var _cross_rel_speed := PackedFloat32Array()
var _long_sign := PackedInt32Array()
var _side := PackedInt32Array()

var _last_threat_time := -100.0
var _last_threat_side := 0
var _last_threat_agent := -1
var _last_threat_clearance := 0.0


func _ready() -> void:
	if config == null:
		config = ScoringConfig.new()
	process_physics_priority = 10  # after vehicle and traffic have moved


func setup(p_player: TukController, p_traffic: TrafficManager) -> void:
	player = p_player
	traffic = p_traffic
	var n := traffic.pool_capacity()
	_state.resize(n)
	_state.fill(STATE_IDLE)
	_suppressed.resize(n)
	_suppressed.fill(0)
	_min_clearance.resize(n)
	_time_tracked.resize(n)
	_slow_alongside.resize(n)
	_start_time.resize(n)
	_cross_time.resize(n)
	_cross_rel_speed.resize(n)
	_long_sign.resize(n)
	_side.resize(n)
	traffic.agent_despawned.connect(_on_agent_despawned)


func _on_agent_despawned(agent: TrafficAgent) -> void:
	_state[agent.agent_id] = STATE_IDLE
	_suppressed[agent.agent_id] = 0
	if _last_threat_agent == agent.agent_id:
		_last_threat_agent = -1


func is_candidate(agent_id: int) -> bool:
	return agent_id >= 0 and agent_id < _state.size() and _state[agent_id] != STATE_IDLE


func _physics_process(delta: float) -> void:
	if player == null or traffic == null:
		return
	var now := SimClock.now()
	var cfg := config
	var xf := player.global_transform
	var pf3 := -xf.basis.z
	var f1 := Vector2(pf3.x, pf3.z)
	if f1.length_squared() < 0.0001:
		return
	f1 = f1.normalized()
	var r1 := Vector2(-f1.y, f1.x)
	var body_offset := xf.basis * player.tuning.body_center
	var c1 := Vector2(xf.origin.x + body_offset.x, xf.origin.z + body_offset.z)
	var ext := player.half_extents()
	var pv := Vector2(player.linear_velocity.x, player.linear_velocity.z)
	var player_moving := player.speed_kmh >= cfg.min_player_speed_kmh
	var broad_sq := cfg.broad_phase_radius * cfg.broad_phase_radius
	candidate_count = 0

	for agent in traffic.active_agents:
		var id := agent.agent_id
		var ap := agent.global_position
		var c2 := Vector2(ap.x, ap.z)
		if c2.distance_squared_to(c1) > broad_sq:
			if _state[id] == STATE_TRACKING:
				_state[id] = STATE_IDLE
				expired += 1
			elif _state[id] == STATE_CONFIRMING:
				_confirm(agent, now)
			_suppressed[id] = 0
			continue
		var f2 := Vector2(agent.forward_vec.x, agent.forward_vec.z)
		var clearance := OrientedRect.distance(c1, f1, ext.x, ext.y, c2, f2, agent.half_width, agent.half_length)
		var rel := pv - Vector2(agent.velocity_vec.x, agent.velocity_vec.z)
		var rel_speed := rel.length()
		var offset := c2 - c1
		var longitudinal := offset.dot(f1)
		var lateral := offset.dot(r1)
		var collided := agent.last_collision_time >= _start_time[id] and _state[id] != STATE_IDLE

		if _suppressed[id] == 1:
			if clearance > cfg.proximity_distance:
				_suppressed[id] = 0
			continue

		match _state[id]:
			STATE_IDLE:
				if clearance <= cfg.proximity_distance and player_moving \
						and rel_speed >= cfg.min_relative_speed * 0.75 \
						and now - agent.last_award_time >= cfg.agent_cooldown:
					_state[id] = STATE_TRACKING
					_start_time[id] = now
					_time_tracked[id] = 0.0
					_slow_alongside[id] = 0.0
					_min_clearance[id] = clearance
					_side[id] = 1 if lateral >= 0.0 else -1
					_long_sign[id] = 1 if longitudinal >= 0.0 else -1
			STATE_TRACKING:
				candidate_count += 1
				_time_tracked[id] += delta
				if absf(longitudinal) < ext.y + agent.half_length and rel_speed < cfg.min_relative_speed * 0.6:
					_slow_alongside[id] += delta
				if clearance < _min_clearance[id]:
					_min_clearance[id] = clearance
					_side[id] = 1 if lateral >= 0.0 else -1
				var sign_now := 1 if longitudinal >= 0.0 else -1
				if collided:
					_state[id] = STATE_IDLE
					_suppressed[id] = 1
					rejected_collision += 1
				elif sign_now != _long_sign[id]:
					_state[id] = STATE_CONFIRMING
					_cross_time[id] = now
					_cross_rel_speed[id] = rel_speed
				elif clearance > cfg.proximity_distance * 1.3:
					_state[id] = STATE_IDLE
					expired += 1
				elif _slow_alongside[id] > cfg.max_alongside_time or _time_tracked[id] > cfg.max_track_time:
					_state[id] = STATE_IDLE
					_suppressed[id] = 1
					expired += 1
			STATE_CONFIRMING:
				candidate_count += 1
				if clearance < _min_clearance[id]:
					_min_clearance[id] = clearance
				if collided:
					_state[id] = STATE_IDLE
					_suppressed[id] = 1
					rejected_collision += 1
				elif absf(longitudinal) > ext.y + agent.half_length or now - _cross_time[id] >= cfg.confirm_time:
					_confirm(agent, now)


func _confirm(agent: TrafficAgent, now: float) -> void:
	var id := agent.agent_id
	var cfg := config
	_state[id] = STATE_IDLE
	if agent.last_collision_time >= _start_time[id]:
		rejected_collision += 1
		return
	var clearance := _min_clearance[id]
	var rel_speed := _cross_rel_speed[id]
	var side := _side[id]
	var oncoming := agent.forward_vec.dot(-player.global_transform.basis.z) < -0.5
	var valid_close := clearance >= cfg.min_valid_clearance and clearance <= cfg.max_valid_clearance \
			and rel_speed >= cfg.min_relative_speed
	var threat := clearance <= cfg.tight_gap_threat_clearance and rel_speed >= cfg.tight_gap_min_relative_speed

	if threat and _last_threat_agent >= 0 and _last_threat_agent != id and side != _last_threat_side \
			and absf(_cross_time[id] - _last_threat_time) <= cfg.tight_gap_window:
		var ev := SkillEvent.new()
		ev.type = SkillEvent.Type.TIGHT_GAP
		ev.clearance = minf(clearance, _last_threat_clearance)
		ev.relative_speed = rel_speed
		ev.side = 0
		ev.agent_ids = PackedInt32Array([_last_threat_agent, id])
		ev.timestamp = now
		ev.is_oncoming = oncoming
		agent.last_award_time = now
		_mark_awarded(_last_threat_agent, now)
		_last_threat_agent = -1
		events_tight_gap += 1
		EventBus.skill_event.emit(ev)
		return

	if threat:
		_last_threat_time = _cross_time[id]
		_last_threat_side = side
		_last_threat_agent = id
		_last_threat_clearance = clearance

	if valid_close:
		var ev := SkillEvent.new()
		ev.type = SkillEvent.Type.CLOSE_CALL
		ev.clearance = clearance
		ev.relative_speed = rel_speed
		ev.side = side
		ev.agent_ids = PackedInt32Array([id])
		ev.timestamp = now
		ev.is_oncoming = oncoming
		agent.last_award_time = now
		events_close_call += 1
		EventBus.skill_event.emit(ev)
	elif rel_speed < cfg.min_relative_speed:
		rejected_speed += 1
	else:
		rejected_clearance += 1


func _mark_awarded(agent_id: int, now: float) -> void:
	for agent in traffic.active_agents:
		if agent.agent_id == agent_id:
			agent.last_award_time = now
			return
