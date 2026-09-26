extends TestCase

# The document owns the tree, the path and the dirty flag. The dirty flag comes
# from the undo stack, so it has to survive undo, redo, save and load.

const SAMPLE := "res://Tests/Data/two_cratons.geotekt"
const SCRATCH := "user://test_document.geotekt"
# Where the crust colour preference is written while it is being tested, so the
# real settings file is left alone.
const CONFIG_SCRATCH := "user://test_document_config"


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
	assert_eq(document.display_name(), "two_cratons.geotekt")
	assert_true(not document.can_undo(), "loading resets the undo stack")
	assert_eq(document.root.children[0].child_count(), 3, "the three cratons are there")


func test_loading_a_file_that_is_not_one_reports_why() -> void:
	var document := Document.new()
	assert_true(not document.load_from_file("res://Tests/Data/nothing-here").is_empty(),
		"a missing file is reported")
	assert_true(not document.load_from_file("res://project.godot").is_empty(),
		"a file that is not JSON is reported")
	assert_true(not document.is_dirty(), "a failed load leaves the document alone")


# A file that names some other program in its application field is turned
# away, and the message says whose file it is not.
func test_a_file_naming_another_program_is_refused() -> void:
	var document := Document.new()
	var path := ProjectSettings.globalize_path(SCRATCH)
	for application in [Document.APPLICATION, "some-other-program"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"application": application, "version": "0.27.0",
			"features": {"type": "Group", "is_group": true, "title": "Planet", "children": []}}))
		file.close()
		var error := document.load_from_file(path)
		if application == Document.APPLICATION:
			assert_eq(error, "", "a file saying geotekt opens")
		else:
			assert_true(error.contains("not a Geotekton file"),
				"any other name is refused, naming the program: %s" % error)
	DirAccess.remove_absolute(path)


func test_saving_makes_it_clean_and_writes_what_loads_back() -> void:
	var document := Document.new()
	document.root.children.append(Feature.create_feature("Craton"))
	document.record()

	assert_eq(document.save_to_file(SCRATCH), "", "the document is written")
	assert_true(not document.is_dirty(), "saving makes the document clean")
	assert_eq(document.path, SCRATCH)
	assert_eq(document.display_name(), "test_document.geotekt")

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
	assert_true(not document.load_imported("user://no_such_import.geotekt").is_empty(),
		"a missing file is reported")
	assert_eq(document.root.child_count(), before, "and the open document is untouched")


### The ridge and crust a split leaves


const CRUST_TITLES := ["Square", "Square 2", "Square ridge", "Square crust",
	"Square 2 crust"]


# A square split at 100 Ma with Ridge and Crust on, the halves drifting apart
# from there, one faster and both sliding along the cut, so that the half stage
# rotation is not the identity.
func _split_square(drift: bool) -> Document:
	var document := Document.new()
	var square := Feature.create_feature("Square")
	square.add_ring(PackedVector2Array([Vector2(-10, -10), Vector2(-10, 10),
		Vector2(10, 10), Vector2(10, -10)]), Feature.GeometryKind.POLYGON)
	document.root.children.append(square)
	document.current_time = 100.0
	document.record()
	assert_eq(document.split_feature_along(square, 0,
		PackedVector2Array([Vector2(-11, 0), Vector2(0, 2), Vector2(11, 0)]), true, true), "")
	if drift:
		for index in [0, 1]:
			var half: Feature = document.root.children[index]
			var west := _mean_longitude(half.rings[0]) < 0.0
			assert_eq(document.set_keyframe(half, 100.0, Vector3.ZERO), "")
			assert_eq(document.set_keyframe(half, 0.0,
				Vector3(20, 0, 4) if west else Vector3(-15, 0, -3)), "")
	return document


func _world(document: Document, node: Feature, ring: PackedVector2Array,
		time: float) -> PackedVector2Array:
	return Feature.apply_basis(ring, Feature.world_basis(document.root, node, time))


func _assert_same_ring(actual: PackedVector2Array, expected: PackedVector2Array,
		tolerance: float, message: String) -> void:
	assert_eq(actual.size(), expected.size(), "%s: the vertex count" % message)
	for i in mini(actual.size(), expected.size()):
		assert_true(actual[i].distance_to(expected[i]) <= tolerance,
			"%s: vertex %d is %s, not %s" % [message, i, actual[i], expected[i]])


