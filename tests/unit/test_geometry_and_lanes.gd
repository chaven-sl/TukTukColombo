extends "res://tests/test_case.gd"


func test_rect_distance_side_by_side() -> void:
	# Two 2x4 rects facing the same way, centres 3 m apart sideways -> 1 m gap.
	var d := OrientedRect.distance(Vector2.ZERO, Vector2(0, -1), 1.0, 2.0, Vector2(3, 0), Vector2(0, -1), 1.0, 2.0)
	check_near(d, 1.0, 0.0001, "parallel gap")


func test_rect_distance_overlap_is_zero() -> void:
	var d := OrientedRect.distance(Vector2.ZERO, Vector2(0, -1), 1.0, 2.0, Vector2(1.5, 0.5), Vector2(0, -1), 1.0, 2.0)
	check_near(d, 0.0, 0.0001, "overlap")
	# Cross-shaped overlap where no corner is inside the other rectangle.
	var cross := OrientedRect.distance(Vector2.ZERO, Vector2(0, -1), 0.5, 3.0, Vector2.ZERO, Vector2(1, 0), 0.5, 3.0)
	check_near(cross, 0.0, 0.0001, "cross overlap detected by SAT")


func test_rect_distance_rotated() -> void:
	# Rect B rotated 90 deg, its nearest edge 2 m ahead of A's front.
	var d := OrientedRect.distance(Vector2.ZERO, Vector2(0, -1), 1.0, 2.0, Vector2(0, -5), Vector2(1, 0), 1.0, 2.0)
	check_near(d, 2.0, 0.0001, "front-to-side gap")


func test_lane_sampling_and_length() -> void:
	var lane := Lane.new()
	lane.set_points(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, -10), Vector3(10, 0, -10)]))
	check_near(lane.length, 20.0, 0.0001, "polyline length")
	check(lane.sample_position(5.0).is_equal_approx(Vector3(0, 0, -5)), "midpoint of first segment")
	check(lane.sample_position(15.0).is_equal_approx(Vector3(5, 0, -10)), "midpoint of second segment")
	check(lane.sample_position(-3.0).is_equal_approx(Vector3.ZERO), "clamped below 0")
	check(lane.sample_position(99.0).is_equal_approx(Vector3(10, 0, -10)), "clamped above length")
	check_near(lane.closest_s(Vector3(1, 0, -7)), 7.0, 0.0001, "projection onto lane")


func test_curve_advisory_is_slower_than_straight() -> void:
	var arc := PackedVector3Array()
	for i in 41:
		var a := deg_to_rad(90.0 * i / 40.0)
		arc.append(Vector3(20.0 * (1.0 - cos(a)), 0.0, -20.0 * sin(a)))
	var curved := Lane.new()
	curved.set_points(arc, 2.8)
	check_near(curved.advisory_at(15.0), sqrt(2.8 * 20.0), 0.5, "advisory ≈ sqrt(a_lat * r) on r=20 arc")
	var straight := Lane.new()
	straight.set_points(PackedVector3Array([Vector3.ZERO, Vector3(0, 0, -50), Vector3(0, 0, -100)]))
	check(straight.advisory_at(50.0) > 30.0, "straight lane is effectively unlimited")
