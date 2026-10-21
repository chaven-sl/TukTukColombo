class_name AdaptiveTrafficBudget
extends RefCounted
## Decides how many traffic agents the device can afford.
##
##   actual_target = min(gameplay_density_target, performance_ceiling)
##
## FPS is averaged over short windows. The ceiling steps DOWN only after FPS
## stays below the low threshold for low_sustain_seconds, and steps UP only
## after FPS stays above the high threshold for (longer) high_sustain_seconds.
## The band between thresholds resets both timers, and a cooldown separates
## changes, so population never oscillates frame to frame.

signal changed(performance_ceiling: int, actual_target: int)

var config: TrafficBudgetConfig
var gameplay_density_target := 14
var performance_ceiling := 14
var window_fps := 60.0

var _window_time := 0.0
var _window_frames := 0
var _low_time := 0.0
var _high_time := 0.0
var _cooldown := 0.0


func _init(p_config: TrafficBudgetConfig = null, density_target: int = 14) -> void:
	config = p_config if p_config != null else TrafficBudgetConfig.new()
	gameplay_density_target = density_target
	performance_ceiling = clampi(config.initial_ceiling, config.min_ceiling, config.max_ceiling)


func get_actual_target() -> int:
	return mini(gameplay_density_target, performance_ceiling)


func set_density_target(target: int) -> void:
	gameplay_density_target = target
	changed.emit(performance_ceiling, get_actual_target())


## Feed every rendered frame's delta.
func push_frame(delta: float) -> void:
	_window_time += delta
	_window_frames += 1
	if _window_time < config.sample_window:
		return
	window_fps = float(_window_frames) / _window_time
	_evaluate(_window_time, window_fps)
	_window_time = 0.0
	_window_frames = 0


func _evaluate(dt: float, fps: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)
	if fps < config.low_fps_threshold:
		_low_time += dt
		_high_time = 0.0
	elif fps > config.high_fps_threshold:
		_high_time += dt
		_low_time = 0.0
	else:
		_low_time = 0.0
		_high_time = 0.0
	if _cooldown > 0.0:
		return
	if _low_time >= config.low_sustain_seconds and performance_ceiling > config.min_ceiling:
		performance_ceiling = maxi(performance_ceiling - config.step_down, config.min_ceiling)
		_after_change()
	elif _high_time >= config.high_sustain_seconds and performance_ceiling < config.max_ceiling:
		performance_ceiling = mini(performance_ceiling + config.step_up, config.max_ceiling)
		_after_change()


func _after_change() -> void:
	_low_time = 0.0
	_high_time = 0.0
	_cooldown = config.change_cooldown
	changed.emit(performance_ceiling, get_actual_target())
