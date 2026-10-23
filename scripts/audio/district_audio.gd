class_name DistrictAudio
extends Node3D
## First coherent audio layer (v0.03B) — presentation only. READS telemetry
## and EventBus hooks; never writes gameplay state, never inside physics.
##
##   TukAudio      engine idle/load loops pitched by speed & throttle, tyres
##   Traffic       pooled 3D voices (4): nearest bus rumble, bike passes,
##                 occasional zone-weighted horns, incident horns & shouts
##   Ambience      city / crowd / market beds crossfaded by zone; rail
##                 clatter + train horn behind the station; vendor calls
##   Events        player horn, collisions (thud / crash + ambience duck),
##                 prop knocks, passenger reactions
## Priority (brief): player engine > player collision > passenger > major
## incident > near traffic > ambience > distant detail — enforced by fixed
## pools, cooldowns, range limits and ducking the Ambience bus on crashes.

const POOL := 4

var player: TukController
var traffic: TrafficManager
var network: RoadNetwork
var rng := RandomNumberGenerator.new()

var _idle: AudioStreamPlayer
var _load: AudioStreamPlayer
var _tyre: AudioStreamPlayer
var _horn: AudioStreamPlayer
var _impact: AudioStreamPlayer
var _passenger: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer3D] = []
var _rumble: AudioStreamPlayer3D
var _rumble_target: TrafficAgent = null
var _beds: Dictionary = {}  # zone bed name -> AudioStreamPlayer
var _rail: AudioStreamPlayer3D
var _train: AudioStreamPlayer3D
var _vendor: AudioStreamPlayer3D
var _zone_samples: Array = []  # [Vector3, StringName]
var _zone: StringName = &"station"
var _scan_timer := 0.0
var _horn_timer := 4.0
var _train_timer := 20.0
var _vendor_timer := 10.0
var _bike_cooldown: Dictionary = {}
var _throttle_prev := 0.0
var _lift := 0.0
var _duck := 0.0
## Diagnostics.
var stats := {"horns": 0, "shouts": 0, "impacts": 0, "bike_passes": 0, "trains": 0, "vendor_calls": 0}


func setup(p_player: TukController, p_traffic: TrafficManager, p_network: RoadNetwork) -> void:
	player = p_player
	traffic = p_traffic
	network = p_network
	rng.seed = 77
	_idle = AudioLibrary.player_2d(self, "tuk_engine_idle", &"Vehicle", -8.0)
	_load = AudioLibrary.player_2d(self, "tuk_engine_load", &"Vehicle", -30.0)
	_tyre = AudioLibrary.player_2d(self, "tyre_road", &"Vehicle", -40.0)
	_horn = AudioLibrary.player_2d(self, "horn_tuk", &"Vehicle", -3.0)
	_impact = AudioLibrary.player_2d(self, "collision_thud", &"Vehicle", 0.0)
	_passenger = AudioLibrary.player_2d(self, "passenger_react", &"Vehicle", -10.0)
	for p in [_idle, _load, _tyre]:
		p.play()
	for i in POOL:
		_pool.append(AudioLibrary.player_3d(self, "", &"Traffic", 70.0))
	_rumble = AudioLibrary.player_3d(self, "bus_rumble", &"Traffic", 45.0)
	for bed: String in ["amb_city", "amb_crowd", "amb_market"]:
		var b := AudioLibrary.player_2d(self, bed, &"Ambience", -60.0)
		b.play(rng.randf() * 5.0)
		_beds[bed] = b
	_vendor = AudioLibrary.player_3d(self, "vendor_call", &"Ambience", 50.0)
	_build_zone_samples()
	_place_station_sounds()
	EventBus.horn_sounded.connect(func(_p: Vector3) -> void:
		_horn.play()
		stats["horns"] += 1)
	EventBus.collision_event.connect(_on_collision)
	EventBus.traffic_horn.connect(_on_traffic_horn)
	EventBus.driver_shout.connect(func(at: Vector3, _k: String) -> void:
		_one_shot("driver_shout", at, -2.0)
		stats["shouts"] += 1)
	EventBus.prop_knocked.connect(func(at: Vector3, _k: int) -> void: _one_shot("prop_knock", at, -4.0))
	EventBus.passenger_reaction.connect(func(_k: String, _id: StringName) -> void: _passenger.play())


