class_name PerfSections
extends RefCounted
## Debug-only section profiler (v0.03B1). Microsecond timers around the major
## per-frame update paths; a no-op (one bool check) unless a performance run
## enables it. Fixed-size sample rings: no allocations while recording.
##
##   var t := PerfSections.begin()
##   … work …
##   PerfSections.end(PerfSections.HUMAN_LOGIC, t)

enum { HUMAN_LOGIC, HUMAN_PRESENTATION, TRAFFIC, HERO_VISUAL, AUDIO, GPS, HUD, NOTIFICATIONS,
	DAMAGE_RECOVERY, INCIDENTS, PROPS, CAMERA, PLAYER_PHYSICS, COUNT }
const NAMES := ["human_logic", "human_presentation", "traffic", "hero_visual", "audio", "gps", "hud",
	"notifications", "damage_recovery", "incidents", "props", "camera", "player_physics"]
const RING := 4096

static var enabled := false
static var _sum := PackedFloat64Array()
static var _count := PackedInt32Array()
static var _samples := PackedFloat32Array()  # COUNT × RING, flat
static var _write := PackedInt32Array()


static func start() -> void:
	_sum.resize(COUNT)
	_sum.fill(0.0)
	_count.resize(COUNT)
	_count.fill(0)
	_write.resize(COUNT)
	_write.fill(0)
	_samples.resize(COUNT * RING)
	enabled = true


static func stop() -> void:
	enabled = false


static func begin() -> int:
	return Time.get_ticks_usec() if enabled else 0


static func end(section: int, started: int) -> void:
	if not enabled:
		return
	add(section, float(Time.get_ticks_usec() - started))


## Adds an already-measured duration (µs), e.g. a sub-part of a loop.
static func add(section: int, us: float) -> void:
	if not enabled:
		return
	_sum[section] += us
	_count[section] += 1
	_samples[section * RING + _write[section]] = us
	_write[section] = (_write[section] + 1) % RING


## {name: {"mean_ms", "p95_ms", "calls"}} for every section that ran.
static func summary() -> Dictionary:
	var out := {}
	for i in mini(COUNT, _count.size()):
		var n := _count[i]
		if n == 0:
			continue
		var m := mini(n, RING)
		var s := _samples.slice(i * RING, i * RING + m)
		s.sort()
		out[NAMES[i]] = {"mean_ms": snappedf(_sum[i] / n / 1000.0, 0.001),
				"p95_ms": snappedf(s[mini(int(m * 0.95), m - 1)] / 1000.0, 0.001), "calls": n}
	return out
