class_name EffectiveVehicleConfig
extends RefCounted
## Upgrade modifier layer (v0.04). Builds the tuning the tuk actually drives
## with: a COPY of the base VehicleTuning with each upgrade's per-level
## effects applied. The base resource is never mutated, so tests can compare
## level 0 against level 5 and the approved handling baseline stays intact.
##
## Deliberately untouched by any upgrade: mass, centre of mass, inertia,
## body size, roll assist, roll cutoff, tyre grip — the tuk keeps its body
## roll, two-wheel behaviour and rollover risk (high agility + high
## consequence).

## Fields no upgrade may ever modify (tested).
const PROTECTED := ["mass_kg", "center_of_mass", "inertia", "body_size", "roll_assist_low_speed",
		"roll_assist_high_speed", "roll_assist_damping", "roll_assist_cutoff_deg", "tyre_grip",
		"front_grip_multiplier", "rear_grip_multiplier", "max_steer_angle_deg", "inside_wheel_light_load"]


## `levels`: {"engine": 0..5, …}. Returns a new VehicleTuning.
static func build(base: VehicleTuning, levels: Dictionary) -> VehicleTuning:
	var t := base.duplicate() as VehicleTuning
	for def in UpgradeCatalog.all():
		var level := clampi(int(levels.get(String(def.id), 0)), 0, def.max_level)
		if level == 0:
			continue
		for i in def.fields.size():
			var field := def.fields[i]
			if PROTECTED.has(field):
				push_error("[EffectiveVehicleConfig] %s may not modify %s" % [def.id, field])
				continue
			var value: float = t.get(field)
			if def.modes[i] == "add":
				value += def.per_level[i] * level
			else:
				value *= 1.0 + def.per_level[i] * level
			t.set(field, value)
	return t


## 0..1 relative stat for the garage bars (never raw physics values).
static func stat_fraction(levels: Dictionary, id: StringName) -> float:
	var def := UpgradeCatalog.get_def(id)
	# Base level shows as 1 bar of 6 so a stock tuk isn't "empty".
	return (1.0 + float(levels.get(String(id), 0))) / float(def.max_level + 1)
