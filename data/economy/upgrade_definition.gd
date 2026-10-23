class_name UpgradeDefinition
extends Resource
## One upgrade category (v0.04): ENGINE / BRAKES / HANDLING / SUSPENSION.
## Effects are expressed against the BASE VehicleTuning — the controller's
## physics stays the source of truth; EffectiveVehicleConfig applies these
## on a copy. Nothing here touches body roll, roll assist or rollover.

@export var id: StringName = &""
@export var display_key := ""
@export var description_key := ""
## Player-facing stat bar label (SPEED / BRAKING / HANDLING / SUSPENSION).
@export var stat_key := ""
@export var max_level := 5
## Cost to buy level 1…max_level (Rs.). PROTOTYPE BASELINE (economy sim).
@export var costs := PackedInt32Array([1800, 3000, 4800, 7000, 10000])
## VehicleTuning field names this upgrade modifies.
@export var fields := PackedStringArray()
## Per-level change for each field: a fraction (0.06 = +6 % per level) when
## the matching mode is "mul", an absolute amount when "add".
@export var per_level := PackedFloat32Array()
@export var modes := PackedStringArray()
## Human-readable improvement per level, e.g. "+2.5 km/h top speed" (key).
@export var improvement_key := ""


func cost_for_level(level: int) -> int:
	return costs[level - 1] if level >= 1 and level <= costs.size() else -1
