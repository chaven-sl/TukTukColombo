extends "res://tests/test_case.gd"
## v0.03B1: the graphics tiers the device actually runs, and that the
## documentation quotes the repository's real values (no report drift).

const TIERS := ["res://resources/platform/graphics_low.tres", "res://resources/platform/graphics_medium.tres",
		"res://resources/platform/graphics_high.tres"]


func test_tier_files_are_ordered_and_capped() -> void:
	for i in TIERS.size():
		var p := load(TIERS[i]) as GraphicsProfile
		check(p != null, "%s loads" % TIERS[i])
		if p == null:
			continue
		check_eq(int(p.tier), i, "%s tier index" % TIERS[i])
		if i > 0:  # LOW may cap at 30 by design; MEDIUM (mobile default) and HIGH never
			check(p.max_fps == 0 or p.max_fps >= 60, "%s does not cap below 60 FPS (%d)" % [TIERS[i], p.max_fps])
		check(p.render_scale > 0.49 and p.render_scale <= 1.0, "%s render scale sane" % TIERS[i])


func test_mobile_defaults_to_medium() -> void:
	# On this desktop run the feature is absent; the mapping itself is what ships.
	check_eq(GraphicsProfile.default_tier_for_platform(), GraphicsProfile.Tier.MEDIUM if OS.has_feature("mobile") else GraphicsProfile.Tier.HIGH,
			"mobile → MEDIUM, desktop → HIGH")


func test_docs_quote_actual_medium_shadow_distance() -> void:
	var medium := load(TIERS[1]) as GraphicsProfile
	var doc := FileAccess.get_file_as_string("res://docs/fort_pettah_art_budget.md")
	var quoted := "shadow distance %d m" % int(medium.shadow_max_distance)
	check(doc.contains(quoted), "art budget quotes \"%s\" (the .tres value)" % quoted)


func test_physics_tick_rate() -> void:
	check_eq(int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")), 60, "60 Hz physics")
