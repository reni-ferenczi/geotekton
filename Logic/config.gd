class_name Config

# Application settings, kept as one JSON file per user, outside the project.
# Values are read through the accessors below; every setter writes the file
# immediately, so a crash cannot lose more than the last change.

const MAX_RECENT_FILES := 10

# Where the config file lives; set to a scratch folder by the tests.
static var directory_override: String = ""

static var _data: Dictionary = {}
static var _loaded: bool = false


static func _get_config_dir() -> String:
	if not directory_override.is_empty():
		return directory_override
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


# Forget what was read, so the next access loads the file again.
static func reload() -> void:
	_loaded = false
	_data = {}


# Throw every setting away, for a run that must neither depend on nor change
# the settings of whoever is at the keyboard.
static func clear() -> void:
	_data = {}
	_loaded = true
	save()


static func save() -> void:
	DirAccess.make_dir_recursive_absolute(_get_config_dir())
	var file := FileAccess.open(_get_config_path(), FileAccess.WRITE)
	if file == null:
		push_error("Failed to write config file: %s" % _get_config_path())
		return
	file.store_string(JSON.stringify(_data, "\t"))


### Generic access


static func get_value(key: String, default: Variant = null) -> Variant:
	_ensure_loaded()
	return _data.get(key, default)


static func set_value(key: String, value: Variant) -> void:
	_ensure_loaded()
	_data[key] = value
	save()


### Folders


static func get_last_directory() -> String:
	return get_value("last_directory", _get_default_directory())


static func set_last_directory(path: String) -> void:
	set_value("last_directory", path)


static func set_last_directory_from_file(file_path: String) -> void:
	set_last_directory(file_path.get_base_dir())


### Recently opened files


static func get_recent_files() -> Array:
	return get_value("recent_files", [])


static func add_recent_file(path: String) -> void:
	set_value("recent_files", push_recent(get_recent_files(), path, MAX_RECENT_FILES))


static func clear_recent_files() -> void:
	set_value("recent_files", [])


# The list with path in front, without a second copy of it and no longer than
# cap entries.
static func push_recent(list: Array, path: String, cap: int) -> Array:
	var result: Array = [path]
	for entry in list:
		if str(entry) != path:
			result.append(entry)
	return result.slice(0, cap)