func test_a_split_with_ridge_and_crust_leaves_five_features_in_order() -> void:
	var document := _split_square(false)
	assert_eq(document.root.children.map(func(n: Feature) -> String: return n.title),
		CRUST_TITLES, "the halves, the ridge and one crust for each half")
	var ridge: Feature = document.root.children[2]
	assert_true(ridge.midway and ridge.geometry_kind == Feature.GeometryKind.TOPOLOGY,
		"the ridge is a midway topology")
	assert_eq(ridge.feature_type, "topology", "typed as one")
	assert_eq(ridge.keyframes.size() + ridge.couplings.size(), 0, "with no motion of its own")
	assert_eq(ridge.sections.size(), 2, "between two sections")
	assert_eq(ridge.time_range, Vector2i(0, 100), "from the split to the present")
	for index in [3, 4]:
		var crust: Feature = document.root.children[index]
		assert_true(crust.is_crust() and crust.closed, "a crust")
		assert_eq(crust.color, FeatureType.color(FeatureType.CRUST), "in the crust colour")
		assert_eq(crust.line_color(crust.color),
			FeatureType.color(FeatureType.CRUST_LINES), "with its lines in theirs")
		assert_eq(crust.line_scale(), Feature.CRUST_LINE_SCALE, "and drawn thin")
		assert_eq(crust.time_range, Vector2i(0, 100), "over the ridge's time range")
		assert_eq(crust.crust_ridge, ridge.uuid, "opened by the ridge")
		assert_eq(crust.crust_half, document.root.children[index - 3].uuid, "beside its half")
		assert_eq(crust.crust_edge, 3, "along a cut of three vertices")
	var data: Dictionary = document.root.children[3].to_json()
	assert_eq(data.get("crust"), {"half": document.root.children[0].uuid, "ridge": ridge.uuid,
		"edge": 3}, "a crust writes what it is built from")
	assert_eq(Feature.from_json(data).crust_ridge, ridge.uuid, "and reads it back")
	document.undo()
	assert_eq(document.root.children.size(), 1, "one undo puts the square back")


func test_the_ridge_is_the_half_stage_line() -> void:
	var document := _split_square(true)
	var first: Feature = document.root.children[0]
	var second: Feature = document.root.children[1]
	var ridge: Feature = document.root.children[2]
	# The line the 0.22.0 ridge was: the cut carried by the half stage rotation.
	var half := Basis(Quaternion(Feature.world_basis(document.root, first, 50.0)).slerp(
		Quaternion(Feature.world_basis(document.root, second, 50.0)), 0.5))
	var expected := Feature.apply_basis(first.rings[0].slice(0, 3), half)
	_assert_same_ring(Ridge.ring_at(document.root, ridge, 50.0), expected, 1e-6,
		"the ridge at 50 Ma")
	Topology.rebuild(document.root, ridge, 50.0)
	_assert_same_ring(ridge.rings[0], expected, 1e-6, "and as rebuilt")


func test_the_crust_is_bands_between_isochrons_at_the_skip() -> void:
	var document := _split_square(true)
	var root := document.root
	for index in [3, 4]:
		var crust: Feature = root.children[index]
		var half: Feature = root.get_node_by_uuid(crust.crust_half)
		Crust.rebuild(root, crust, 0.0, 25.0)
		var lines := crust.crust_line_rings
		assert_eq(crust.rings.size(), 4, "%s: four bands from 100 Ma at 25 My" % crust.title)
		assert_eq(Crust.chunks(crust), 4, "counted as four chunks")
		assert_eq(crust.drawn_as(), Feature.GeometryKind.POLYGON, "drawn as a polygon")
		assert_eq(lines.size(), 5 + 3, "with five isochrons and three flowlines over them")

		# The oldest band is against the continent: its outer isochron is the cut.
		var cut := _world(document, half, half.rings[0].slice(0, 3), 0.0)
		var outer := lines[0]
		var matches := outer.duplicate()
		if outer[0].distance_to(cut[0]) > outer[0].distance_to(cut[2]):
			matches.reverse()
		_assert_same_ring(matches, cut, 1e-3, "%s: the oldest isochron" % crust.title)
		_assert_same_ring(crust.rings[0].slice(0, 3), outer, 1e-9,
			"%s: the first band starts on it" % crust.title)
		var ridge := Ridge.ring_at(root, root.children[2], 0.0)
		_assert_same_ring(lines[4], ridge, 1e-3, "%s: the youngest is the ridge" % crust.title)
		for i in 3:
			assert_eq(lines[5 + i].size(), 5, "a flowline crosses every isochron")
			assert_eq(lines[5 + i][0], outer[i], "from the continent")
			assert_eq(lines[5 + i][4], lines[4][i], "to the ridge")

		# The bands tile the sea floor between the cut and the ridge, which is
		# bounded by the flowlines of the cut's two ends.
		var whole := Feature.create_feature("Whole")
		var ring := outer.duplicate()
		ring.append_array(lines[7].slice(1, 4))
		var back := lines[4].duplicate()
		back.reverse()
		ring.append_array(back)
		var first_flowline := lines[5].slice(1, 4)
		first_flowline.reverse()
		ring.append_array(first_flowline)
		whole.add_ring(ring, Feature.GeometryKind.POLYGON)
		var total := Measure.geometry_area(crust)
		assert_true(total > 0.0, "%s has an area" % crust.title)
		assert_close(total, Measure.geometry_area(whole), 1e-6 * total,
			"%s: the bands add up to the sea floor" % crust.title)

		Crust.rebuild(root, crust, 100.0, 25.0)
		for band in crust.rings:
			assert_close(Measure.ring_area(band), 0.0, 1e-3, "no band has an area at the split")
		assert_eq(Crust.chunks(crust), 0, "and there are none")
		assert_eq(crust.crust_line_rings.size(), 1, "with the one isochron and no flowline")
		Crust.rebuild(root, crust, 0.0, 50.0)
		assert_eq(Crust.chunks(crust), 2, "a longer skip gives fewer chunks")


