class_name TrafficIncidentManager
extends Node
## Social reactions to the player hitting traffic (v0.03A1).
##
## Listens to EventBus.collision_event; only TRAFFIC collisions with a valid
## other_agent_id qualify (walls, kerbs and rollovers never do). The tier comes
## from severity + impact speed (IncidentRules), the response from the
## driver's temperament:
##
##   LIGHT     horn or shout from the moving vehicle; rarely stop-and-yell
##   MODERATE  vehicle stops, horn burst; often the driver gets out
##   MAJOR     vehicle stops, repeated horn; driver (almost) always gets out
##
## Altercation flow (at most ONE at a time; further collisions only horn):
##   STOPPING → [HONKING | EXITING → APPROACHING → ARGUING → RETURNING]
##   → RESUMING → done
## Non-violent: talking distance only, no contact, no chase. If the player
## drives away the driver shouts once and walks back. Hard time cap.
##
## Presentation and audio go through EventBus hooks (traffic_horn,
## driver_shout, traffic_incident_started/resolved). Never touches score,
## combo or fare; the existing collision penalties stay where they were.

enum Horn { ANGRY, REPEATED, NEARBY }
enum Phase { NONE, STOPPING, HONKING, EXITING, APPROACHING, ARGUING, RETURNING, RESUMING }

@export var config: IncidentConfig

var traffic: TrafficManager
var humans: HumanManager
var player: TukController
var rng := RandomNumberGenerator.new()

# The single active altercation (or none).
var phase: Phase = Phase.NONE
var tier: IncidentRules.Tier = IncidentRules.Tier.NONE
var agent: TrafficAgent = null
var temperament: DriverTemperament = null
var driver: HumanAgent = null
var elapsed := 0.0
var phase_time := 0.0
var last_event: CollisionEvent = null
var player_left := false

# Diagnostics (debug HUD, tests, soak).
var stats_light := 0
var stats_altercations := 0
var stats_driver_exits := 0
var stats_suppressed := 0
var stats_ignored_world := 0
var stats_follower_horns := 0
var stats_timeouts := 0
var stats_resolved := 0
var stats_player_left := 0

var _start_distance := 0.0
var _argue_seconds := 0.0
var _honk_seconds := 0.0
var _shout_timer := 0.0
var _shout_index := 0
var _follower_timer := 0.0
var _last_light_time := -1000.0
var _agent_last_incident: Dictionary = {}  # agent_id -> SimClock time


func setup(p_traffic: TrafficManager, p_humans: HumanManager, p_player: TukController, seed_value: int = 0) -> void:
	traffic = p_traffic
	humans = p_humans
	player = p_player
	if config == null:
		config = IncidentConfig.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	EventBus.collision_event.connect(on_collision)
	humans.human_released.connect(_on_human_released)
	traffic.agent_despawned.connect(_on_agent_despawned)
	EventBus.player_reset.connect(func() -> void:
		if phase != Phase.NONE:
			_leave("DRIVER_SHOUT_LEFT"))


func is_active() -> bool:
	return phase != Phase.NONE


func phase_name() -> String:
	return Phase.keys()[phase]


func on_collision(event: CollisionEvent) -> void:
	var t := IncidentRules.tier_for(event, config)
	if t == IncidentRules.Tier.NONE:
		if event != null and event.kind == CollisionEvent.Kind.WORLD:
			stats_ignored_world += 1
		return
	var a := traffic.agent_by_id(event.other_agent_id)
	if a == null:
		return
	var now := SimClock.now()
	if a == agent:
		return  # the same vehicle again during its own incident
	if now - float(_agent_last_incident.get(a.agent_id, -1000.0)) < config.agent_cooldown:
		return
	var temp := IncidentRules.pick_temperament(config, rng.randf())
	var resp := IncidentRules.response(t, temp, config, rng.randf(), rng.randf())
	var stops := resp == IncidentRules.Response.STOP_AND_HONK or resp == IncidentRules.Response.STOP_AND_EXIT
	if stops and phase != Phase.NONE:
		# Only one altercation at a time: this one just horns.
		stats_suppressed += 1
		_agent_last_incident[a.agent_id] = now
		_horn(a, Horn.ANGRY)
		return
	_agent_last_incident[a.agent_id] = now
	last_event = event
	if not stops:
		if now - _last_light_time < config.light_cooldown:
			return
		_last_light_time = now
		stats_light += 1
		if resp == IncidentRules.Response.HORN_ONLY:
			_horn(a, Horn.ANGRY)
		_shout(a.global_position, "DRIVER_SHOUT_WATCH_OUT" if rng.randf() < 0.5 else "DRIVER_SHOUT_WHAT_DOING")
		EventBus.traffic_incident_started.emit(int(t), a.global_position)
		EventBus.traffic_incident_resolved.emit(int(t))
		return
	_begin(a, t, temp, resp == IncidentRules.Response.STOP_AND_EXIT)


