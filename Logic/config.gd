class_name Config

# Application settings, kept as one JSON file per user, outside the project.
# Values are read through the accessors below; every setter writes the file
# immediately, so a crash cannot lose more than the last change.

const MAX_RECENT_FILES := 10

# How far the outline sizes may be scaled either way. Small enough to see and
# large enough to be worth the setting, without letting a marker swallow the
# shape it marks.
const MIN_SCALE := 0.25
const MAX_SCALE := 4.0

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


# Drop the copy held in memory, so the next access reads the file again.
# Not named reload: that is a method of Script itself, and calling it would
# reload this script and reset every static variable in it.
static func forget() -> void:
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


### Editing and measuring
#
# The planet radius is a preference rather than part of a document: it says
# which planet the distances are read against, not anything about the features,
# so it neither dirties a document nor needs a format of its own. The two
# outline sizes are multiples of what planet.gdshader draws at, which is easier
# to pick than the chord length on a unit sphere the uniform is in.


static func get_planet_radius() -> float:
	return clampf(float(get_value("planet_radius_km", Measure.EARTH_RADIUS_KM)),
		Measure.MIN_RADIUS_KM, Measure.MAX_RADIUS_KM)


static func set_planet_radius(km: float) -> void:
	set_value("planet_radius_km", clampf(km, Measure.MIN_RADIUS_KM, Measure.MAX_RADIUS_KM))


static func get_vertex_marker_scale() -> float:
	return clampf(float(get_value("vertex_marker_scale", 1.0)), MIN_SCALE, MAX_SCALE)


static func set_vertex_marker_scale(scale: float) -> void:
	set_value("vertex_marker_scale", clampf(scale, MIN_SCALE, MAX_SCALE))


static func get_line_width_scale() -> float:
	return clampf(float(get_value("line_width_scale", 1.0)), MIN_SCALE, MAX_SCALE)


static func set_line_width_scale(scale: float) -> void:
	set_value("line_width_scale", clampf(scale, MIN_SCALE, MAX_SCALE))


# How far the timeline's step buttons and their shortcuts jump, in millions of
# years. A number beside the buttons rather than a dialog setting, since it is
# changed on the spot: 50 for laying out an animation, 10 for one feature's
# movement, and back.
const DEFAULT_SKIP := 50.0
const MIN_SKIP := 0.0001


static func get_skip_increment() -> float:
	return maxf(float(get_value("skip_increment", DEFAULT_SKIP)), MIN_SKIP)


static func set_skip_increment(increment: float) -> void:
	set_value("skip_increment", maxf(increment, MIN_SKIP))


static func get_snap_to_vertices() -> bool:
	return bool(get_value("snap_to_vertices", true))


static func set_snap_to_vertices(enabled: bool) -> void:
	set_value("snap_to_vertices", enabled)


# Whether the Circle tool commits a circle as an outline, a polyline, rather
# than a polygon. A switch beside the segment count while that tool is active,
# and the kind of choice someone makes once and keeps.
static func get_circle_outline() -> bool:
	return bool(get_value("circle_outline", false))


static func set_circle_outline(enabled: bool) -> void:
	set_value("circle_outline", enabled)


# Whether the Split tool leaves a ridge along the cut. A switch beside the Split
# button while that tool is active, on unless someone turns it off.
static func get_split_ridge() -> bool:
	return bool(get_value("split_ridge", true))


static func set_split_ridge(enabled: bool) -> void:
	set_value("split_ridge", enabled)


# How wide a picture File > Export Image writes. The height follows from the
# projection, so this one number settles the size of every export. The default
# is large enough to print and the bounds are what a viewport can be asked for.
const DEFAULT_EXPORT_WIDTH := 3600
const MIN_EXPORT_WIDTH := 100
const MAX_EXPORT_WIDTH := 8000
const EXPORT_WIDTH_STEP := 10


static func get_export_width() -> int:
	return clampi(int(get_value("export_width", DEFAULT_EXPORT_WIDTH)),
		MIN_EXPORT_WIDTH, MAX_EXPORT_WIDTH)


static func set_export_width(width: int) -> void:
	set_value("export_width", clampi(width, MIN_EXPORT_WIDTH, MAX_EXPORT_WIDTH))


# Which ffmpeg encodes the frames of a video export. Empty means look for one:
# on the path first, then where Shotcut keeps the copy it ships. A path that
# names nothing leaves the frames unencoded rather than sending the search off
# to find some other encoder, so a machine can be told it has none.
static func get_ffmpeg() -> String:
	return str(get_value("ffmpeg", "")).strip_edges()


static func set_ffmpeg(path: String) -> void:
	set_value("ffmpeg", path.strip_edges())


### The view
#
# What a new document starts from: the scene settings it is given, and which
# view it opens in. The settings themselves belong to a document and are saved
# with it; these are only the values a document that has said nothing yet gets.


# The name the projection selector shows for the view a new document opens in.
# A name no longer in the selector falls back to the globe.
static func get_default_view() -> String:
	return str(get_value("default_view", "Globe"))


static func set_default_view(name: String) -> void:
	set_value("default_view", name)


static func get_view_defaults() -> ViewSettings:
	return ViewSettings.from_json(get_value("view_defaults"))


# The block holds the scene settings only. A `style` key an older version
# wrote into it, or the draw style keys from before 0.10.0, are not read: the
# root group's style is pinned, so there is no default to keep for it.
static func set_view_defaults(settings: ViewSettings) -> void:
	set_value("view_defaults", settings.to_json())



### Python
#
# Which interpreter runs the scripting bridge and where the scripts that become
# menu entries are looked for. The interpreter defaults to the environment the
# project's own tooling uses, so a checkout that has had `uv sync` run in it
# needs no setting at all; an installed application is given one in Preferences.


static func default_interpreter() -> String:
	var project := ProjectSettings.globalize_path("res://")
	if OS.get_name() == "Windows":
		return project.path_join(".venv/Scripts/python.exe")
	return project.path_join(".venv/bin/python")


# Where the scripts shipped with the project are, which is what the script
# directories start as.
static func _default_script_directory() -> String:
	return ProjectSettings.globalize_path("res://").path_join("Scripts")


static func get_python_interpreter() -> String:
	var path := str(get_value("python_interpreter", ""))
	return path if not path.is_empty() else default_interpreter()


static func set_python_interpreter(path: String) -> void:
	set_value("python_interpreter", path)


static func get_script_directories() -> Array:
	var stored: Variant = get_value("script_directories")
	if stored is not Array:
		return [_default_script_directory()]
	var directories: Array = []
	for entry in stored:
		if not str(entry).strip_edges().is_empty():
			directories.append(str(entry).strip_edges())
	return directories


static func set_script_directories(directories: Array) -> void:
	var cleaned: Array = []
	for entry in directories:
		var path := str(entry).strip_edges()
		if not path.is_empty() and path not in cleaned:
			cleaned.append(path)
	set_value("script_directories", cleaned)


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
