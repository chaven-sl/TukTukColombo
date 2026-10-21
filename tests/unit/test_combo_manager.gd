extends "res://tests/test_case.gd"


func test_multiplier_progression_caps_at_five() -> void:
	var combo := ComboManager.new(5, 3.0)
	check_eq(combo.multiplier(), 1, "idle multiplier is 1x")
	var expected := [25, 50, 75, 100, 125, 125, 125]
	for i in expected.size():
		check_eq(combo.register_event(25), expected[i], "award %d" % (i + 1))
	check_eq(combo.multiplier(), 5, "multiplier capped at 5x")
	check_eq(combo.chain, 7, "chain keeps counting past the cap")


func test_tight_gap_uses_current_multiplier() -> void:
	var combo := ComboManager.new(5, 3.0)
	combo.register_event(25)
	combo.register_event(25)
	check_eq(combo.register_event(50), 150, "TIGHT GAP x3 = 150")


func test_timeout_resets_combo() -> void:
	var combo := ComboManager.new(5, 3.0)
	combo.register_event(25)
	check(not combo.update(2.9), "still alive at 2.9 s")
	check(combo.update(0.2), "expires after 3.0 s")
	check_eq(combo.chain, 0, "chain cleared")
	check_eq(combo.multiplier(), 1, "back to 1x")
	check(not combo.update(1.0), "idle update reports nothing")


func test_event_refreshes_timeout() -> void:
	var combo := ComboManager.new(5, 3.0)
	combo.register_event(25)
	combo.update(2.5)
	combo.register_event(25)
	check_near(combo.time_left, 3.0, 0.0001, "timer refreshed")
	check(not combo.update(2.9), "refreshed combo survives")
	check_eq(combo.multiplier(), 2, "still 2x")


func test_reset_on_collision() -> void:
	var combo := ComboManager.new(5, 3.0)
	check(not combo.reset(), "reset with no combo returns false")
	combo.register_event(25)
	combo.register_event(25)
	check(combo.reset(), "reset reports an active combo")
	check_eq(combo.chain, 0, "chain cleared")
	check_eq(combo.register_event(25), 25, "fresh combo starts at 1x")
