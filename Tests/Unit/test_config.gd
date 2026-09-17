extends TestCase

# The config file is what a session is restored from, so what goes in has to
# come back out of a fresh read, and the recent file list has to stay ordered,
# free of duplicates and bounded.

const SCRATCH := "user://test_config"


func _use_a_scratch_config() -> void:
	Config.directory_override = ProjectSettings.globalize_path(SCRATCH)
	DirAccess.make_dir_recursive_absolute(Config.directory_override)
	DirAccess.remove_absolute(Config.directory_override + "/config.json")
	Config.forget()


func _restore_the_real_config() -> void:
	DirAccess.remove_absolute(Config.directory_override + "/config.json")
	Config.directory_override = ""
	Config.forget()


func test_values_survive_a_reload() -> void:
	_use_a_scratch_config()
	Config.set_value("window", {"x": 120, "y": 60, "width": 1280, "height": 720, "maximized": false})
	Config.set_value("splitter_left", 380)
	Config.set_value("splitter_right", -290)
	Config.set_value("panel_timeline", false)
	Config.set_last_directory("C:/Maps")

	Config.forget()

	var window: Variant = Config.get_value("window")
	assert_true(window is Dictionary, "the window geometry comes back as a dictionary")
	assert_eq(int(window["x"]), 120)
	assert_eq(int(window["y"]), 60)
	assert_eq(int(window["width"]), 1280)
	assert_eq(int(window["height"]), 720)
	assert_eq(bool(window["maximized"]), false)
	assert_eq(int(Config.get_value("splitter_left", 0)), 380)
	assert_eq(int(Config.get_value("splitter_right", 0)), -290)
	assert_eq(bool(Config.get_value("panel_timeline", true)), false)
	assert_eq(Config.get_last_directory(), "C:/Maps")
	_restore_the_real_config()


# Preferences saved before 0.16.0 name the raster and the grid by their old
# keys; the values carry over and the file is written with the new ones.
func test_view_defaults_saved_before_0_16_0_keep_their_values() -> void:
	_use_a_scratch_config()
	Config.set_value("view_defaults", {"backdrop_opacity": 0.3, "graticule_spacing": 45.0})
	Config.forget()
	var settings := Config.get_view_defaults()
	assert_close(settings.raster_opacity, 0.3, 1e-6, "the raster opacity")
	assert_eq(settings.grid_spacing, 45.0, "the grid spacing")
	assert_eq(settings.planet_color, ViewSettings.DEFAULT_PLANET_COLOR,
		"preferences without a planet color take the default")
	assert_eq(settings.raster_path, "", "and, unlike a file, no raster")
	Config.forget()
	assert_eq(Config.get_value("view_defaults"), {"raster_opacity": 0.3, "grid_spacing": 45.0},
		"and the file holds the new keys")
	_restore_the_real_config()


func test_a_missing_key_falls_back_to_the_default() -> void:
	_use_a_scratch_config()
	assert_eq(Config.get_value("never_written", "fallback"), "fallback")
	assert_eq(bool(Config.get_value("restore_session", true)), true)
	_restore_the_real_config()


func test_the_recent_list_keeps_the_newest_first_without_duplicates() -> void:
	_use_a_scratch_config()
	Config.add_recent_file("a.middle-earth")
	Config.add_recent_file("b.middle-earth")
	Config.add_recent_file("a.middle-earth")
	Config.forget()
	assert_eq(Config.get_recent_files(), ["a.middle-earth", "b.middle-earth"],
		"the reopened file moves to the front and is listed once")

	Config.clear_recent_files()
	Config.forget()
	assert_eq(Config.get_recent_files(), [], "Clear empties the list")
	_restore_the_real_config()


func test_the_recent_list_is_capped() -> void:
	var list: Array = []
	for i in Config.MAX_RECENT_FILES + 5:
		list = Config.push_recent(list, "file %d" % i, Config.MAX_RECENT_FILES)
	assert_eq(list.size(), Config.MAX_RECENT_FILES, "the list stops at MAX_RECENT_FILES")
	assert_eq(str(list[0]), "file %d" % (Config.MAX_RECENT_FILES + 4), "the newest is first")


