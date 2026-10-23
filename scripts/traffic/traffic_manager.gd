class_name TrafficManager
extends Node3D
## Owns the traffic population around the player: the pool, spawning and
## despawning outside the player's view, the adaptive performance budget and
## the single per-tick update loop for all active agents (one loop instead of
## one _physics_process per agent).

signal agent_spawned(agent: TrafficAgent)
signal agent_despawned(agent: TrafficAgent)

@export var config: TrafficConfig
@export var budget_config: TrafficBudgetConfig
@export var vehicle_classes: Array[TrafficVehicleClass] = []
## 0 = random seed each run.
@export var rng_seed := 0

var network: RoadNetwork
var player: TukController
var camera: Camera3D
var budget: AdaptiveTrafficBudget
var pool := TrafficPool.new()
var active_agents: Array[TrafficAgent] = []
## Every pooled agent by agent_id (resolves CollisionEvent.other_agent_id).
var agents_by_id: Array[TrafficAgent] = []
var rng := RandomNumberGenerator.new()

# Per-tick player context, cached so agents never query the player node.
var player_position := Vector3.ZERO
var player_velocity := Vector3.ZERO
var player_forward := Vector3.FORWARD
var player_half_width := 0.65
var player_half_length := 1.3

# Diagnostics (debug HUD and tests).
var stats_spawned := 0
var stats_despawned := 0
var stats_sink_despawns := 0
var stats_stuck_despawns := 0
var stats_budget_despawns := 0
var stats_behind_despawns := 0
var stats_visible_spawns := 0
var stats_spawn_failures := 0

var _spawn_timer := 0.0
var _slot_candidates := PackedInt32Array()
var _despawn_timer := 0.0


func setup(p_network: RoadNetwork, p_player: TukController, p_camera: Camera3D) -> void:
	network = p_network
	player = p_player
	camera = p_camera
	if config == null:
		config = TrafficConfig.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	budget = AdaptiveTrafficBudget.new(budget_config, config.gameplay_density_target)
	budget.changed.connect(_on_budget_changed)
	var extents := player.half_extents()
	player_half_width = extents.x
	player_half_length = extents.y
	_create_pool()
	_cache_player()
	_initial_fill()


func _exit_tree() -> void:
	active_agents.clear()
	TrafficAgentFactory.clear_cache()


func _create_pool() -> void:
	var id := 0
	for cls in vehicle_classes:
		for i in cls.pool_count:
			var agent := TrafficAgentFactory.create_agent(cls, id)
			agents_by_id.append(agent)
			id += 1
			add_child(agent)
			agent.deactivate()
			pool.add(agent)


## Active agent for a CollisionEvent.other_agent_id, or null.
func agent_by_id(id: int) -> TrafficAgent:
	if id < 0 or id >= agents_by_id.size():
		return null
	var a := agents_by_id[id]
	return a if a.is_active else null


func pool_capacity() -> int:
	return pool.capacity()


func target_count() -> int:
	return budget.get_actual_target() if budget != null else 0


func _on_budget_changed(ceiling: int, actual: int) -> void:
	EventBus.performance_budget_changed.emit(ceiling, actual)


func _process(delta: float) -> void:
	if budget != null:
		budget.push_frame(delta)


func _physics_process(delta: float) -> void:
	if network == null:
		return
	_cache_player()
	var i := active_agents.size() - 1
	while i >= 0:
		var agent := active_agents[i]
		if not agent.step(delta, self) and not agent.incident_hold:
			stats_sink_despawns += 1
			_despawn_at(i)
		i -= 1
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = config.spawn_interval
		var deficit := target_count() - active_agents.size()
		if deficit > 0:
			_try_spawn(false)
		if deficit > 3:
			_try_spawn(false)
	_despawn_timer -= delta
	if _despawn_timer <= 0.0:
		_despawn_timer = 0.25
		_despawn_pass()


func _cache_player() -> void:
	player_position = player.global_position
	player_velocity = player.linear_velocity
	player_forward = -player.global_transform.basis.z


# --- Visibility ---

func is_in_view(pos: Vector3) -> bool:
	if camera == null:
		return false
	var d2 := pos.distance_squared_to(player_position)
	if d2 > config.hidden_distance * config.hidden_distance:
		return false
	return camera.is_position_in_frustum(pos) or camera.is_position_in_frustum(pos + Vector3.UP * 2.5)


func can_despawn_silently(agent: TrafficAgent) -> bool:
	return not is_in_view(agent.global_position)


# --- Routing ---

func choose_next_lane(lane: Lane) -> Lane:
	var succ := lane.successors
	if succ.is_empty():
		return null
	if succ.size() == 1:
		return succ[0]
	var total := 0.0
	for l in succ:
		total += _route_weight(l)
	var r := rng.randf() * total
	for l in succ:
		r -= _route_weight(l)
		if r <= 0.0:
			return l
	return succ[succ.size() - 1]


func _route_weight(lane: Lane) -> float:
	if not lane.is_connector:
		return 1.0
	match lane.movement:
		IntersectionController.Movement.LEFT:
			return config.turn_weight_left
		IntersectionController.Movement.RIGHT:
			return config.turn_weight_right
	return config.turn_weight_straight


# --- Spawning ---

func _initial_fill() -> void:
	var attempts := 0
	while active_agents.size() < target_count() and attempts < target_count() * 30:
		_try_spawn(true)
		attempts += 1