func _build_zone_samples() -> void:
	for seg in network.segments:
		var n := maxi(2, int(seg.length / 12.0))
		for k in n:
			var s := seg.length * float(k) / float(n - 1)
			_zone_samples.append([seg.global_transform * seg.local_center(s), seg.zone])


func _place_station_sounds() -> void:
	for seg in network.segments:
		if seg.name != "StationFrontage":
			continue
		var behind := seg.global_transform * (seg.local_center(90.0) + seg.local_right(90.0) * -40.0)
		_rail = AudioLibrary.player_3d(self, "rail_clatter", &"Ambience", 140.0)
		_rail.global_position = behind
		_rail.volume_db = -14.0
		_rail.play()
		_train = AudioLibrary.player_3d(self, "train_horn", &"Ambience", 260.0)
		_train.global_position = behind
		_train.volume_db = -4.0


func _one_shot(sound: String, at: Vector3, volume_db: float) -> bool:
	if player.global_position.distance_to(at) > 70.0:
		return false  # distant detail: skip rather than steal a voice
	for p in _pool:
		if not p.playing:
			p.stream = AudioLibrary.get_stream(sound)
			p.volume_db = volume_db
			p.pitch_scale = rng.randf_range(0.95, 1.05)
			p.global_position = at
			p.play()
			return true
	return false


func _on_collision(e: CollisionEvent) -> void:
	if e.kind == CollisionEvent.Kind.ROLLOVER:
		return
	var major := e.severity == CollisionEvent.Severity.MAJOR
	_impact.stream = AudioLibrary.get_stream("collision_crash" if major else ("scrape" if e.impact_speed_kmh() < 10.0 else "collision_thud"))
	_impact.volume_db = 0.0 if major else -5.0
	_impact.play()
	stats["impacts"] += 1
	if major:
		_duck = 1.6  # the crash owns the mix for a moment


func _on_traffic_horn(at: Vector3, pattern: int) -> void:
	match pattern:
		TrafficIncidentManager.Horn.REPEATED:
			_one_shot("horn_repeated", at, -1.0)
		TrafficIncidentManager.Horn.ANGRY:
			_one_shot("horn_car", at, -2.0)
		_:
			_one_shot(["horn_tuk", "horn_bike", "horn_car"][rng.randi() % 3], at, -8.0)
	stats["horns"] += 1


func _process(delta: float) -> void:
	if player == null:
		return
	_engine(delta)
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.4
		_scan_traffic()
		_update_zone()
	_ambience(delta)
	_ambient_horns(delta)
	_station_and_market(delta)


func _engine(delta: float) -> void:
	var kmh := player.speed_kmh
	var thr := player.input.throttle
	if _throttle_prev > 0.5 and thr < 0.1 and kmh > 15.0:
		_lift = 0.5  # throttle lift: the note drops away for a moment
	_throttle_prev = thr
	_lift = maxf(_lift - delta, 0.0)
	var load := clampf(thr * 0.75 + kmh / 60.0 * 0.45 - _lift, 0.0, 1.0)
	_idle.volume_db = lerpf(-7.0, -26.0, load)
	_idle.pitch_scale = 0.92 + clampf(kmh / 70.0, 0.0, 1.0) * 0.5
	_load.volume_db = lerpf(-34.0, -3.0, load)
	_load.pitch_scale = clampf(0.72 + kmh / 60.0 * 0.95, 0.72, 1.85)
	_tyre.volume_db = lerpf(-42.0, -15.0, clampf(kmh / 60.0, 0.0, 1.0))
	_tyre.pitch_scale = 0.8 + clampf(kmh / 80.0, 0.0, 1.0) * 0.5