func test_the_python_settings_default_to_the_project_and_survive_a_reload() -> void:
	_use_a_scratch_config()
	var project := ProjectSettings.globalize_path("res://")
	assert_true(Config.get_python_interpreter().begins_with(project.path_join(".venv")),
		"an unset interpreter is the project's own environment")
	assert_eq(Config.get_script_directories(), [project.path_join("Scripts")],
		"an unset script list is the folder the project ships")

	Config.set_python_interpreter("C:/Python/python.exe")
	Config.set_script_directories(["C:/Scripts", " C:/More ", "", "C:/Scripts"])
	Config.forget()

	assert_eq(Config.get_python_interpreter(), "C:/Python/python.exe")
	assert_eq(Config.get_script_directories(), ["C:/Scripts", "C:/More"],
		"blank entries and repeats are dropped")

	Config.set_script_directories([])
	Config.forget()
	assert_eq(Config.get_script_directories(), [], "an empty list is a choice, not an absence")
	_restore_the_real_config()


func test_the_export_width_defaults_and_stays_inside_its_bounds() -> void:
	_use_a_scratch_config()
	assert_eq(Config.get_export_width(), Config.DEFAULT_EXPORT_WIDTH,
		"an unset export width is the default")

	Config.set_export_width(720)
	Config.forget()
	assert_eq(Config.get_export_width(), 720, "a width that was set survives a reload")

	Config.set_export_width(99999)
	assert_eq(Config.get_export_width(), Config.MAX_EXPORT_WIDTH, "too wide is clamped")
	Config.set_export_width(1)
	assert_eq(Config.get_export_width(), Config.MIN_EXPORT_WIDTH, "and so is too narrow")

	# A file written by hand is read through the same bounds.
	Config.set_value("export_width", 0)
	assert_eq(Config.get_export_width(), Config.MIN_EXPORT_WIDTH,
		"a width read from the file is clamped too")
	_restore_the_real_config()


func test_the_ffmpeg_path_is_remembered_as_it_was_typed() -> void:
	_use_a_scratch_config()
	assert_eq(Config.get_ffmpeg(), "", "no ffmpeg named is the search")

	Config.set_ffmpeg("  C:/ffmpeg/bin/ffmpeg.exe  ")
	Config.forget()
	assert_eq(Config.get_ffmpeg(), "C:/ffmpeg/bin/ffmpeg.exe",
		"a path survives a reload without the spaces around it")

	Config.set_ffmpeg("")
	assert_eq(Config.get_ffmpeg(), "", "and clearing it asks for the search again")
	_restore_the_real_config()


func test_feature_colors_survive_a_reload() -> void:
	_use_a_scratch_config()
	assert_eq(Config.get_feature_colors(), {}, "no file, no feature colors")
	assert_eq(FeatureType.color(FeatureType.POLYGON), Color(0.36, 0.60, 0.33), "so the catalog color holds")
	var blue := Color(0.0, 0.0, 1.0, 1.0)
	Config.set_feature_colors({FeatureType.POLYGON: blue})
	Config.forget()
	assert_eq(Config.get_feature_colors(), {FeatureType.POLYGON: blue}, "the dictionary comes back")
	assert_eq(Config.get_value("feature_colors"), {FeatureType.POLYGON: [0.0, 0.0, 1.0, 1.0]},
		"written as [r, g, b, a]")
	assert_eq(FeatureType.color(FeatureType.POLYGON), blue, "the preference wins over the catalog")
	assert_eq(FeatureType.color(FeatureType.NONE), blue, "and is what a type the catalog lacks takes")
	assert_eq(FeatureType.color(FeatureType.LINE), Color.CRIMSON, "a missing entry is the catalog color")
	Config.set_value("feature_colors", {FeatureType.LINE: "red"})
	assert_eq(FeatureType.color(FeatureType.LINE), Color.CRIMSON, "and so is one that is not a color")
	_restore_the_real_config()
