class_name DevicePerfTest
extends Node
## Repeatable ~5-minute device benchmark: the normal world (traffic,
## pedestrians, crossings, passengers waiting) driven by the deterministic
## autopilot with fixed seeds, recorded by SessionPerformanceMonitor.
##
## Start it with any of:
##   - pause screen → "Performance test (5 min)" (debug builds)
##   - command line   -- --perf-test[=seconds]
##   - a flag file    user://perf_test.flag (contents = seconds, optional);
##     tools/android_perf_test.sh creates it with `adb shell run-as`.
## Results: user://perf/device_perf_test.json and a "[PerfMonitor]" log line
## (visible in logcat).

signal finished(summary: Dictionary)

const FLAG := "user://perf_test.flag"
const DEFAULT_SECONDS := 300.0
## Recording starts after this warm-up (first-frame sign bake / pipeline
## compiles are a load cost, not gameplay frame rate). The autopilot drives
## from the start. v0.03B; earlier device results included the warm-up.
const WARMUP_SECONDS := 3.0

var monitor: SessionPerformanceMonitor
var player: TukController
var network: RoadNetwork
var traffic: TrafficManager
var running := false
var duration := DEFAULT_SECONDS
var _t := 0.0
var _warmup := 0.0
var _autopilot: AutopilotDriver


## v0.03B1 A/B switches for the run (flag file: "<seconds> opt1,opt2").
static var options := PackedStringArray()


## True if a perf run was requested (does not consume the flag file).
static func is_requested() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf-test"):
			return true
	return FileAccess.file_exists(FLAG)


static func requested_seconds() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg == "--perf-test":
			return DEFAULT_SECONDS
		if arg.begins_with("--perf-options="):
			options = arg.get_slice("=", 1).split(",", false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf-test="):
			return float(arg.get_slice("=", 1))
	if FileAccess.file_exists(FLAG):
		var parts := FileAccess.get_file_as_string(FLAG).strip_edges().split(" ", false)
		DirAccess.remove_absolute(FLAG)
		var text := parts[0] if parts.size() > 0 else ""
		if parts.size() > 1:
			options = parts[1].split(",", false)
		return float(text) if text.is_valid_float() and float(text) > 0.0 else DEFAULT_SECONDS
	return 0.0


func begin(seconds: float) -> void:
	if running:
		return
	duration = seconds
	_t = 0.0
	_autopilot = AutopilotDriver.new()
	add_child(_autopilot)
	_autopilot.setup(player, network, traffic, 7)
	_warmup = WARMUP_SECONDS
	running = true
	print("[DevicePerfTest] started (%.0f s)" % seconds)


func _process(delta: float) -> void:
	if not running or get_tree().paused:
		return
	if _warmup > 0.0:
		_warmup -= delta
		if _warmup <= 0.0:
			monitor.start()
		return
	_t += delta
	if _t >= duration:
		running = false
		monitor.stop()
		_autopilot.queue_free()
		_autopilot = null
		var path := monitor.save_summary("device_perf_test")
		print("[DevicePerfTest] finished → %s" % ProjectSettings.globalize_path(path))
		finished.emit(monitor.summary())