func _scan_traffic() -> void:
	var best: TrafficAgent = null
	var best_d := 35.0
	var now := SimClock.now()
	for a in traffic.active_agents:
		var d := a.global_position.distance_to(player.global_position)
		if a.vehicle_class.kind == TrafficVehicleClass.Kind.BUS and d < best_d:
			best_d = d
			best = a
		if a.vehicle_class.kind == TrafficVehicleClass.Kind.MOTORCYCLE and d < 7.0 and a.speed > 5.0:
			if now - float(_bike_cooldown.get(a.agent_id, -100.0)) > 4.0:
				_bike_cooldown[a.agent_id] = now
				if _one_shot("bike_pass", a.global_position, -6.0):
					stats["bike_passes"] += 1
	_rumble_target = best
	if best != null and not _rumble.playing:
		_rumble.play()
	elif best == null and _rumble.playing:
		_rumble.stop()


func _update_zone() -> void:
	var best_d := INF
	for z: Array in _zone_samples:
		var d := (z[0] as Vector3).distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			_zone = z[1]


const ZONE_MIX := {
	&"station": [0.7, 0.85, 0.1], &"olcott": [1.0, 0.75, 0.2], &"market": [0.5, 0.65, 1.0],
	&"junction": [0.9, 0.6, 0.4], &"service": [0.6, 0.2, 0.0],
}


func _ambience(delta: float) -> void:
	if _rumble_target != null:
		_rumble.global_position = _rumble_target.global_position
	_duck = maxf(_duck - delta, 0.0)
	var mix: Array = ZONE_MIX.get(_zone, [0.8, 0.5, 0.2])
	var names := ["amb_city", "amb_crowd", "amb_market"]
	for i in 3:
		var target_db := linear_to_db(maxf(float(mix[i]), 0.001)) - 4.0 - _duck * 5.0
		var b: AudioStreamPlayer = _beds[names[i]]
		b.volume_db = move_toward(b.volume_db, target_db, delta * 12.0)


func _ambient_horns(delta: float) -> void:
	_horn_timer -= delta
	if _horn_timer > 0.0:
		return
	var busy := 1.8 if _zone == &"market" or _zone == &"olcott" else 1.0
	_horn_timer = rng.randf_range(3.0, 8.0) / busy
	if traffic.active_agents.is_empty():
		return
	var a := traffic.active_agents[rng.randi() % traffic.active_agents.size()]
	if a.global_position.distance_to(player.global_position) > 45.0:
		return
	var sound := "horn_car"
	match a.vehicle_class.kind:
		TrafficVehicleClass.Kind.BUS:
			sound = "horn_bus"
		TrafficVehicleClass.Kind.TUK:
			sound = "horn_tuk"
		TrafficVehicleClass.Kind.MOTORCYCLE:
			sound = "horn_bike"
	if _one_shot(sound, a.global_position, -10.0):
		stats["horns"] += 1


func _station_and_market(delta: float) -> void:
	_train_timer -= delta
	if _train_timer <= 0.0 and _train != null:
		_train_timer = rng.randf_range(35.0, 70.0)
		_train.play()
		stats["trains"] += 1
	_vendor_timer -= delta
	if _vendor_timer <= 0.0:
		_vendor_timer = rng.randf_range(12.0, 25.0)
		if _zone == &"market" or _zone == &"station":
			var fwd := -player.global_transform.basis.z
			var side := fwd.cross(Vector3.UP) * (8.0 if rng.randf() < 0.5 else -8.0)
			_vendor.global_position = player.global_position + fwd * 15.0 + side
			_vendor.pitch_scale = rng.randf_range(0.9, 1.15)
			_vendor.play()
			stats["vendor_calls"] += 1
