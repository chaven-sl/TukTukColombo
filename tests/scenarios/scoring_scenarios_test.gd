extends Node3D
## Deterministic near-miss / combo scenarios with hand-placed traffic.
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/scoring_scenarios_test.tscn
##
## The player tuk drives straight down -Z at a held speed past traffic agents
## placed at exact lateral clearances. Verifies CLOSE_CALL, TIGHT_GAP, the
## clearance and relative-speed rejections, combo growth, collision reset and
## no duplicate awards for one pass.

const TUK_SCENE := preload("res://scenes/player/player_tuk.tscn")
const CAR := preload("res://resources/traffic/car.tres")
const SCORING := preload("res://resources/scoring/scoring_config.tres")

var tuk: TukController
var traffic: TrafficManager
var detector: NearMissDetector
var scoring: ScoringSystem
var agents: Array[TrafficAgent] = []

var _scenarios: Array[Dictionary] = []
var _index := -1
var _t := 0.0
var _events: Array[SkillEvent] = []
var _awards: Array[Vector2i] = []   # (points, multiplier)
var _collisions := 0
var _failures := 0
var _combo_resets := 0


func _ready() -> void:
	var ground := StaticBody3D.new()
	ground.set_meta(&"is_ground", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 2000)
	shape.shape = box
	shape.position = Vector3(0, -1, -900)
	ground.add_child(shape)
	add_child(ground)

	tuk = TUK_SCENE.instantiate()
	add_child(tuk)
	tuk.get_node("PlayerInput").set("enabled", false)
	traffic = TrafficManager.new()
	add_child(traffic)
	for i in 4:
		var agent := TrafficAgentFactory.create_agent(CAR, i)
		traffic.add_child(agent)
		agent.deactivate()
		traffic.pool.add(agent)
		agents.append(agent)
	detector = NearMissDetector.new()
	detector.config = SCORING
	add_child(detector)
	detector.setup(tuk, traffic)
	scoring = ScoringSystem.new()
	scoring.config = SCORING
	add_child(scoring)
	scoring.combo_lost.connect(func(_r: int) -> void: _combo_resets += 1)
	EventBus.skill_event.connect(func(e: SkillEvent) -> void: _events.append(e))
	EventBus.score_awarded.connect(func(_type: int, points: int, mult: int, _total: int) -> void:
		_awards.append(Vector2i(points, mult)))
	EventBus.collision_event.connect(func(_e: CollisionEvent) -> void: _collisions += 1)

	var car_hw := CAR.width * 0.5
	var tuk_hw := 0.65
	# offset = lateral centre offset giving the requested edge clearance.
	var off := func(clearance: float) -> float: return tuk_hw + car_hw + clearance
	_scenarios = [
		{"name": "single close call (0.5 m, 50 km/h past parked car)", "speed": 50.0,
			"cars": [Vector3(off.call(0.5), 0, -60)], "expect": {"close": 1, "gap": 0}},
		{"name": "too wide (1.4 m) -> nothing", "speed": 50.0,
			"cars": [Vector3(off.call(1.4), 0, -60)], "expect": {"close": 0, "gap": 0}},
		{"name": "too slow (18 km/h, rel < 6 m/s) -> nothing", "speed": 18.0,
			"cars": [Vector3(-off.call(0.5), 0, -40)], "expect": {"close": 0, "gap": 0}},
		{"name": "tight gap between two cars (0.5 m each side)", "speed": 50.0,
			"cars": [Vector3(-off.call(0.5), 0, -60), Vector3(off.call(0.55), 0, -62)], "expect": {"gap": 1, "min_close": 1}},
		{"name": "three close calls in a row build combo x1..x3", "speed": 50.0,
			"cars": [Vector3(off.call(0.5), 0, -50), Vector3(-off.call(0.5), 0, -75), Vector3(off.call(0.6), 0, -100)],
			"expect": {"close": 3, "gap": 0, "multipliers": [1, 2, 3]}},
		{"name": "side-swipe collision -> no award, combo reset", "speed": 45.0,
			"cars": [Vector3(off.call(0.6), 0, -40), Vector3(off.call(-0.25), 0, -80)],
			"expect": {"close": 1, "gap": 0, "collision": true, "reset": true}},
	]
	_next()


