class_name TouchSteeringMapper
extends RefCounted
## Pure mapping from a thumb's horizontal offset on the steering pad to the
## abstract steer value (−1 … +1). Absolute (not relative-to-touch-down): the
## thumb's position IS the steering, so crossing from left to right reverses
## steering immediately with no re-centre step. No smoothing here — the
## vehicle's own approved steering response does that.


static func map(offset_x: float, half_width: float, config: TouchControlsConfig) -> float:
	if half_width <= 0.0:
		return 0.0
	var n := clampf(offset_x / (half_width * config.full_lock_fraction), -1.0, 1.0)
	var magnitude := absf(n)
	if magnitude <= config.steer_dead_zone:
		return 0.0
	var t := (magnitude - config.steer_dead_zone) / (1.0 - config.steer_dead_zone)
	return signf(n) * pow(clampf(t, 0.0, 1.0), config.steer_exponent)
