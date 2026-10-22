class_name SessionPerformanceMonitor
extends Node
## Lightweight in-build performance recorder for device testing (not
## production telemetry). Frame times go into a preallocated ring buffer; once
## per second it samples traffic/human counts, draw calls and memory. No
## allocations per frame. summary() computes FPS stats (km/h not involved).

const CAPACITY := 36000  # 10 minutes at 60 FPS

var traffic: TrafficManager
var humans: HumanManager
var recording := false

var _frames := PackedFloat32Array()
var _count := 0
var _write := 0
var _second_accum := 0.0
var _second_frames := 0
var _second_fps := PackedFloat32Array()
var _elapsed := 0.0
var _traffic_min := 999
var _traffic_max := 0
var _ceiling_min := 999
var _ceiling_max := 0
var _humans_min := 999
var _humans_max := 0
var _draw_calls_sum := 0.0
var _draw_samples := 0
var _memory_peak := 0.0
var _budget_changes := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_frames.resize(CAPACITY)
	EventBus.performance_budget_changed.connect(func(_c: int, _t: int) -> void:
		if recording:
			_budget_changes += 1)


func start() -> void:
	_count = 0
	_write = 0
	_elapsed = 0.0
	_second_accum = 0.0
	_second_frames = 0
	_second_fps.clear()
	_traffic_min = 999
	_traffic_max = 0
	_ceiling_min = 999
	_ceiling_max = 0
	_humans_min = 999
	_humans_max = 0
	_draw_calls_sum = 0.0
	_draw_samples = 0
	_memory_peak = 0.0
	_budget_changes = 0
	recording = true


func stop() -> void:
	recording = false


func _process(delta: float) -> void:
	if not recording or get_tree().paused:
		return
	_frames[_write] = delta
	_write = (_write + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)
	_elapsed += delta
	_second_accum += delta
	_second_frames += 1
	if _second_accum >= 1.0:
		_second_fps.append(_second_frames / _second_accum)
		_second_accum = 0.0
		_second_frames = 0
		_sample_world()


func _sample_world() -> void:
	if traffic != null:
		var n := traffic.active_agents.size()
		_traffic_min = mini(_traffic_min, n)
		_traffic_max = maxi(_traffic_max, n)
		if traffic.budget != null:
			_ceiling_min = mini(_ceiling_min, traffic.budget.performance_ceiling)
			_ceiling_max = maxi(_ceiling_max, traffic.budget.performance_ceiling)
	if humans != null:
		_humans_min = mini(_humans_min, humans.active.size())
		_humans_max = maxi(_humans_max, humans.active.size())
	_draw_calls_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_draw_samples += 1
	_memory_peak = maxf(_memory_peak, Performance.get_monitor(Performance.MEMORY_STATIC))


func summary() -> Dictionary:
	if _count == 0:
		return {}
	var sorted := PackedFloat32Array()
	sorted.resize(_count)
	var total := 0.0
	for i in _count:
		sorted[i] = _frames[i]
		total += _frames[i]
	sorted.sort()
	var mean_frame := total / _count
	var p95_frame := sorted[mini(int(_count * 0.95), _count - 1)]
	var p5_fps := 1.0 / maxf(sorted[mini(int(_count * 0.95), _count - 1)], 0.0001)
	var min_stable := INF
	for f in _second_fps:
		min_stable = minf(min_stable, f)
	return {
		"seconds": snappedf(_elapsed, 0.1),
		"frames": _count,
		"fps_avg": snappedf(1.0 / maxf(mean_frame, 0.0001), 0.1),
		"fps_p5": snappedf(p5_fps, 0.1),
		"fps_min_stable_1s": snappedf(min_stable if min_stable != INF else 0.0, 0.1),
		"frame_ms_avg": snappedf(mean_frame * 1000.0, 0.01),
		"frame_ms_p95": snappedf(p95_frame * 1000.0, 0.01),
		"traffic_active_range": [_traffic_min, _traffic_max],
		"traffic_ceiling_range": [_ceiling_min, _ceiling_max],
		"budget_changes": _budget_changes,
		"humans_active_range": [_humans_min, _humans_max],
		"humans_peak": _humans_max,
		"draw_calls_avg": snappedf(_draw_calls_sum / maxf(_draw_samples, 1.0), 0.1),
		"memory_static_peak_mb": snappedf(_memory_peak / 1048576.0, 0.1),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"resolution": "%dx%d" % [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"window_size": "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"device_model": OS.get_model_name(),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"video_api": RenderingServer.get_video_adapter_api_version(),
	}


func save_summary(tag: String) -> String:
	var data := summary()
	DirAccess.make_dir_recursive_absolute("user://perf")
	var path := "user://perf/%s.json" % tag
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	print("[PerfMonitor] %s %s" % [tag, JSON.stringify(data)])
	return path
