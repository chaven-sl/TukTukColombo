extends "res://tests/test_case.gd"
## v0.04 upgrade modifier layer: modest, believable, base untouched.

var base: VehicleTuning = load("res://resources/vehicles/tuk_player_tuning.tres")


func _levels(n: int) -> Dictionary:
	var d := UpgradeCatalog.empty_levels()
	for k in d.keys():
		d[k] = n
	return d


func test_level0_equals_base() -> void:
	var t := EffectiveVehicleConfig.build(base, _levels(0))
	for p in ["top_speed_kmh", "brake_force", "steering_response", "damping_front"]:
		check_near(t.get(p), base.get(p), 0.0001, "%s unchanged at level 0" % p)


func test_base_resource_never_mutated() -> void:
	var before := [base.top_speed_kmh, base.brake_force, base.steering_response, base.damping_front]
	EffectiveVehicleConfig.build(base, _levels(5))
	check_eq([base.top_speed_kmh, base.brake_force, base.steering_response, base.damping_front], before, "base tuning untouched")


func test_engine_effect_and_bounds() -> void:
	var t := EffectiveVehicleConfig.build(base, {"engine": 5})
	check(t.top_speed_kmh > base.top_speed_kmh, "faster top speed")
	check(t.top_speed_kmh >= 78.0 and t.top_speed_kmh <= 85.0, "level 5 top speed ~80–85 km/h (%.1f)" % t.top_speed_kmh)
	check(t.drive_force > base.drive_force and t.drive_force <= base.drive_force * 1.25, "stronger, not absurd, acceleration")


func test_brake_effect_and_bounds() -> void:
	var t := EffectiveVehicleConfig.build(base, {"brakes": 5})
	check(t.brake_force > base.brake_force, "stronger brakes")
	check(t.brake_force <= base.brake_force * 1.4, "modest (≤ +40 %%: %.0f → %.0f N)" % [base.brake_force, t.brake_force])


func test_handling_keeps_roll_and_rollover() -> void:
	var t := EffectiveVehicleConfig.build(base, _levels(5))
	check(t.steering_response > base.steering_response, "sharper steering response")
	check(t.steering_response <= base.steering_response * 1.3, "steering response within bounds")
	for p in ["roll_assist_low_speed", "roll_assist_high_speed", "roll_assist_damping", "roll_assist_cutoff_deg", "mass_kg",
			"tyre_grip", "max_steer_angle_deg", "inside_wheel_light_load"]:
		check_eq(t.get(p), base.get(p), "%s untouched (roll / rollover behaviour preserved)" % p)
	check_eq(t.center_of_mass, base.center_of_mass, "centre of mass untouched")


func test_suspension_effect_and_bounds() -> void:
	var t := EffectiveVehicleConfig.build(base, {"suspension": 5})
	check(t.damping_front > base.damping_front and t.damping_front <= base.damping_front * 1.3, "more damping, modest")
	check(t.bump_stop_stiffness > base.bump_stop_stiffness, "firmer bump stops (kerb/landing composure)")
	check_near(t.suspension_travel, base.suspension_travel, 0.0001, "travel unchanged (not an off-roader)")


func test_upgrade_definitions_well_formed() -> void:
	for def in UpgradeCatalog.all():
		check_eq(def.max_level, 5, "%s has 5 levels" % def.id)
		check_eq(def.costs.size(), 5, "%s has 5 costs" % def.id)
		var rising := true
		for i in range(1, def.costs.size()):
			rising = rising and def.costs[i] > def.costs[i - 1]
		check(rising, "%s costs rise each level" % def.id)
		check(def.fields.size() == def.per_level.size() and def.fields.size() == def.modes.size(), "%s effect arrays line up" % def.id)
		for f in def.fields:
			check(not EffectiveVehicleConfig.PROTECTED.has(f), "%s never touches protected %s" % [def.id, f])
