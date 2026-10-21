class_name SimClock
extends RefCounted
## Deterministic simulation time derived from the physics frame counter.
## Use it for gameplay timestamps (cooldowns, collision times) so headless
## fixed-step tests behave exactly like real-time play.


static func now() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
