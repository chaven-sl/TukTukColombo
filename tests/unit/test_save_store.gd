extends "res://tests/test_case.gd"

const DIR := "user://test_saves"


func _fresh_store(name: String) -> SaveStore:
	var store := SaveStore.new(DIR, name)
	for path in [store.primary_path(), store.backup_path(), store.temp_path(), store.corrupt_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.make_dir_recursive_absolute(DIR)
	return store


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_first_launch_creates_defaults() -> void:
	var store := _fresh_store("first")
	check_eq(store.load_document(), SaveStore.LoadResult.CREATED_DEFAULT, "no files -> CREATED_DEFAULT")
	check_eq(store.data["schema_version"], SaveStore.CURRENT_SCHEMA_VERSION, "schema version set")
	check(store.data.has("settings") and store.data.has("prototype_stats"), "sections present")


func test_round_trip_serialisation() -> void:
	var store := _fresh_store("roundtrip")
	store.load_document()
	store.data["prototype_stats"]["best_combo"] = 7
	store.data["prototype_stats"]["highest_score"] = 1234
	store.data["settings"]["locale"] = "si"
	check(store.save_document(), "save succeeds: %s" % store.last_error)
	var again := SaveStore.new(DIR, "roundtrip")
	check_eq(again.load_document(), SaveStore.LoadResult.LOADED_PRIMARY, "reload from primary")
	check_eq(again.data["prototype_stats"]["best_combo"], 7, "int survives JSON (not float)")
	check_eq(typeof(again.data["prototype_stats"]["best_combo"]), TYPE_INT, "type normalised to int")
	check_eq(again.data["prototype_stats"]["highest_score"], 1234, "score survives")
	check_eq(again.data["settings"]["locale"], "si", "setting survives")
	check(not FileAccess.file_exists(again.temp_path()), "temp file promoted away")


func test_second_save_creates_backup() -> void:
	var store := _fresh_store("backup")
	store.load_document()
	store.data["prototype_stats"]["highest_score"] = 10
	store.save_document()
	store.data["prototype_stats"]["highest_score"] = 20
	store.save_document()
	check(FileAccess.file_exists(store.backup_path()), "backup exists after second save")
	var backup := store.read_document(store.backup_path())
	check_eq(backup["prototype_stats"]["highest_score"], 10, "backup holds the previous valid save")


func test_corrupt_primary_recovers_from_backup() -> void:
	var store := _fresh_store("corrupt")
	store.load_document()
	store.data["prototype_stats"]["highest_score"] = 111
	store.save_document()
	store.data["prototype_stats"]["highest_score"] = 222
	store.save_document()
	_write(store.primary_path(), "{ this is not json")
	var again := SaveStore.new(DIR, "corrupt")
	check_eq(again.load_document(), SaveStore.LoadResult.RECOVERED_BACKUP, "falls back to backup")
	check_eq(again.data["prototype_stats"]["highest_score"], 111, "backup data restored")
	check(FileAccess.file_exists(again.corrupt_path()), "corrupt file quarantined for diagnosis")


func test_everything_corrupt_resets_to_defaults() -> void:
	var store := _fresh_store("allbad")
	_write(store.primary_path(), "[1, 2, 3]")
	_write(store.backup_path(), "")
	check_eq(store.load_document(), SaveStore.LoadResult.RESET_DEFAULT, "unreadable files -> RESET_DEFAULT")
	check_eq(store.data["prototype_stats"]["highest_score"], 0, "defaults used")


func test_corrupt_primary_never_overwrites_good_backup() -> void:
	var store := _fresh_store("protect")
	store.load_document()
	store.data["prototype_stats"]["highest_score"] = 5
	store.save_document()
	store.data["prototype_stats"]["highest_score"] = 6
	store.save_document()
	_write(store.primary_path(), "garbage")
	store.data["prototype_stats"]["highest_score"] = 7
	store.save_document()
	var backup := store.read_document(store.backup_path())
	check_eq(backup["prototype_stats"]["highest_score"], 5, "good backup kept when primary was corrupt")


func test_interrupted_save_recovers_temp() -> void:
	var store := _fresh_store("interrupted")
	var doc := SaveStore.default_document()
	doc["prototype_stats"]["best_combo"] = 9
	_write(store.temp_path(), JSON.stringify(doc))
	check_eq(store.load_document(), SaveStore.LoadResult.RECOVERED_TEMP, "staged temp used when primary missing")
	check_eq(store.data["prototype_stats"]["best_combo"], 9, "temp data restored")


func test_migration_from_v0() -> void:
	var store := _fresh_store("migrate")
	_write(store.primary_path(), JSON.stringify({"schema_version": 0, "best_combo": 4, "high_score": 900}))
	check_eq(store.load_document(), SaveStore.LoadResult.LOADED_PRIMARY, "v0 primary accepted")
	check_eq(store.data["schema_version"], SaveStore.CURRENT_SCHEMA_VERSION, "upgraded to current schema")
	check_eq(store.data["prototype_stats"]["best_combo"], 4, "best_combo migrated")
	check_eq(store.data["prototype_stats"]["highest_score"], 900, "high_score renamed to highest_score")


func test_future_schema_is_refused() -> void:
	var store := _fresh_store("future")
	_write(store.primary_path(), JSON.stringify({"schema_version": 99, "settings": {}}))
	check(store.read_document(store.primary_path()).is_empty(), "newer schema not silently downgraded")


func test_missing_keys_filled_and_wrong_types_ignored() -> void:
	var doc := {"schema_version": 1, "settings": {"locale": 5}, "prototype_stats": {"best_combo": "lots"}}
	var normalised := SaveStore.normalise(doc)
	check_eq(normalised["settings"]["locale"], "en", "wrong type falls back to default")
	check_eq(normalised["prototype_stats"]["best_combo"], 0, "wrong type stat falls back")
	check(normalised["prototype_stats"].has("total_close_calls"), "missing key filled")


func test_v1_save_migrates_to_v2_preserving_data() -> void:
	var store := _fresh_store("v1_to_v2")
	var v1 := {
		"schema_version": 1,
		"settings": {"locale": "ta", "master_volume": 0.5, "show_debug_hud": true},
		"prototype_stats": {"best_combo": 6, "highest_score": 4321, "total_close_calls": 77, "total_tight_gaps": 9},
	}
	_write(store.primary_path(), JSON.stringify(v1))
	check_eq(store.load_document(), SaveStore.LoadResult.LOADED_PRIMARY, "v1 file accepted")
	check_eq(store.data["schema_version"], SaveStore.CURRENT_SCHEMA_VERSION, "upgraded to the current schema")
	var stats: Dictionary = store.data["prototype_stats"]
	check_eq(stats["best_combo"], 6, "best_combo preserved")
	check_eq(stats["highest_score"], 4321, "highest_score preserved")
	check_eq(stats["total_close_calls"], 77, "total_close_calls preserved")
	check_eq(stats["total_tight_gaps"], 9, "total_tight_gaps preserved")
	check_eq(store.data["settings"]["locale"], "ta", "settings preserved")
	check_eq(store.data["settings"]["show_debug_hud"], true, "bool setting preserved")
	for key in ["rides_completed", "rides_failed", "best_passenger_satisfaction", "pedestrian_impacts", "prototype_fares_total"]:
		check_eq(stats.get(key, -1), 0, "%s added at 0" % key)
	var per_type: Dictionary = stats["passenger_type_completions"]
	check_eq(per_type.get("careful", -1), 0, "per-passenger counters added")
	check(store.save_document(), "migrated document saves")
	var again := SaveStore.new(DIR, "v1_to_v2")
	again.load_document()
	check_eq(again.data["prototype_stats"]["highest_score"], 4321, "survives a save/load round trip")


func test_nested_counters_normalise_to_int() -> void:
	var doc := SaveStore.default_document()
	doc["prototype_stats"]["passenger_type_completions"] = {"rushed": 3.0, "careful": "bad", "vip": 2.0}
	var n := SaveStore.normalise(doc)
	var per_type: Dictionary = n["prototype_stats"]["passenger_type_completions"]
	check_eq(per_type["rushed"], 3, "float count coerced to int")
	check_eq(typeof(per_type["rushed"]), TYPE_INT, "int type")
	check_eq(per_type["careful"], 0, "invalid value falls back to default")
	check_eq(per_type.get("vip", -1), 2, "future passenger ids kept")



# --- v0.04 career (schema v3) ---

func test_clean_new_save_has_career_defaults() -> void:
	var store := _fresh_store("career_new")
	store.load_document()
	var c: Dictionary = store.data["career"]
	check_eq(c["cash"], 1500, "starting cash Rs. 1,500")
	check_eq(c["reputation"], 0, "starting reputation 0")
	check_eq((c["upgrades"] as Dictionary).size(), 4, "four upgrade categories")
	for id in ["engine", "brakes", "handling", "suspension"]:
		check_eq(c["upgrades"][id], 0, "%s starts at level 0" % id)


func test_v2_save_migrates_to_v3_keeping_stats() -> void:
	var store := _fresh_store("v2_to_v3")
	_write(store.primary_path(), JSON.stringify({"schema_version": 2, "settings": {"locale": "si"},
			"prototype_stats": {"best_combo": 9, "rides_completed": 14, "prototype_fares_total": 2100}}))
	check_eq(store.load_document(), SaveStore.LoadResult.LOADED_PRIMARY, "v2 primary loads")
	check_eq(store.data["schema_version"], 3, "migrated to v3")
	check_eq(store.data["prototype_stats"]["rides_completed"], 14, "v2 ride stats kept")
	check_eq(store.data["settings"]["locale"], "si", "settings kept")
	check_eq(store.data["career"]["cash"], 1500, "career added with starting cash")
	check_eq(store.data["career"]["upgrades"]["engine"], 0, "upgrades start at 0")


func test_career_cash_reputation_upgrades_persist() -> void:
	var store := _fresh_store("career_persist")
	store.load_document()
	store.data["career"]["cash"] = 4321
	store.data["career"]["reputation"] = 77
	store.data["career"]["upgrades"]["brakes"] = 3
	check(store.save_document(), "saved")
	var again := SaveStore.new(DIR, "career_persist")
	again.load_document()
	check_eq(again.data["career"]["cash"], 4321, "cash persisted")
	check_eq(again.data["career"]["reputation"], 77, "reputation persisted")
	check_eq(again.data["career"]["upgrades"]["brakes"], 3, "upgrade level persisted")


func test_corrupt_primary_recovers_career_from_backup() -> void:
	var store := _fresh_store("career_backup")
	store.load_document()
	store.data["career"]["cash"] = 2600
	store.save_document()
	store.data["career"]["cash"] = 9999
	store.save_document()
	_write(store.primary_path(), "{ broken")
	var again := SaveStore.new(DIR, "career_backup")
	check_eq(again.load_document(), SaveStore.LoadResult.RECOVERED_BACKUP, "falls back to the backup")
	check_eq(again.data["career"]["cash"], 2600, "career cash from the backup")


func test_tampered_career_values_are_clamped() -> void:
	var store := _fresh_store("career_clamp")
	_write(store.primary_path(), JSON.stringify({"schema_version": 3, "career": {"cash": -500, "reputation": -3,
			"upgrades": {"engine": 9, "brakes": -2}}}))
	store.load_document()
	check_eq(store.data["career"]["cash"], 0, "negative cash clamped to 0")
	check_eq(store.data["career"]["reputation"], 0, "negative reputation clamped")
	check_eq(store.data["career"]["upgrades"]["engine"], 5, "level clamped to max 5")
	check_eq(store.data["career"]["upgrades"]["brakes"], 0, "level clamped to 0")