# The step on the crust wins over the Skip the rebuild is handed, so the same
# file opens with the same bands wherever the Skip happens to sit.
func test_a_crust_samples_at_its_own_step() -> void:
	var document := _split_square(true)
	var root := document.root
	document.current_time = 0.0
	var crust: Feature = root.children[3]
	var versions := document.applied
	assert_eq(document.set_crust_step(crust, 25.0), "", "the crust takes a 25 My step")
	assert_eq(document.applied, versions + 1, "as one undo version")
	for skip: float in [1.0, 10.0, 50.0]:
		Crust.rebuild_all(root, 0.0, skip)
		assert_eq(Crust.chunks(crust), 4,
			"four bands over the 100 My range at a skip of %s" % skip)
		assert_eq(crust.crust_line_rings.size(), 5 + 3,
			"with five isochrons and three flowlines")
	# The other half is still on the Skip, so it follows it.
	var other: Feature = root.children[4]
	assert_eq(other.time_step, 0.0, "the other crust carries no step")
	assert_eq(Crust.chunks(other), 2, "so a skip of 50 leaves it two bands")

	assert_eq(document.set_crust_step(crust, 0.0), "", "back to the Skip")
	Crust.rebuild_all(root, 0.0, 50.0)
	assert_eq(Crust.chunks(crust), 2, "and it follows it again")
	assert_true(not document.set_crust_step(root.children[2], 25.0).is_empty(),
		"the ridge is no crust")
	assert_true(not document.set_crust_step(crust, -1.0).is_empty(), "nor is -1 a step")

	var data: Dictionary = crust.to_json()
	assert_true(not data.has("time_step"), "a crust on the Skip writes no step")
	document.set_crust_step(crust, 25.0)
	assert_eq(Feature.from_json(crust.to_json()).time_step, 25.0, "one with a step round trips")


func test_the_crust_shape_is_its_bands() -> void:
	var document := _split_square(true)
	document.current_time = 0.0
	var geometry := Planet.collect_geometry(document.root, 0.0)
	var crust: Feature = document.root.children[3]
	var shape := document.shape_of(crust)
	assert_eq(shape["kind"], Feature.GeometryKind.POLYGON, "Copy Shape takes a polygon")
	assert_eq(shape["rings"].size(), crust.rings.size(), "of the bands")

	# The bands are triangles and the isochrons and flowlines segments, all of
	# the one feature, over the column each band takes.
	var columns := _columns_of(geometry, crust)
	assert_eq(columns.size(), crust.rings.size(), "a column of the feature rows per band")
	assert_eq(columns[0], geometry.index_for(crust), "the oldest band is where the crust is found")
	var kinds := {}
	for column: int in columns:
		for i in range(geometry.starts[column], geometry.ends[column]):
			kinds[geometry.primitives[i]["kind"]] = true
	assert_eq(kinds.keys().size(), 2, "the crust draws two kinds of primitive")
	assert_true(kinds.has(Planet.Primitive.TRIANGLE) and kinds.has(Planet.Primitive.SEGMENT),
		"filled bands and drawn lines")
	shape = document.shape_of(document.root.children[2])
	assert_eq(shape["kind"], Feature.GeometryKind.POLYLINE, "and a line from the ridge")
	assert_eq(shape["rings"].size(), 1, "of one ring")
	assert_true(not document.set_topology_closed(crust, false).is_empty(),
		"a crust cannot be opened")
	assert_true(not document.add_section(crust, document.root.children[0], 0).is_empty(),
		"nor take a section")
	assert_true(not document.add_section(document.root.children[2],
		document.root.children[0], 0).is_empty(), "nor a ridge a third one")


