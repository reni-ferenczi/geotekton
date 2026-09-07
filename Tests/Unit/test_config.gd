extends TestCase

# The config file is what a session is restored from, so what goes in has to
# come back out of a fresh read, and the recent file list has to stay ordered,
# free of duplicates and bounded.

const SCRATCH := "user://test_config"


func _use_a_scratch_config() -> void:
	Config.directory_override = ProjectSettings.globalize_path(SCRATCH)
	DirAccess.make_dir_recursive_absolute(Config.directory_override)
	DirAccess.remove_absolute(Config.directory_override + "/config.json")
	Config.reload()


func _restore_the_real_config() -> void:
	DirAccess.remove_absolute(Config.directory_override + "/config.json")
	Config.directory_override = ""
	Config.reload()


func test_values_survive_a_reload() -> void:
	_use_a_scratch_config()
	Config.set_value("window", {"x": 120, "y": 60, "width": 1280, "height": 720, "maximized": false})
	Config.set_value("splitter_left", 380)
	Config.set_value("splitter_right", -290)
	Config.set_value("panel_timeline", false)
	Config.set_last_directory("C:/Maps")

	Config.reload()

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
	Config.reload()
	assert_eq(Config.get_recent_files(), ["a.middle-earth", "b.middle-earth"],
		"the reopened file moves to the front and is listed once")

	Config.clear_recent_files()
	Config.reload()
	assert_eq(Config.get_recent_files(), [], "Clear empties the list")
	_restore_the_real_config()


func test_the_recent_list_is_capped() -> void:
	var list: Array = []
	for i in Config.MAX_RECENT_FILES + 5:
		list = Config.push_recent(list, "file %d" % i, Config.MAX_RECENT_FILES)
	assert_eq(list.size(), Config.MAX_RECENT_FILES, "the list stops at MAX_RECENT_FILES")
	assert_eq(str(list[0]), "file %d" % (Config.MAX_RECENT_FILES + 4), "the newest is first")
