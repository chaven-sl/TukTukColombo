extends RefCounted
## Minimal assertion base for headless logic tests (no plugin dependency).
## Test suites extend this and define methods named test_*.

var failures: PackedStringArray = PackedStringArray()
var assertions := 0
var current_test := ""


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append("%s: %s" % [current_test, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance, "%s (expected %.3f ± %.3f, got %.3f)" % [message, expected, tolerance, actual])
