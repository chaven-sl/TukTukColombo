class_name TouchSteeringMapper
extends RefCounted
## Pure mapping from a thumb's horizontal offset to the abstract steer value
## (−1 … +1). v0.03A1: the offset is measured from the touch-down point
## (floating origin), not from the pad centre — a thumb resting slightly off
## centre no longer steers. Crossing back over the origin reverses steering
## immediately with no re-centre step. No smoothing here — the vehicle's own
## approved steering response does that.


static func map(offset_x: float, full_lock_travel: float, config: TouchControlsConfig) -> float:
	if full_lock_travel <= 0.0:
		return 0.0
	var n := clampf(offset_x / full_lock_travel, -1.0, 1.0)
	var magnitude := absf(n)
	if magnitude <= config.steer_dead_zone:
		return 0.0
	var t := (magnitude - config.steer_dead_zone) / (1.0 - config.steer_dead_zone)
	return signf(n) * pow(clampf(t, 0.0, 1.0), config.steer_exponent)
