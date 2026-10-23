extends Node
## Global access point to the persistent local save (user://save_v1.json).
## File handling, backup, recovery and migration live in SaveStore so they can
## be unit tested without this autoload.

signal saved(ok: bool)

var store: SaveStore
var last_load_result: int = SaveStore.LoadResult.CREATED_DEFAULT


func _ready() -> void:
	# Automated (headless) runs never touch the player's progression: they
	# use their own save slot. `-- --save-slot=NAME` picks one explicitly.
	var slot := "save_headless" if DisplayServer.get_name() == "headless" else "save_v1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-slot="):
			slot = arg.get_slice("=", 1)
	store = SaveStore.new("user://", slot)
	if slot == "save_headless":
		# Every automated run starts from a clean career: stages must not
		# inherit cash / upgrades / reputation from an earlier test process.
		for path in [store.primary_path(), store.backup_path(), store.temp_path(), store.corrupt_path()]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	last_load_result = store.load_document()
	print("[SaveManager] load: %s" % SaveStore.LoadResult.keys()[last_load_result])


func get_setting(key: String, default_value: Variant = null) -> Variant:
	return _section("settings").get(key, default_value)


func set_setting(key: String, value: Variant) -> void:
	_section("settings")[key] = value


func get_stat(key: String, default_value: Variant = 0) -> Variant:
	return _section("prototype_stats").get(key, default_value)


func set_stat(key: String, value: Variant) -> void:
	_section("prototype_stats")[key] = value


## v0.04 career section (CareerProfile wraps it; same dictionary instance).
func career_section() -> Dictionary:
	return _section("career")


func save_now() -> bool:
	var ok := store.save_document()
	if not ok:
		push_warning("[SaveManager] save failed: %s" % store.last_error)
	saved.emit(ok)
	return ok


func _section(section_name: String) -> Dictionary:
	if not store.data.has(section_name):
		store.data[section_name] = {}
	return store.data[section_name]
