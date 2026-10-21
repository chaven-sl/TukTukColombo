extends Node
## Global access point to the persistent local save (user://save_v1.json).
## File handling, backup, recovery and migration live in SaveStore so they can
## be unit tested without this autoload.

signal saved(ok: bool)

var store: SaveStore
var last_load_result: int = SaveStore.LoadResult.CREATED_DEFAULT


func _ready() -> void:
	store = SaveStore.new("user://", "save_v1")
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
