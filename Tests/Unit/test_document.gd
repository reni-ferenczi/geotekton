extends TestCase

# The document owns the tree, the path and the dirty flag. The dirty flag comes
# from the undo stack, so it has to survive undo, redo, save and load.

const SAMPLE := "res://Tests/Data/two_cratons.middle-earth"
const SCRATCH := "user://test_document.middle-earth"


func test_a_new_document_is_clean_and_untitled() -> void:
	var document := Document.new()
	assert_true(not document.is_dirty(), "a new document is clean")
	assert_eq(document.path, "", "a new document has no path")
	assert_eq(document.display_name(), Document.UNTITLED)
	assert_true(document.root.is_root, "the root group is marked as the root")
	assert_true(not document.can_undo(), "there is nothing to undo yet")
	assert_true(not document.can_redo(), "there is nothing to redo yet")


func test_an_edit_makes_it_dirty_and_undoing_it_clean_again() -> void:
	var document := Document.new()
	document.root.children.append(Feature.create_feature("Craton"))
	document.record()
	assert_true(document.is_dirty(), "the document is dirty after an edit")
	assert_true(document.can_undo(), "the edit can be undone")

	document.undo()
	assert_true(not document.is_dirty(), "undoing back to the saved version is clean")
	assert_eq(document.root.child_count(), 0, "the feature is gone")

	document.redo()
	assert_true(document.is_dirty(), "redoing the edit is dirty again")
	assert_eq(document.root.child_count(), 1, "the feature is back")


func test_a_view_setting_is_undone_like_an_edit() -> void:
	var document := Document.new()
	var before := document.view.background_color
	document.view.background_color = Color.RED
	document.view_edited()
	assert_true(document.is_dirty(), "a view setting edited is offered for saving")
	assert_true(document.can_undo(), "and can be undone")

	document.undo()
	assert_eq(document.view.background_color, before, "undo puts the colour back")
	assert_true(not document.is_dirty(), "undoing to the saved version is clean")

	document.redo()
	assert_eq(document.view.background_color, Color.RED, "redo brings it back")
	assert_true(document.is_dirty(), "and the document is dirty again")


func test_a_version_holds_the_view_it_was_recorded_with() -> void:
	# The stack clones the block, so editing the live one afterwards does not
	# rewrite the version that was recorded.
	var document := Document.new()
	document.view.ambient = 0.5
	document.view_edited()
	document.view.ambient = 0.9
	document.undo()
	document.redo()
	assert_close(document.view.ambient, 0.5, 1e-9, "the version is what was recorded")


func test_recording_an_edit_drops_the_redo_versions() -> void:
	var document := Document.new()
	document.root.children.append(Feature.create_feature("First"))
	document.record()
	document.undo()
	document.root.children.append(Feature.create_feature("Second"))
	document.record()
	assert_true(not document.can_redo(), "the undone edit cannot be redone after a new one")
	assert_eq(document.root.children[0].title, "Second")


func test_loading_a_file_gives_a_clean_document_named_after_it() -> void:
	var document := Document.new()
	document.root.children.append(Feature.create_feature("Craton"))
	document.record()

	assert_eq(document.load_from_file(SAMPLE), "", "the sample file loads")
	assert_true(not document.is_dirty(), "a freshly loaded document is clean")
	assert_eq(document.path, SAMPLE)
	assert_eq(document.display_name(), "two_cratons.middle-earth")
	assert_true(not document.can_undo(), "loading resets the undo stack")
	assert_eq(document.root.children[0].child_count(), 3, "the three cratons are there")


func test_loading_a_file_that_is_not_one_reports_why() -> void:
	var document := Document.new()
	assert_true(not document.load_from_file("res://Tests/Data/nothing-here").is_empty(),
		"a missing file is reported")
	assert_true(not document.load_from_file("res://project.godot").is_empty(),
		"a file that is not JSON is reported")
	assert_true(not document.is_dirty(), "a failed load leaves the document alone")


