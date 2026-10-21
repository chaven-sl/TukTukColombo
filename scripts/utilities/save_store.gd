class_name SaveStore
extends RefCounted
## Versioned, crash-tolerant JSON save document.
##
## Files (for base name "save_v1" in directory D):
##   D/save_v1.json     primary
##   D/save_v1.bak      previous valid primary
##   D/save_v1.tmp      write staging; also used for recovery if a crash
##                      happened between "rotate" and "promote"
##   D/save_v1.corrupt  last unreadable primary, kept for diagnosis
##
## Write flow: write tmp -> re-read & validate tmp -> rotate valid primary to
## bak -> promote tmp to primary. Load flow: primary -> tmp -> bak -> defaults.
## Migrations upgrade older schema versions step by step.

const CURRENT_SCHEMA_VERSION := 2

enum LoadResult {
	LOADED_PRIMARY,    ## primary was valid
	RECOVERED_TEMP,    ## primary missing/corrupt, staged tmp was valid
	RECOVERED_BACKUP,  ## primary missing/corrupt, backup was valid
	CREATED_DEFAULT,   ## no save existed (first launch)
	RESET_DEFAULT,     ## save files existed but none were readable
}

var directory: String
var base_name: String
var data: Dictionary = {}
var last_load_result: LoadResult = LoadResult.CREATED_DEFAULT
var last_error := ""


func _init(p_directory: String = "user://", p_base_name: String = "save_v1") -> void:
	directory = p_directory
	base_name = p_base_name
	data = default_document()


func primary_path() -> String:
	return directory.path_join(base_name + ".json")


func backup_path() -> String:
	return directory.path_join(base_name + ".bak")


func temp_path() -> String:
	return directory.path_join(base_name + ".tmp")


func corrupt_path() -> String:
	return directory.path_join(base_name + ".corrupt")


static func default_document() -> Dictionary:
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"settings": {
			"locale": "en",
			"master_volume": 1.0,
			"show_debug_hud": false,
		},
		"prototype_stats": {
			"best_combo": 0,
			"highest_score": 0,
			"total_close_calls": 0,
			"total_tight_gaps": 0,
			# v2 (prototype v0.02)
			"rides_completed": 0,
			"rides_failed": 0,
			"best_passenger_satisfaction": 0,
			"pedestrian_impacts": 0,
			"prototype_fares_total": 0,
			"passenger_type_completions": {"rushed": 0, "careful": 0, "thrill_seeker": 0},
		},
	}


func load_document() -> LoadResult:
	var primary_exists := FileAccess.file_exists(primary_path())
	var temp_exists := FileAccess.file_exists(temp_path())
	var backup_exists := FileAccess.file_exists(backup_path())

	var doc := read_document(primary_path())
	if not doc.is_empty():
		last_load_result = LoadResult.LOADED_PRIMARY
	else:
		if primary_exists:
			_quarantine(primary_path())
		doc = read_document(temp_path())
		if not doc.is_empty():
			last_load_result = LoadResult.RECOVERED_TEMP
		else:
			doc = read_document(backup_path())
			if not doc.is_empty():
				last_load_result = LoadResult.RECOVERED_BACKUP
			elif primary_exists or temp_exists or backup_exists:
				last_load_result = LoadResult.RESET_DEFAULT
			else:
				last_load_result = LoadResult.CREATED_DEFAULT
	if doc.is_empty():
		doc = default_document()
	data = normalise(doc)
	return last_load_result


func save_document() -> bool:
	last_error = ""
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK and err != ERR_ALREADY_EXISTS:
		last_error = "cannot create save directory (%s)" % error_string(err)
		return false
	data["schema_version"] = CURRENT_SCHEMA_VERSION
	var text := JSON.stringify(data, "\t")

	var file := FileAccess.open(temp_path(), FileAccess.WRITE)
	if file == null:
		last_error = "cannot open temp file (%s)" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(text)
	file.close()

	if read_document(temp_path()).is_empty():
		last_error = "temp file failed verification"
		return false

	# Only a valid primary is rotated into the backup slot; a corrupt primary
	# must never overwrite a good backup.
	if FileAccess.file_exists(primary_path()):
		if not read_document(primary_path()).is_empty():
			if FileAccess.file_exists(backup_path()):
				DirAccess.remove_absolute(backup_path())
			err = DirAccess.rename_absolute(primary_path(), backup_path())
			if err != OK:
				last_error = "cannot rotate backup (%s)" % error_string(err)
				return false
		else:
			_quarantine(primary_path())

	err = DirAccess.rename_absolute(temp_path(), primary_path())
	if err != OK:
		last_error = "cannot promote temp file (%s)" % error_string(err)
		return false
	return true