# The columns of the feature rows one feature was given, in order. Only a crust
# takes more than one: one per band, so each can be colored on its own.
func _columns_of(geometry: Planet.Geometry, feature: Feature) -> Array[int]:
	var columns: Array[int] = []
	for index in geometry.features.size():
		if geometry.features[index] == feature:
			columns.append(index)
	return columns


# A crust with a step of its own, so the bands do not follow the Skip of
# whatever machine the test runs on, and the geometry collected from it.
func _crust_geometry(document: Document, crust: Feature, styling: Styling = null) -> Planet.Geometry:
	assert_eq(document.set_crust_step(crust, 25.0), "", "the crust samples every 25 My")
	return Planet.collect_geometry(document.root, document.current_time, styling)


# GP-0103: the bands are colored by the age of the crust in them. The oldest
# band, the one lying against the continent, keeps the crust's own color, and
# each younger band towards the ridge is a lighter shade of it.
func test_the_bands_are_colored_by_the_age_of_the_crust() -> void:
	var document := _split_square(true)
	document.current_time = 0.0
	var crust: Feature = document.root.children[3]
	var geometry := _crust_geometry(document, crust)
	assert_eq(Array(crust.band_ages), [100.0, 75.0, 50.0, 25.0],
		"the band ages run oldest at the continent to youngest at the ridge")
	assert_eq(crust.ring_triangles.size(), 4, "with every band triangulated on its own")

	var columns := _columns_of(geometry, crust)
	var base := FeatureType.color(FeatureType.CRUST)
	assert_eq(columns.size(), 4, "a column of the feature rows per band")
	assert_eq(geometry.colors[columns[0]], base, "the oldest band is the crust colour itself")
	assert_eq(geometry.colors[columns[3]], base.lightened(Styling.YOUNGEST_LIGHTER),
		"and the youngest the lightest shade of it")
	for k in columns.size() - 1:
		assert_true(geometry.colors[columns[k]].v < geometry.colors[columns[k + 1]].v,
			"band %d is darker than the one nearer the ridge" % k)
	for column: int in columns:
		assert_eq(geometry.line_colors[column], FeatureType.color(FeatureType.CRUST_LINES),
			"while the isochrons and the flowlines keep their own colour")


# Under the age style each band is read from the palette at its own age, the way
# an age grid is painted, rather than the whole crust at the age of the split.
func test_the_age_style_paints_each_band_at_its_own_age() -> void:
	var document := _split_square(true)
	document.current_time = 0.0
	var from := Color(1.0, 0.0, 0.0, 1.0)
	var to := Color(0.0, 0.0, 1.0, 1.0)
	document.root.style.mode = Styling.BY_AGE
	document.root.style.palette = Palette.RAMP
	document.root.style.ramp_colors = [from, to]
	document.root.style.ramp_span = 200.0
	var crust: Feature = document.root.children[3]
	var geometry := _crust_geometry(document, crust,
		Styling.of(ViewSettings.new(), document.root))
	var columns := _columns_of(geometry, crust)
	assert_eq(columns.size(), 4, "the four bands are drawn")
	for k in columns.size():
		var age: float = crust.band_ages[k]
		assert_close(geometry.colors[columns[k]], from.lerp(to, age / 200.0), 1e-5,
			"the band holding crust %s My old" % age)


# The crust colour preference sets the old end of the ramp: a crust starts in
# the colour the preference holds, and every band is a shade of that.
func test_the_crust_colour_preference_moves_the_whole_ramp() -> void:
	var kept := Config.directory_override
	Config.directory_override = ProjectSettings.globalize_path(CONFIG_SCRATCH)
	DirAccess.make_dir_recursive_absolute(Config.directory_override)
	DirAccess.remove_absolute(Config.directory_override + "/config.json")
	Config.forget()
	var picked := Color(0.7, 0.3, 0.1, 1.0)
	Config.set_feature_colors({FeatureType.CRUST: picked})

	var document := _split_square(true)
	document.current_time = 0.0
	var crust: Feature = document.root.children[3]
	var geometry := _crust_geometry(document, crust)
	var columns := _columns_of(geometry, crust)
	assert_eq(crust.color, picked, "the crust starts in the colour the preference holds")
	assert_eq(columns.size(), 4, "in four bands")
	for k in columns.size():
		assert_eq(geometry.colors[columns[k]],
			Styling.lighter_band(picked, float(k) / 3.0),
			"band %d is a shade of the picked colour" % k)

	DirAccess.remove_absolute(Config.directory_override + "/config.json")
	Config.directory_override = kept
	Config.forget()


