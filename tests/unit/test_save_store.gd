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