func test_saving_makes_it_clean_and_writes_what_loads_back() -> void:
	var document := Document.new()
	document.root.children.append(Feature.create_feature("Craton"))
	document.record()

	assert_eq(document.save_to_file(SCRATCH), "", "the document is written")
	assert_true(not document.is_dirty(), "saving makes the document clean")
	assert_eq(document.path, SCRATCH)
	assert_eq(document.display_name(), "test_document.middle-earth")

	var reloaded := Document.new()
	assert_eq(reloaded.load_from_file(SCRATCH), "", "the written file loads back")
	assert_eq(reloaded.root.children[0].title, "Craton")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func test_editing_after_a_save_is_dirty_until_it_is_undone() -> void:
	var document := Document.new()
	assert_eq(document.save_to_file(SCRATCH), "")
	document.root.children.append(Feature.create_feature("Craton"))
	document.record()
	assert_true(document.is_dirty(), "the edit after the save is unsaved")
	document.undo()
	assert_true(not document.is_dirty(), "undoing back to the saved version is clean")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func test_the_undo_buffer_stops_growing() -> void:
	var document := Document.new()
	for i in Document.MAX_UNDO_STEPS + 10:
		document.root.children.append(Feature.create_feature("Craton %d" % i))
		document.record()
	assert_eq(document.versions.size(), Document.MAX_UNDO_STEPS,
		"the buffer keeps at most MAX_UNDO_STEPS versions")
	assert_true(document.is_dirty(),
		"the saved version fell out of the buffer, so the document stays dirty")
	while document.can_undo():
		document.undo()
	assert_true(document.is_dirty(), "undoing to the oldest kept version is still dirty")


### The current time

# The time is where the document is being looked at, not part of what it holds,
# so it records no undo version and leaves the dirty flag alone.


func test_moving_the_time_leaves_the_document_clean() -> void:
	var document := Document.new()
	var moved := [0]
	document.time_changed.connect(func() -> void: moved[0] += 1)

	document.set_time(750.0)
	assert_close(document.current_time, 750.0, 1e-9)
	assert_eq(moved[0], 1, "the move was announced")
	assert_true(not document.is_dirty(), "looking at another time changes nothing")
	assert_true(not document.can_undo(), "and records nothing to undo")

	document.set_time(750.0)
	assert_eq(moved[0], 1, "setting the time it already is announces nothing")


func test_the_time_stays_between_the_present_and_the_limit() -> void:
	var document := Document.new()
	document.set_time(-50.0)
	assert_close(document.current_time, 0.0, 1e-9, "there is no time after the present")
	document.set_time(Document.MAX_TIME + 1000.0)
	assert_close(document.current_time, Document.MAX_TIME, 1e-9, "nor before the limit")


func test_a_document_always_opens_at_the_present() -> void:
	var document := Document.new()
	document.set_time(1200.0)
	assert_eq(document.load_from_file(SAMPLE), "", "the sample file loads")
	assert_close(document.current_time, 0.0, 1e-9, "opening a file comes back to now")

	document.set_time(1200.0)
	document.reset()
	assert_close(document.current_time, 0.0, 1e-9, "and so does a new document")


### Keyframes

# These are content: each one records an undo version like every other edit.


func test_setting_a_keyframe_records_an_undo_version() -> void:
	var document := Document.new()
	var feature := Feature.create_feature("Craton")
	document.root.children.append(feature)
	document.record()

	document.set_keyframe(feature, 100.0, Vector3(30, 0, 0))
	assert_eq(feature.keyframes.size(), 1)
	assert_true(document.can_undo(), "the keyframe can be undone")

	document.set_keyframe(feature, 100.0, Vector3(45, 0, 0))
	assert_eq(feature.keyframes.size(), 1, "the same time replaces rather than adds")
	assert_close(feature.keyframes[0].rotation, Vector3(45, 0, 0), 1e-6)