### The children a split takes along


func _square(title: String, half_size: float, center := Vector2.ZERO) -> Feature:
	var square := Feature.create_feature(title)
	square.add_ring(PackedVector2Array([center + Vector2(-half_size, -half_size),
		center + Vector2(-half_size, half_size), center + Vector2(half_size, half_size),
		center + Vector2(half_size, -half_size)]), Feature.GeometryKind.POLYGON)
	return square


func _titled(document: Document, title: String) -> Feature:
	for node in document.root.children:
		if node.title == title:
			return node
	return null


# A craton split north to south at 100 Ma, with whatever follows it from 200 Ma.
func _split_with(children: Array[Feature], on: bool) -> Document:
	var document := Document.new()
	var craton := _square("Craton", 10.0)
	document.root.children.append(craton)
	for child in children:
		document.root.children.append(child)
		assert_eq(document.couple(child, craton, 200.0), "")
	document.current_time = 100.0
	document.record()
	assert_eq(document.split_feature_along(craton, 0,
		PackedVector2Array([Vector2(-11, 0), Vector2(11, 0)]), false, false, on), "")
	return document


func _follows(node: Feature, time: float) -> String:
	return Coupling.span_at(node, time).parent


func _west(node: Feature) -> bool:
	return _mean_longitude(node.rings[0]) < 0.0


func _world_ring(document: Document, node: Feature, time: float) -> PackedVector2Array:
	return Feature.apply_basis(node.rings[0], Feature.world_basis(document.root, node, time))


# Whether the middle of the node falls inside the half, both where they stand.
func _sits_on(document: Document, node: Feature, half: Feature, time: float) -> bool:
	var middle := Feature.world_basis(document.root, node, time) * Kinematics.centroid(node)
	return Geometry2D.is_point_in_polygon(Feature._xyz_to_latlon_s(middle),
		_world_ring(document, half, time))


func test_a_split_with_children_splits_a_child_the_cut_crosses() -> void:
	var document := _split_with([_square("Range", 5.0)] as Array[Feature], true)
	assert_eq(document.root.children.map(func(n: Feature) -> String: return n.title),
		["Craton", "Craton 2", "Range", "Range 2"], "the child is split beside itself")
	assert_eq(document.split_children.map(func(n: Feature) -> String: return n.title),
		["Range", "Range 2"], "and named for the status bar")
	document.undo()
	assert_eq(document.root.children.size(), 2, "one undo takes the whole split back")
	document.redo()
	var craton := _titled(document, "Craton")
	var second := _titled(document, "Craton 2")
	for title in ["Range", "Range 2"]:
		var piece := _titled(document, title)
		if _west(piece) == _west(second):
			assert_eq(piece.couplings.size(), 2, "%s follows over two spans" % title)
		var far := _west(piece) == _west(second)
		assert_eq(_follows(piece, 0.0), second.uuid if far else craton.uuid,
			"%s follows the half on its side" % title)
		assert_eq(_follows(piece, 150.0), craton.uuid,
			"%s follows the original before the split" % title)
		assert_eq(_follows(piece, 100.0), second.uuid if far else craton.uuid,
			"%s from the split age" % title)

	# The halves drift apart and each piece of the range goes with its own half.
	for half in [craton, second]:
		assert_eq(document.set_keyframe(half, 100.0, Vector3.ZERO), "")
		assert_eq(document.set_keyframe(half, 0.0, Vector3(20.0 if _west(half) else -20.0, 0, 0)), "")
	for title in ["Range", "Range 2"]:
		var piece := _titled(document, title)
		var own := second if _follows(piece, 0.0) == second.uuid else craton
		var other := craton if own == second else second
		assert_true(_sits_on(document, piece, own, 0.0), "%s sits on its half at 0 Ma" % title)
		assert_true(not _sits_on(document, piece, other, 0.0), "and not on the other one")
		assert_true(_sits_on(document, piece, own, 100.0), "%s sat there at 100 Ma" % title)