func _try_spawn(initial: bool) -> bool:
	var cls := _pick_class()
	if cls == null or network.spawn_slot_count() == 0:
		return false
	var use_source := not initial and not network.source_lanes.is_empty() and rng.randf() < config.source_spawn_chance
	if use_source:
		for attempt in 3:
			var source := network.source_lanes[rng.randi() % network.source_lanes.size()]
			var s_src := minf(2.0 + cls.length * 0.5, source.length * 0.5)
			var p_src := source.sample_position(s_src)
			if not is_in_view(p_src) and _spawn_clear(source, s_src, cls, p_src):
				_activate(cls, source, s_src)
				return true
	# Gather every valid road slot (no allocation after warm-up), then try a
	# few at random. Scanning ~400 slots every spawn tick is cheap and finds
	# the narrow valid band far more reliably than blind random sampling.
	var min_d := config.initial_spawn_min_distance if initial else config.spawn_min_distance
	var min_sq := min_d * min_d
	var max_sq := config.spawn_max_distance * config.spawn_max_distance
	var player_right := player_forward.cross(Vector3.UP)
	var travel := Vector3(player_velocity.x, 0.0, player_velocity.z)
	var ahead_only := config.spawn_ahead_only and travel.length_squared() > 9.0
	var travel_dir := travel.normalized() if ahead_only else Vector3.ZERO
	_slot_candidates.clear()
	for slot in network.spawn_slot_count():
		var to := network.spawn_slot_pos[slot] - player_position
		var d2 := to.length_squared()
		if d2 < min_sq or d2 > max_sq:
			continue
		if initial:
			var ahead := to.dot(player_forward)
			if ahead > 0.0 and ahead < config.initial_clear_ahead and absf(to.dot(player_right)) < 10.0:
				continue
		else:
			if ahead_only and to.dot(travel_dir) < 0.0:
				continue
			if is_in_view(network.spawn_slot_pos[slot]):
				continue
		_slot_candidates.append(slot)
	for attempt in mini(config.spawn_attempts, _slot_candidates.size()):
		var pick := rng.randi() % _slot_candidates.size()
		var slot := _slot_candidates[pick]
		_slot_candidates[pick] = _slot_candidates[_slot_candidates.size() - 1]
		_slot_candidates.resize(_slot_candidates.size() - 1)
		var lane := network.spawn_slot_lanes[slot]
		var s := network.spawn_slot_s[slot]
		var pos := network.spawn_slot_pos[slot]
		if not _spawn_clear(lane, s, cls, pos):
			continue
		_activate(cls, lane, s)
		if not initial and is_in_view(pos):
			stats_visible_spawns += 1
		return true
	stats_spawn_failures += 1
	return false


func _pick_class() -> TrafficVehicleClass:
	var total := 0.0
	for cls in vehicle_classes:
		if pool.free_count(cls) > 0:
			total += cls.spawn_weight
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for cls in vehicle_classes:
		if pool.free_count(cls) == 0:
			continue
		r -= cls.spawn_weight
		if r <= 0.0:
			return cls
	return null


func _spawn_clear(lane: Lane, s: float, cls: TrafficVehicleClass, pos: Vector3) -> bool:
	for a in lane.agents:
		if absf(a.s - s) < config.min_spawn_separation + a.half_length + cls.length * 0.5:
			return false
	var clearance_sq := config.min_spawn_clearance * config.min_spawn_clearance
	for a in active_agents:
		if a.global_position.distance_squared_to(pos) < clearance_sq:
			return false
	return true


func _activate(cls: TrafficVehicleClass, lane: Lane, s: float) -> void:
	var agent := pool.acquire(cls)
	if agent == null:
		return
	var target := rng.randf_range(cls.min_speed_kmh, cls.max_speed_kmh) / 3.6
	var start_speed := minf(target, lane.advisory_at(s)) * rng.randf_range(0.7, 1.0)
	agent.set_body_material(TrafficAgentFactory.body_material(cls.body_colors[rng.randi() % cls.body_colors.size()]))
	agent.activate(lane, s, start_speed, target, choose_next_lane(lane))
	active_agents.append(agent)
	stats_spawned += 1
	agent_spawned.emit(agent)


# --- Despawning ---

func _despawn_pass() -> void:
	var over := active_agents.size() - target_count()
	var far_sq := config.despawn_distance * config.despawn_distance
	var near_sq := config.spawn_min_distance * config.spawn_min_distance
	var travel := Vector3(player_velocity.x, 0.0, player_velocity.z)
	var recycle_behind := config.spawn_ahead_only and travel.length_squared() > 9.0
	var travel_dir := travel.normalized() if recycle_behind else Vector3.ZERO
	for idx in range(active_agents.size() - 1, -1, -1):
		var agent := active_agents[idx]
		var d2 := agent.global_position.distance_squared_to(player_position)
		if agent.incident_hold or is_in_view(agent.global_position):
			continue
		if d2 > far_sq:
			_despawn_at(idx)
		elif recycle_behind and (agent.global_position - player_position).dot(travel_dir) < -config.behind_despawn_distance:
			stats_behind_despawns += 1
			_despawn_at(idx)
		elif agent.at_sink:
			stats_sink_despawns += 1
			_despawn_at(idx)
		elif agent.stopped_time > config.stuck_despawn_seconds:
			stats_stuck_despawns += 1
			_despawn_at(idx)
		elif over > 0 and d2 > near_sq:
			stats_budget_despawns += 1
			over -= 1
			_despawn_at(idx)


func _despawn_at(index: int) -> void:
	var agent := active_agents[index]
	active_agents.remove_at(index)
	agent.deactivate()
	pool.release(agent)
	stats_despawned += 1
	agent_despawned.emit(agent)


## Number of agents currently waiting at a stop line (debug).
func waiting_count() -> int:
	var n := 0
	for a in active_agents:
		if a.waiting_for_signal and a.speed < 0.5:
			n += 1
	return n
