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

var monitor: SessionPerformanceMonitor
var player: TukController
var network: RoadNetwork
var traffic: TrafficManager
var running := false
var duration := DEFAULT_SECONDS
var _t := 0.0
var _autopilot: AutopilotDriver


static func requested_seconds() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg == "--perf-test":
			return DEFAULT_SECONDS
		if arg.begins_with("--perf-test="):
			return float(arg.get_slice("=", 1))
	if FileAccess.file_exists(FLAG):
		var text := FileAccess.get_file_as_string(FLAG).strip_edges()
		DirAccess.remove_absolute(FLAG)
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
	monitor.start()
	running = true
	print("[DevicePerfTest] started (%.0f s)" % seconds)


func _process(delta: float) -> void:
	if not running or get_tree().paused:
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