func test_a_split_with_children_moves_a_child_whole_and_cuts_a_line() -> void:
	var line := Feature.create_feature("Fault")
	line.add_ring(PackedVector2Array([Vector2(0, -3), Vector2(0, 8)]),
		Feature.GeometryKind.POLYLINE)
	var document := _split_with(
		[_square("East", 2.0, Vector2(0, 5)), _square("West", 2.0, Vector2(0, -5)), line] 			as Array[Feature], true)
	assert_eq(document.root.children.size(), 6, "the craton and the fault are split")
	assert_eq(document.split_children.map(func(n: Feature) -> String: return n.title),
		["Fault", "Fault 2"], "and the fault's pieces named for the status bar")
	var craton := _titled(document, "Craton")
	var second := _titled(document, "Craton 2")
	var east := second if not _west(second) else craton
	var west := craton if east == second else second
	assert_eq(_follows(_titled(document, "East"), 0.0), east.uuid, "East follows the eastern half")
	assert_eq(_follows(_titled(document, "West"), 0.0), west.uuid, "West follows the western half")
	for title in ["Fault", "Fault 2"]:
		var piece := _titled(document, title)
		assert_eq(_follows(piece, 0.0), west.uuid if _west(piece) else east.uuid,
			"%s follows the half on its side" % title)


func test_a_split_without_children_leaves_them_following_the_original() -> void:
	var document := _split_with(
		[_square("Range", 5.0), _square("East", 2.0, Vector2(0, 5))] as Array[Feature], false)
	assert_eq(document.root.children.map(func(n: Feature) -> String: return n.title),
		["Craton", "Craton 2", "Range", "East"], "no child is split")
	var craton := _titled(document, "Craton")
	for title in ["Range", "East"]:
		var child := _titled(document, title)
		assert_eq(child.couplings.size(), 1, "%s keeps its one span" % title)
		assert_eq(_follows(child, 0.0), craton.uuid, "%s follows the original" % title)


func test_a_cut_is_clipped_to_the_ring_it_crosses() -> void:
	var ring := _square("Ring", 5.0).rings[0]
	var cut := GeometryEdit.clip_path(ring,
		PackedVector2Array([Vector2(-11, 0), Vector2(0, 1), Vector2(11, 0)]))
	var wanted := [Vector2(-5, 6.0 / 11.0), Vector2(0, 1), Vector2(5, 6.0 / 11.0)]
	assert_eq(cut.size(), wanted.size(), "from where the path goes in to where it comes out")
	for i in mini(cut.size(), wanted.size()):
		assert_true(cut[i].is_equal_approx(wanted[i]), "point %d: %s" % [i, cut[i]])
	assert_true(GeometryEdit.clip_path(ring,
		PackedVector2Array([Vector2(-11, 7), Vector2(11, 7)])).is_empty(),
		"a path that misses the ring cuts nothing")


func _mean_longitude(ring: PackedVector2Array) -> float:
	var total := 0.0
	for vertex in ring:
		total += vertex.y
	return total / ring.size()


### A second split of a half
#
# The square split west from east at 100 Ma with Ridge and Crust on, then its
# eastern half split again at 50 Ma. The ridge names each side of the first cut
# by a range of vertices, which the second split moves; GP-0122.


func _east_half(document: Document) -> Feature:
	for index in [0, 1]:
		var half: Feature = document.root.children[index]
		if not _west(half):
			return half
	return null


func _ridge_of(document: Document) -> Feature:
	return _titled(document, "Square ridge")


func _crust_of(document: Document, ridge: Feature, west: bool) -> Feature:
	for node in document.root.children:
		if node.is_crust() and node.crust_ridge == ridge.uuid:
			var half := document.root.get_node_by_uuid(node.crust_half)
			if half != null and _west(half) == west:
				return node
	return null


# A cut north to south through the eastern half, east of the first cut, in one
# direction or the other: which way it runs decides which piece keeps the title.
func _second_cut(northward: bool) -> PackedVector2Array:
	var path := PackedVector2Array([Vector2(-11, 6), Vector2(11, 6)])
	if not northward:
		path.reverse()
	return path


func _crust_areas(document: Document, ridge: Feature) -> Array:
	var areas := []
	for west in [true, false]:
		var crust := _crust_of(document, ridge, west)
		Crust.rebuild(document.root, crust, 0.0, 25.0)
		areas.append(Measure.geometry_area(crust))
	return areas


