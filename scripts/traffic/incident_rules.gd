class_name IncidentRules
extends RefCounted
## Pure decision rules for traffic collision reactions (unit tested).
## Severity dominates; temperament shifts the odds. `roll` values are uniform
## 0–1 numbers supplied by the caller (seeded RNG in game, fixed in tests).

enum Tier { NONE, LIGHT, MODERATE, MAJOR }
enum Response { HORN_ONLY, SHOUT_ONLY, STOP_AND_HONK, STOP_AND_EXIT }


## Only TRAFFIC collisions can become incidents; walls, kerbs and rollovers never do.
static func tier_for(event: CollisionEvent, cfg: IncidentConfig) -> Tier:
	if event == null or event.kind != CollisionEvent.Kind.TRAFFIC or event.other_agent_id < 0:
		return Tier.NONE
	if event.severity == CollisionEvent.Severity.MAJOR:
		return Tier.MAJOR
	return Tier.MODERATE if event.impact_speed_kmh() >= cfg.moderate_min_kmh else Tier.LIGHT


static func response(tier: Tier, t: DriverTemperament, cfg: IncidentConfig, roll_a: float, roll_b: float) -> Response:
	match tier:
		Tier.LIGHT:
			if roll_b < t.escalate_light_chance:
				return Response.STOP_AND_HONK
			return Response.HORN_ONLY if roll_a < t.horn_chance else Response.SHOUT_ONLY
		Tier.MODERATE:
			return Response.STOP_AND_EXIT if roll_a < t.exit_chance_moderate else Response.STOP_AND_HONK
		Tier.MAJOR:
			var p := maxf(t.exit_chance_major, cfg.major_min_exit_chance)
			return Response.STOP_AND_EXIT if roll_a < p else Response.STOP_AND_HONK
	return Response.SHOUT_ONLY


static func argue_seconds(tier: Tier, t: DriverTemperament, cfg: IncidentConfig, roll: float) -> float:
	var base := lerpf(t.argue_seconds.x, t.argue_seconds.y, clampf(roll, 0.0, 1.0))
	return base * (cfg.major_argue_scale if tier == Tier.MAJOR else cfg.moderate_argue_scale)


static func pick_temperament(cfg: IncidentConfig, roll: float) -> DriverTemperament:
	var total := 0.0
	for t in cfg.temperaments:
		total += t.weight
	if cfg.temperaments.is_empty() or total <= 0.0:
		return DriverTemperament.new()
	var r := clampf(roll, 0.0, 0.9999) * total
	for t in cfg.temperaments:
		r -= t.weight
		if r < 0.0:
			return t
	return cfg.temperaments[cfg.temperaments.size() - 1]