func _begin(a: TrafficAgent, t: IncidentRules.Tier, temp: DriverTemperament, wants_exit: bool) -> void:
	agent = a
	tier = t
	temperament = temp
	driver = null
	elapsed = 0.0
	player_left = false
	_shout_index = rng.randi()
	_shout_timer = 0.0
	_follower_timer = config.follower_horn_interval
	_argue_seconds = IncidentRules.argue_seconds(t, temp, config, rng.randf()) if wants_exit else 0.0
	_honk_seconds = rng.randf_range(config.honk_only_seconds.x, config.honk_only_seconds.y) * (1.0 + temp.intensity * 0.5)
	agent.incident_hold = true
	_start_distance = player.global_position.distance_to(agent.global_position)
	stats_altercations += 1
	_set_phase(Phase.STOPPING)
	_horn(agent, Horn.REPEATED if t == IncidentRules.Tier.MAJOR else Horn.ANGRY)
	EventBus.traffic_incident_started.emit(int(t), agent.global_position)


func _set_phase(p: Phase) -> void:
	phase = p
	phase_time = 0.0


func _physics_process(delta: float) -> void:
	if phase == Phase.NONE:
		return
	elapsed += delta
	phase_time += delta
	if agent == null or not agent.is_active:
		_finish()
		return
	if elapsed > config.max_incident_seconds:
		stats_timeouts += 1
		_finish()
		return
	_follower_horns(delta)
	var b := driver.behaviour as DriverBehaviour if driver != null else null
	match phase:
		Phase.STOPPING:
			if phase_time >= config.stop_seconds and agent.speed < 0.5:
				if _argue_seconds > 0.0 and _spawn_driver():
					_set_phase(Phase.EXITING)
				else:
					_set_phase(Phase.HONKING)
		Phase.HONKING:
			_periodic_shout(agent.global_position + Vector3.UP * 1.2, delta)
			if phase_time >= _honk_seconds:
				_set_phase(Phase.RESUMING)
		Phase.EXITING:
			if phase_time >= config.exit_seconds:
				_update_approach_target(b)
				driver.set_state(HumanAgent.State.APPROACHING_PLAYER)
				_set_phase(Phase.APPROACHING)
		Phase.APPROACHING:
			if _player_has_left() or phase_time > config.approach_max_seconds:
				_leave("DRIVER_SHOUT_LEFT")
				return
			_update_approach_target(b)
			if b.arrived or driver.global_position.distance_to(b.approach_target) < 0.4:
				driver.set_state(HumanAgent.State.ARGUING)
				_shout_timer = 0.0
				_set_phase(Phase.ARGUING)
		Phase.ARGUING:
			b.face_target = player.global_position
			if _player_has_left():
				_leave("DRIVER_SHOUT_LEFT")
				return
			_periodic_shout(driver.global_position + Vector3.UP * 1.9, delta)
			if phase_time >= _argue_seconds:
				_walk_back()
		Phase.RETURNING:
			if b == null or b.back_in_vehicle or phase_time > 12.0:
				_release_driver()
				_set_phase(Phase.RESUMING)
		Phase.RESUMING:
			if phase_time >= config.resume_delay:
				_finish()