func test_a_second_split_keeps_the_older_ridge_on_the_first_cut() -> void:
	for northward in [true, false]:
		var document := _split_square(true)
		var ridge := _ridge_of(document)
		var before := {}
		for age in [100.0, 50.0, 0.0]:
			before[age] = Ridge.ring_at(document.root, ridge, age)
		var areas := _crust_areas(document, ridge)
		document.current_time = 50.0
		assert_eq(document.split_feature_along(_east_half(document), 0,
			_second_cut(northward)), "", "the second cut is made")
		for age in [100.0, 50.0, 0.0]:
			_assert_same_ring(Ridge.ring_at(document.root, ridge, age), before[age], 1e-3,
				"the older ridge at %s Ma" % age)
		var after := _crust_areas(document, ridge)
		for i in 2:
			assert_close(after[i], areas[i], 1.0, "crust %d keeps its area to the km²" % i)


func test_the_older_ridge_and_crust_move_to_the_piece_holding_the_first_cut() -> void:
	var in_copy := false
	for northward in [true, false]:
		var document := _split_square(false)
		var east := _east_half(document)
		var craton := _square("Craton", 1.0, Vector2(0, 8))
		document.root.children.append(craton)
		assert_eq(document.set_keyframe(craton, 100.0, Vector3.ZERO), "")
		assert_eq(document.set_keyframe(craton, 0.0, Vector3(0, 0, 10)), "")
		assert_eq(document.couple(east, craton, 100.0), "")
		var ridge := _ridge_of(document)
		var crust := _crust_of(document, ridge, false)
		var at := 0 if ridge.sections[0].feature_uuid == east.uuid else 1
		document.current_time = 50.0
		document.record()
		assert_eq(document.split_feature_along(east, 0, _second_cut(northward), false, false),
			"", "the second cut is made")
		var coast := document.split_freed
		assert_true(coast != null, "the piece west of the craton goes free")
		in_copy = in_copy or coast != east
		var section: TopologySection = ridge.sections[at]
		assert_eq(section.feature_uuid, coast.uuid, "the section names the piece with the cut")
		assert_eq(crust.crust_half, coast.uuid, "and so does the crust")
		# Whichever piece holds it, the crust's oldest isochron stays on the
		# coast it opened from, before and after that piece went free.
		for time in [75.0, 25.0, 0.0]:
			var lines := Crust.isochrons(document.root, crust, time, 25.0)
			var run: PackedVector2Array = coast.rings[section.part].slice(
				section.from_index, section.to_index + 1)
			if section.reversed:
				run.reverse()
			_assert_same_ring(lines[0], _world(document, coast, run, time), 1e-3,
				"the oldest isochron at %s Ma" % time)
		document.undo()
		ridge = _ridge_of(document)
		assert_eq(ridge.sections[at].feature_uuid, east.uuid, "undo puts the section back")
		assert_eq(_crust_of(document, ridge, false).crust_half, east.uuid,
			"and the crust's half")
	assert_true(in_copy, "one of the two directions leaves the first cut in the copy")


func test_a_second_cut_across_the_older_ridge_is_refused() -> void:
	var document := _split_square(true)
	var count := document.root.children.size()
	document.current_time = 50.0
	var east := _east_half(document)
	var ring := east.rings[0].duplicate()
	var problem := document.split_feature_along(east, 0,
		PackedVector2Array([Vector2(5, -1), Vector2(5, 11)]))
	assert_true(problem.contains("Square ridge"), "the cut names the ridge it crosses: %s" % problem)
	assert_eq(document.root.children.size(), count, "and nothing is split")
	assert_eq(east.rings[0], ring, "the half is untouched")


func test_the_vertex_tool_split_keeps_the_older_ridge_too() -> void:
	var document := _split_square(true)
	var ridge := _ridge_of(document)
	var before := Ridge.ring_at(document.root, ridge, 0.0)
	var east := _east_half(document)
	var size := east.rings[0].size()
	# From the last vertex of the cut to the corner two on, away from the cut.
	assert_eq(document.split_feature(east, 0, 2, (2 + 2) % size), "")
	_assert_same_ring(Ridge.ring_at(document.root, ridge, 0.0), before, 1e-6,
		"the older ridge after a Vertex tool split")


### A split under a craton
#
# The way the developers' worlds are built: the craton leads, and the continent
# around it and the orogeny across it both follow the craton. The continent is
# cut north to south east of the craton, through the orogeny.


func _craton_world() -> Document:
	var document := Document.new()
	var craton := _square("Craton", 3.0, Vector2(0, -12))
	var continent := _square("Continent", 20.0)
	var orogeny := _square("Orogeny", 4.0, Vector2(0, 0))
	var foothills := _square("Foothills", 1.0, Vector2(0, 3))
	var island := _square("Island", 1.0, Vector2(0, 26))
	document.root.children.append_array([craton, continent, orogeny, foothills, island])
	for rider in [continent, orogeny]:
		assert_eq(document.couple(rider, craton, 200.0), "")
	assert_eq(document.couple(foothills, orogeny, 200.0), "")
	assert_eq(document.couple(island, continent, 200.0), "")
	document.current_time = 100.0
	document.record()
	return document