## Reads, validates and migrates one file. Returns {} when unusable.
func read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	var doc: Dictionary = json.data
	if not doc.has("schema_version"):
		return {}
	var version_value: Variant = doc["schema_version"]
	if typeof(version_value) != TYPE_FLOAT and typeof(version_value) != TYPE_INT:
		return {}
	var version := int(version_value)
	if version > CURRENT_SCHEMA_VERSION or version < 0:
		# A newer build wrote this. Refuse rather than silently downgrade.
		return {}
	return migrate(doc, version)


## Upgrades a document one schema version at a time.
static func migrate(doc: Dictionary, from_version: int) -> Dictionary:
	var version := from_version
	while version < CURRENT_SCHEMA_VERSION:
		match version:
			0:
				doc = _migrate_0_to_1(doc)
			1:
				doc = _migrate_1_to_2(doc)
		version += 1
	doc["schema_version"] = CURRENT_SCHEMA_VERSION
	return doc


## v0 was the pre-release flat layout: {"schema_version": 0, "best_combo": n,
## "high_score": n}. Kept as the template for future migrations.
static func _migrate_0_to_1(doc: Dictionary) -> Dictionary:
	var upgraded := default_document()
	var stats: Dictionary = upgraded["prototype_stats"]
	if doc.has("best_combo"):
		stats["best_combo"] = int(doc["best_combo"])
	if doc.has("high_score"):
		stats["highest_score"] = int(doc["high_score"])
	return upgraded


## v1 -> v2: adds ride/passenger statistics. Every v1 value is kept as is;
## the new counters start at zero.
static func _migrate_1_to_2(doc: Dictionary) -> Dictionary:
	var stats: Dictionary = doc.get("prototype_stats", {}) if typeof(doc.get("prototype_stats")) == TYPE_DICTIONARY else {}
	for key in ["rides_completed", "rides_failed", "best_passenger_satisfaction", "pedestrian_impacts", "prototype_fares_total"]:
		if not stats.has(key):
			stats[key] = 0
	if not stats.has("passenger_type_completions"):
		stats["passenger_type_completions"] = {"rushed": 0, "careful": 0, "thrill_seeker": 0}
	doc["prototype_stats"] = stats
	return doc


## Fills missing keys from defaults and coerces types (JSON numbers are floats).
static func normalise(doc: Dictionary) -> Dictionary:
	var defaults := default_document()
	var result := defaults.duplicate(true)
	for section_name in defaults.keys():
		if section_name == "schema_version":
			continue
		if not doc.has(section_name) or typeof(doc[section_name]) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = doc[section_name]
		var target: Dictionary = result[section_name]
		for key in target.keys():
			if not source.has(key):
				continue
			var default_value: Variant = target[key]
			var value: Variant = source[key]
			match typeof(default_value):
				TYPE_INT:
					if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
						target[key] = int(value)
				TYPE_FLOAT:
					if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
						target[key] = float(value)
				TYPE_BOOL:
					if typeof(value) == TYPE_BOOL:
						target[key] = value
				TYPE_STRING:
					if typeof(value) == TYPE_STRING:
						target[key] = value
				TYPE_DICTIONARY:
					# Nested counters (e.g. per passenger type): keep known
					# numeric entries, accept new ids, coerce to int.
					if typeof(value) == TYPE_DICTIONARY:
						var merged: Dictionary = (default_value as Dictionary).duplicate()
						for sub in (value as Dictionary).keys():
							var sub_value: Variant = value[sub]
							if typeof(sub_value) == TYPE_FLOAT or typeof(sub_value) == TYPE_INT:
								merged[sub] = int(sub_value)
						target[key] = merged
	result["schema_version"] = CURRENT_SCHEMA_VERSION
	return result


func _quarantine(path: String) -> void:
	if FileAccess.file_exists(corrupt_path()):
		DirAccess.remove_absolute(corrupt_path())
	DirAccess.rename_absolute(path, corrupt_path())