func _spawn_driver() -> bool:
	var door := agent.global_position + agent.right_vec * (agent.half_width + 0.6)
	door.y = 0.0
	driver = humans.acquire_driver(door, agent.right_vec)
	if driver == null:
		return false
	var b := driver.behaviour as DriverBehaviour
	b.door = door
	b.exit_seconds = config.exit_seconds
	driver.walk_speed = config.driver_walk_kmh / 3.6
	driver.set_reaction(HumanAgent.Reaction.ANGRY)
	stats_driver_exits += 1
	return true


func _update_approach_target(b: DriverBehaviour) -> void:
	var from_player := driver.global_position - player.global_position
	from_player.y = 0.0
	if from_player.length_squared() < 0.01:
		from_player = agent.right_vec
	var target := player.global_position + from_player.normalized() * config.argue_distance
	target.y = 0.0
	b.approach_target = target
	b.face_target = player.global_position


## "Clearly left": well beyond both the leave distance and where the tuk was
## when the incident began, or driving off briskly once some way away.
func _player_has_left() -> bool:
	var d := player.global_position.distance_to(agent.global_position)
	var limit := maxf(config.leave_distance, _start_distance + 8.0)
	return d > limit or (d > maxf(6.0, _start_distance + 3.0) and player.speed_kmh > config.leave_speed_kmh)


## Player drove off (or reset): one last shout, then walk back. No chase.
func _leave(line_key: String) -> void:
	if player_left:
		return
	player_left = true
	stats_player_left += 1
	var at := driver.global_position if driver != null else agent.global_position
	_shout(at + Vector3.UP * 1.9, line_key)
	if driver != null:
		_walk_back()
	else:
		_set_phase(Phase.RESUMING)


func _walk_back() -> void:
	if driver == null:
		_set_phase(Phase.RESUMING)
		return
	driver.set_state(HumanAgent.State.RETURNING_TO_VEHICLE)
	_set_phase(Phase.RETURNING)


func _periodic_shout(at: Vector3, delta: float) -> void:
	_shout_timer -= delta
	if _shout_timer > 0.0:
		return
	_shout_timer = config.shout_interval * lerpf(1.4, 0.8, temperament.intensity)
	var keys := temperament.argue_keys
	if keys.is_empty():
		return
	_shout_index += 1
	_shout(at, keys[_shout_index % keys.size()])
	if rng.randf() < temperament.intensity * 0.5:
		_horn(agent, Horn.ANGRY)


func _follower_horns(delta: float) -> void:
	_follower_timer -= delta
	if _follower_timer > 0.0:
		return
	_follower_timer = config.follower_horn_interval
	var r_sq := config.follower_horn_radius * config.follower_horn_radius
	for a in traffic.active_agents:
		if a == agent or a.speed > 0.5 or a.stopped_time < 1.5:
			continue
		if a.global_position.distance_squared_to(agent.global_position) > r_sq:
			continue
		if a.lane != agent.lane and a.next_lane != agent.lane and a.lane != agent.prev_lane:
			continue
		if rng.randf() < config.follower_horn_chance:
			stats_follower_horns += 1
			_horn(a, Horn.NEARBY)
		return  # at most one follower horn per interval


func _horn(a: TrafficAgent, pattern: Horn) -> void:
	EventBus.traffic_horn.emit(a.global_position + Vector3.UP * 1.5, int(pattern))


func _shout(at: Vector3, key: String) -> void:
	EventBus.driver_shout.emit(at, key)


func _release_driver() -> void:
	if driver != null and driver.is_pooled_active:
		humans.release(driver)
	driver = null


func _finish() -> void:
	_release_driver()
	if agent != null:
		agent.incident_hold = false
		agent.hold_timer = 0.0
		agent.stopped_time = 0.0
	var t := tier
	agent = null
	temperament = null
	tier = IncidentRules.Tier.NONE
	_set_phase(Phase.NONE)
	stats_resolved += 1
	EventBus.traffic_incident_resolved.emit(int(t))


func _on_human_released(a: HumanAgent) -> void:
	# e.g. the player hit the driver (pedestrian impact): no driver any more.
	if a == driver:
		driver = null
		if phase == Phase.EXITING or phase == Phase.APPROACHING or phase == Phase.ARGUING or phase == Phase.RETURNING:
			_set_phase(Phase.RESUMING)


func _on_agent_despawned(a: TrafficAgent) -> void:
	if a == agent:
		_finish()
