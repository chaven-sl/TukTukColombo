class_name AudioLibrary
extends RefCounted
## Loads the procedural first-pass sounds (tools/audiogen) and marks loops.

const DIR := "res://assets/audio/sfx/%s.wav"
const LOOPS := ["tuk_engine_idle", "tuk_engine_load", "tyre_road", "bus_rumble", "amb_city", "amb_crowd", "amb_market", "rail_clatter"]

static var _cache: Dictionary = {}


static func get_stream(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var s := load(DIR % sound) as AudioStreamWAV
	if s != null and LOOPS.has(sound):
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	_cache[sound] = s
	return s


## A 2D player on `bus` (added to `parent`).
static func player_2d(parent: Node, sound: String, bus: StringName, volume_db: float = 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = get_stream(sound)
	p.bus = bus
	p.volume_db = volume_db
	parent.add_child(p)
	return p


## A positional player on `bus` with a sensible urban falloff.
static func player_3d(parent: Node, sound: String, bus: StringName, max_distance: float = 60.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_stream(sound) if not sound.is_empty() else null
	p.bus = bus
	p.max_distance = max_distance
	p.unit_size = 8.0
	p.attenuation_filter_cutoff_hz = 8000.0
	parent.add_child(p)
	return p
