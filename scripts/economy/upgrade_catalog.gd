class_name UpgradeCatalog
extends RefCounted
## The four v0.04 upgrade categories, in garage order.

const IDS: Array[StringName] = [&"engine", &"brakes", &"handling", &"suspension"]

static var _defs: Dictionary = {}


static func get_def(id: StringName) -> UpgradeDefinition:
	if not _defs.has(id):
		_defs[id] = load("res://resources/economy/upgrade_%s.tres" % id) as UpgradeDefinition
	return _defs[id]


static func all() -> Array[UpgradeDefinition]:
	var out: Array[UpgradeDefinition] = []
	for id in IDS:
		out.append(get_def(id))
	return out


static func empty_levels() -> Dictionary:
	var d := {}
	for id in IDS:
		d[String(id)] = 0
	return d