func _cut_continent(document: Document, children := true) -> void:
	assert_eq(document.split_feature_along(_titled(document, "Continent"), 0,
		PackedVector2Array([Vector2(-21, 1), Vector2(21, 1)]), false, false, children), "")


func test_the_half_away_from_the_craton_goes_free_where_it_stands() -> void:
	var document := _craton_world()
	_cut_continent(document)
	var craton := _titled(document, "Craton")
	var west := _titled(document, "Continent")
	var east := _titled(document, "Continent 2")
	if not _west(west):
		var swap := west
		west = east
		east = swap
	assert_eq(_follows(west, 0.0), craton.uuid, "the half holding the craton follows it on")
	assert_eq(Coupling.span_at(east, 0.0), null, "the other half follows nothing after the split")
	assert_eq(_follows(east, 150.0), craton.uuid, "and still followed the craton before it")
	assert_eq(document.split_freed, east, "which the status bar is told")
	assert_eq(craton.rings[0].size(), 4, "the craton itself is not cut")


func test_a_sibling_the_cut_crosses_is_cut_and_each_piece_follows_its_side() -> void:
	var document := _craton_world()
	_cut_continent(document)
	var craton := _titled(document, "Craton")
	var free := document.split_freed
	for title in ["Orogeny", "Orogeny 2"]:
		var piece := _titled(document, title)
		assert_true(piece != null, "%s is there" % title)
		assert_eq(_follows(piece, 0.0), craton.uuid if _west(piece) else free.uuid,
			"%s follows the craton on its side, or the freed half" % title)
		assert_eq(_follows(piece, 150.0), craton.uuid, "%s followed the craton before" % title)


func test_what_follows_a_cut_sibling_follows_its_piece_on_that_side() -> void:
	var document := _craton_world()
	_cut_continent(document)
	var east_orogeny := _titled(document, "Orogeny 2")
	if _west(east_orogeny):
		east_orogeny = _titled(document, "Orogeny")
	assert_eq(_follows(_titled(document, "Foothills"), 0.0), east_orogeny.uuid,
		"the foothills east of the cut follow the orogeny's eastern piece")


func test_an_island_off_the_far_coast_goes_with_the_far_half() -> void:
	var document := _craton_world()
	_cut_continent(document)
	assert_eq(_follows(_titled(document, "Island"), 0.0), document.split_freed.uuid,
		"outside both halves, by the side of the cut it is on")


func test_without_children_only_the_continent_is_split_and_freed() -> void:
	var document := _craton_world()
	_cut_continent(document, false)
	assert_true(_titled(document, "Orogeny 2") == null, "the orogeny is left whole")
	assert_true(document.split_freed != null, "the far half still goes free")


func test_the_parts_the_cut_misses_go_by_side() -> void:
	var document := Document.new()
	var land := _square("Land", 10.0)
	land.add_ring(_square("East isle", 2.0, Vector2(0, 20)).rings[0], Feature.GeometryKind.POLYGON)
	land.add_ring(_square("West isle", 2.0, Vector2(0, -20)).rings[0], Feature.GeometryKind.POLYGON)
	document.root.children.append(land)
	document.record()
	assert_eq(document.split_feature_along(land, 0,
		PackedVector2Array([Vector2(-11, 0), Vector2(11, 0)])), "")
	for node in [land, _titled(document, "Land 2")]:
		assert_eq(node.rings.size(), 2, "%s holds its half and the isle on its side" % node.title)
		for ring in node.rings:
			assert_eq(_mean_longitude(ring) < 0.0, _west(node), "all on one side")


func test_a_divide_across_the_dateline_sends_each_part_to_its_side() -> void:
	var document := Document.new()
	var isles := _square("Isles", 2.0, Vector2(0, 176))
	isles.add_ring(_square("Far", 2.0, Vector2(0, -176)).rings[0], Feature.GeometryKind.POLYGON)
	document.root.children.append(isles)
	document.record()
	assert_eq(document.divide_feature(isles,
		PackedVector2Array([Vector2(-10, 180), Vector2(10, 180)])), "")
	var far := _titled(document, "Isles 2")
	assert_eq(isles.rings.size(), 1, "one isle stays")
	assert_true(far != null and far.rings.size() == 1, "and the other goes")
	assert_true(_mean_longitude(far.rings[0]) < 0.0, "the one across 180°")
