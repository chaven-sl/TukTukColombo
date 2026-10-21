extends SceneTree
## Headless logic test runner.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Discovers tests/unit/test_*.gd, runs every test_* method and exits with
## code 1 if any assertion failed. Run `godot --headless --path . --import`
## first after adding new class_name scripts so the class cache is current.

const UNIT_DIR := "res://tests/unit"


func _initialize() -> void:
	var total_tests := 0
	var total_assertions := 0
	var all_failures := PackedStringArray()
	var files := DirAccess.get_files_at(UNIT_DIR)
	files.sort()
	for file_name in files:
		if not file_name.begins_with("test_") or not file_name.ends_with(".gd"):
			continue
		var script: GDScript = load(UNIT_DIR.path_join(file_name))
		var suite: RefCounted = script.new()
		var suite_tests := 0
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			suite.set("current_test", "%s::%s" % [file_name.get_basename(), method_name])
			suite.call(method_name)
			suite_tests += 1
		var failures: PackedStringArray = suite.get("failures")
		total_tests += suite_tests
		total_assertions += int(suite.get("assertions"))
		print("%-34s %2d tests  %s" % [file_name.get_basename(), suite_tests, "ok" if failures.is_empty() else "%d FAILED" % failures.size()])
		all_failures.append_array(failures)
	print("")
	for failure in all_failures:
		print("  FAIL  " + failure)
	print("=== UNIT TESTS: %s — %d tests, %d assertions, %d failures ===" % [
		"PASS" if all_failures.is_empty() else "FAIL", total_tests, total_assertions, all_failures.size()])
	quit(0 if all_failures.is_empty() else 1)
