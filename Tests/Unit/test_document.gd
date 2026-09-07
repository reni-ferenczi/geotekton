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