func test_a_keyframe_can_be_moved_but_not_onto_another() -> void:
	var document := Document.new()
	var feature := Feature.create_feature("Craton")
	document.root.children.append(feature)
	document.set_keyframe(feature, 0.0, Vector3.ZERO)
	document.set_keyframe(feature, 100.0, Vector3(30, 0, 0))

	assert_eq(document.set_keyframe_time(feature, 1, 50.0), "", "moving it is allowed")
	assert_close(feature.keyframes[1].time, 50.0, 1e-9)
	assert_close(feature.keyframes[1].rotation, Vector3(30, 0, 0), 1e-6, "it took its rotation")

	assert_true(not document.set_keyframe_time(feature, 1, 0.0).is_empty(),
		"moving it onto the other one is refused")
	assert_eq(feature.keyframes.size(), 2, "and nothing was merged away")
	assert_true(not document.set_keyframe_time(feature, 1, -1.0).is_empty(),
		"a time after the present is refused")


func test_a_keyframe_moved_past_another_keeps_the_list_sorted() -> void:
	var document := Document.new()
	var feature := Feature.create_feature("Craton")
	document.root.children.append(feature)
	document.set_keyframe(feature, 0.0, Vector3(1, 0, 0))
	document.set_keyframe(feature, 100.0, Vector3(2, 0, 0))

	assert_eq(document.set_keyframe_time(feature, 0, 500.0), "")
	assert_close(feature.keyframes[0].time, 100.0, 1e-9, "the other one is first now")
	assert_close(feature.keyframes[1].rotation, Vector3(1, 0, 0), 1e-6,
		"and the moved one is last, still holding its own rotation")


func test_a_keyframe_can_be_deleted_and_the_index_is_checked() -> void:
	var document := Document.new()
	var feature := Feature.create_feature("Craton")
	document.root.children.append(feature)
	document.set_keyframe(feature, 100.0, Vector3(30, 0, 0))

	assert_true(not document.remove_keyframe(feature, 3).is_empty(), "there is no keyframe 3")
	assert_eq(document.remove_keyframe(feature, 0), "", "the one that is there goes")
	assert_eq(feature.keyframes.size(), 0)
	document.undo()
	assert_eq(document.root.children[0].keyframes.size(), 1, "and undo brings it back")


func test_a_saved_file_says_its_format_and_keeps_the_time_it_was_given() -> void:
	# A time with more digits than a 32-bit float can hold, to show that the
	# keyframe times are written and read as doubles.
	const TIME := 1234.5678901234
	var document := Document.new()
	var feature := Feature.create_feature("Craton")
	document.root.children.append(feature)
	document.set_keyframe(feature, TIME, Vector3(30, 0, 0))
	assert_eq(document.save_to_file(SCRATCH), "", "the document is written")

	var file := FileAccess.open(SCRATCH, FileAccess.READ)
	var raw: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert_eq(str(raw["version"]), Application.VERSION,
		"the file says which format it is in")
	assert_close(float(raw["features"]["children"][0]["keyframes"][0]["time"]), TIME, 1e-9,
		"the time survives the round trip through the file")

	var reloaded := Document.new()
	assert_eq(reloaded.load_from_file(SCRATCH), "", "the written file loads back")
	assert_close(reloaded.root.children[0].keyframes[0].time, TIME, 1e-9)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func test_an_imported_document_opens_untitled_and_unsaved() -> void:
	# File > Import converts into a scratch file and loads that; what opens is
	# a document nobody has saved yet rather than one belonging to the scratch.
	var document := Document.new()
	assert_eq(document.load_imported(SAMPLE), "", "the file was read")
	assert_eq(document.path, "", "an imported document has no file of its own")
	assert_eq(document.display_name(), Document.UNTITLED)
	assert_true(document.is_dirty(), "and is offered for saving")
	assert_eq(document.root.child_count(), 1, "the tree it read is there")


func test_an_import_that_cannot_be_read_says_so_and_changes_nothing() -> void:
	var document := Document.new()
	document.root.children.append(Feature.create_feature("Craton"))
	document.record()
	var before := document.root.child_count()
	assert_true(not document.load_imported("user://no_such_import.middle-earth").is_empty(),
		"a missing file is reported")
	assert_eq(document.root.child_count(), before, "and the open document is untouched")
