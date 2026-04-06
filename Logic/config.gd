class_name Config


static var _data: Dictionary = {}
static var _loaded: bool = false


static func _get_config_dir() -> String:
	return OS.get_environment("APPDATA") + "/MiddleEarth"


static func _get_config_path() -> String:
	return _get_config_dir() + "/config.json"


static func _get_default_directory() -> String:
	return OS.get_environment("USERPROFILE") + "/Documents"


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path := _get_config_path()
	if not FileAccess.file_exists(path):
		_data = {}
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_data = {}
		return
	var text := file.get_as_text()
	var json := JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		_data = json.data
	else:
		_data = {}


static func save() -> void:
	DirAccess.make_dir_recursive_absolute(_get_config_dir())
	var file := FileAccess.open(_get_config_path(), FileAccess.WRITE)
	if file == null:
		push_error("Failed to write config file: %s" % _get_config_path())
		return
	file.store_string(JSON.stringify(_data, "\t"))


static func get_last_directory() -> String:
	_ensure_loaded()
	return _data.get("last_directory", _get_default_directory())


static func set_last_directory(path: String) -> void:
	_ensure_loaded()
	_data["last_directory"] = path
	save()


static func set_last_directory_from_file(file_path: String) -> void:
	set_last_directory(file_path.get_base_dir())