func _next() -> void:
	_index += 1
	if _index >= _scenarios.size():
		_finish()
		return
	var sc: Dictionary = _scenarios[_index]
	_t = 0.0
	_events.clear()
	_awards.clear()
	_collisions = 0
	_combo_resets = 0
	scoring.combo.reset()
	for agent in agents:
		agent.last_award_time = -1000.0
		agent.last_collision_time = -1000.0
		if traffic.active_agents.has(agent):
			traffic.active_agents.erase(agent)
			traffic.agent_despawned.emit(agent)
		agent.visible = false
		agent.collision_layer = 0
		agent.global_position = Vector3(300, -50, 0)
	var cars: Array = sc["cars"]
	for i in cars.size():
		var agent := agents[i]
		agent.global_transform = Transform3D(Basis.IDENTITY, cars[i])
		agent.forward_vec = Vector3.FORWARD
		agent.right_vec = Vector3.RIGHT
		agent.velocity_vec = Vector3.ZERO
		agent.speed = 0.0
		agent.visible = true
		agent.collision_layer = TrafficAgent.TRAFFIC_LAYER
		traffic.active_agents.append(agent)
	# Start 20 m behind the origin already at speed.
	tuk.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 20)))
	tuk.linear_velocity = Vector3(0, 0, -float(sc["speed"]) / 3.6)


func _physics_process(_delta: float) -> void:
	if _index < 0 or _index >= _scenarios.size():
		return
	var sc: Dictionary = _scenarios[_index]
	var target := float(sc["speed"])
	var err := target - tuk.speed_kmh
	tuk.input.throttle = clampf(err * 0.4 + 0.3, 0.0, 1.0) if err > -1.0 else 0.0
	tuk.input.brake = 0.0
	# Hold the centre line x = 0.
	tuk.input.steer = clampf(-(tuk.global_position.x * 0.8 + tuk.linear_velocity.x * 0.5), -1.0, 1.0)
	_t += 1.0 / 60.0
	var last_car_z := 0.0
	for c in sc["cars"]:
		last_car_z = minf(last_car_z, (c as Vector3).z)
	if tuk.global_position.z < last_car_z - 25.0 or _t > 20.0:
		_evaluate(sc)
		_next()


func _evaluate(sc: Dictionary) -> void:
	var close := 0
	var gap := 0
	for e in _events:
		if e.type == SkillEvent.Type.TIGHT_GAP:
			gap += 1
		else:
			close += 1
	var expect: Dictionary = sc["expect"]
	var ok := true
	var detail := "close %d gap %d collisions %d resets %d awards %s | t=%.1f tuk z=%.1f x=%.2f v=%.1f rej c%d s%d e%d col%d" % [close, gap, _collisions, _combo_resets, _awards, _t, tuk.global_position.z, tuk.global_position.x, tuk.speed_kmh, detector.rejected_clearance, detector.rejected_speed, detector.expired, detector.rejected_collision]
	if expect.has("close") and close != int(expect["close"]):
		ok = false
	if expect.has("min_close") and close < int(expect["min_close"]):
		ok = false
	if expect.has("gap") and gap != int(expect["gap"]):
		ok = false
	if expect.has("multipliers"):
		var mults: Array = expect["multipliers"]
		for i in mults.size():
			if i >= _awards.size() or _awards[i].y != int(mults[i]):
				ok = false
	if expect.has("collision") and (_collisions > 0) != bool(expect["collision"]):
		ok = false
	if expect.has("reset") and (_combo_resets > 0) != bool(expect["reset"]):
		ok = false
	print("[%s] %s\n       %s" % ["PASS" if ok else "FAIL", sc["name"], detail])
	if not ok:
		_failures += 1


func _finish() -> void:
	print("=== SCORING SCENARIOS: %s (%d failed) ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
