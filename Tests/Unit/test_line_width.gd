extends TestCase

# A feature's line width: a multiple of what its type draws at, set in the
# Properties panel, saved with the feature, and started from the Default line
# width preference. See Feature.line_scale() and Document.set_line_width().

const SCRATCH_CONFIG := "user://test_line_width_config"


# A config of the test's own, so the preference under test is the one the
# test set rather than whatever the machine holds. _done() drops it.
func _own_config() -> void:
	Config.directory_override = ProjectSettings.globalize_path(SCRATCH_CONFIG)
	Config.clear()


func _done() -> void:
	DirAccess.remove_absolute(Config.directory_override + "/config.json")
	Config.directory_override = ""
	Config.forget()


func _line(title: String = "Fault") -> Feature:
	var line := Feature.create_feature(title)
	line.add_ring(PackedVector2Array([Vector2(0, 0), Vector2(0, 10)]),
		Feature.GeometryKind.POLYLINE)
	return line


func test_the_width_multiplies_what_the_type_draws_at() -> void:
	_own_config()
	var line := _line()
	assert_eq(line.line_scale(), 1.0, "a line at 1 is drawn at the full width")
	line.line_width = 2.0
	assert_close(line.line_scale(), 2.0, 1e-12, "and at 2 twice as wide")
	var circle := Feature.create_feature("Ring")
	circle.feature_type = FeatureType.CIRCLE
	circle.line_width = 2.0
	assert_close(circle.line_scale(), Feature.CIRCLE_LINE_SCALE * 2.0, 1e-12,
		"a circle keeps its own thinness under the width")
	assert_close(circle.type_line_scale(), Feature.CIRCLE_LINE_SCALE, 1e-12,
		"which is what the type alone draws at")
	_done()


func test_only_what_is_drawn_with_lines_has_a_width_to_set() -> void:
	_own_config()
	var document := Document.new()
	var line := _line()
	var polygon := Feature.create_feature("Plate")
	polygon.add_ring(PackedVector2Array([Vector2(-10, -10), Vector2(-10, 10), Vector2(10, 0)]),
		Feature.GeometryKind.POLYGON)
	var points := Feature.create_feature("Volcanoes")
	points.add_ring(PackedVector2Array([Vector2(1, 1)]), Feature.GeometryKind.MULTIPOINT)
	var empty := Feature.create_feature("Nothing yet")
	var group := Feature.create_group("Group")
	document.root.children.append_array([line, polygon, points, empty, group])
	document.record()

	assert_true(line.draws_lines(), "a polyline is drawn with lines")
	assert_true(not polygon.draws_lines(), "a polygon is a fill")
	assert_true(not points.draws_lines(), "a multipoint is dots")
	assert_true(not group.draws_lines(), "a group draws nothing")
	assert_true(not empty.draws_lines(), "an empty feature is a Polygon until typed")
	assert_eq(document.set_feature_type(empty, FeatureType.LINE), "", "typed Line")
	assert_true(empty.draws_lines(), "an empty Line will be drawn with lines")
	assert_eq(document.set_feature_type(empty, FeatureType.HOTSPOT), "", "typed Hotspot")
	assert_true(empty.draws_lines(), "and so will a hotspot's mark and track")

	assert_eq(document.set_line_width(line, 2.0), "", "a line takes a width")
	assert_eq(line.line_width, 2.0, "and holds it")
	assert_true(document.set_line_width(polygon, 2.0).contains("polygon"),
		"a polygon is refused, saying why")
	assert_eq(polygon.line_width, 1.0, "and is left alone")
	assert_true(document.set_line_width(group, 2.0).contains("Only a feature"), "so is a group")
	assert_true(document.set_line_width(line, 0.0).contains("outside"),
		"a width below the range is refused")
	assert_true(document.set_line_width(line, Feature.MAX_LINE_WIDTH + 1.0).contains("outside"),
		"and so is one above it")
	assert_eq(line.line_width, 2.0, "leaving the width where it was")
	_done()


func test_a_closed_topology_has_no_lines_and_an_open_one_has() -> void:
	_own_config()
	var document := Document.new()
	var plate := Feature.create_feature("Plate")
	plate.add_ring(PackedVector2Array([Vector2(-10, -10), Vector2(-10, 10), Vector2(10, 0)]),
		Feature.GeometryKind.POLYGON)
	var boundary := Feature.create_feature("Boundary")
	document.root.children.append_array([plate, boundary])
	document.record()
	assert_eq(document.set_feature_type(boundary, "topology"), "", "typed Topology")
	assert_true(boundary.draws_lines(), "an empty topology is drawn as a line")
	assert_eq(document.add_section(boundary, plate, 0), "", "with a section")
	assert_true(boundary.draws_lines(), "an open topology is drawn as a line")
	assert_eq(document.set_line_width(boundary, 3.0), "", "and takes a width")
	assert_eq(document.set_topology_closed(boundary, true), "", "closed")
	assert_true(not boundary.draws_lines(), "a closed topology is a fill")
	assert_true(document.set_line_width(boundary, 2.0).contains("closed topology"),
		"and is refused a width, saying so")
	assert_eq(boundary.line_width, 3.0, "keeping the one it had for when it is opened again")
	_done()


func test_each_edit_is_one_undo_version() -> void:
	_own_config()
	var document := Document.new()
	var line := _line()
	document.root.children.append(line)
	document.record()
	var depth: int = document.applied
	assert_eq(document.set_line_width(line, 1.5), "")
	assert_eq(document.set_line_width(line, 2.5), "")
	assert_eq(document.applied, depth + 2, "two edits, two versions")
	document.undo()
	assert_eq(document.root.children[0].line_width, 1.5, "undo takes one back")
	document.undo()
	assert_eq(document.root.children[0].line_width, 1.0, "and the other")
	_done()


func test_the_width_is_cloned_and_written_only_when_it_is_not_one() -> void:
	_own_config()
	var line := _line()
	assert_true(not line.to_json().has("line_width"), "a line at 1 writes no key")
	line.line_width = 0.5
	assert_eq(line.to_json()["line_width"], 0.5, "one at 0.5 writes it")
	assert_eq(line.clone().line_width, 0.5, "a clone carries it")
	assert_eq(line.duplicate().line_width, 0.5, "and so does a duplicate")
	var back := Feature.from_json(line.to_json())
	assert_eq(back.line_width, 0.5, "and it reads back")
	var wild: Dictionary = line.to_json()
	wild["line_width"] = 100.0
	assert_eq(Feature.from_json(wild).line_width, Feature.MAX_LINE_WIDTH,
		"a width a file holds outside the range is brought into it")
	_done()


func test_a_new_feature_starts_at_the_default_line_width_preference() -> void:
	_own_config()
	assert_eq(Config.get_default_line_width(), 1.0, "a fresh installation starts features at 1")
	Config.set_default_line_width(2.0)
	assert_eq(Feature.create_feature("New").line_width, 2.0,
		"a new feature starts at the preference")
	var line := _line("Old")
	Config.set_default_line_width(3.0)
	assert_eq(line.line_width, 2.0, "a feature keeps its own width when the preference changes")
	var raw: Dictionary = line.to_json()
	raw.erase("line_width")
	assert_eq(Feature.from_json(raw).line_width, 1.0,
		"and a file without the key reads as 1, not as the preference")
	Config.set_default_line_width(100.0)
	assert_eq(Config.get_default_line_width(), Feature.MAX_LINE_WIDTH,
		"the preference is held to the range")
	Config.forget()
	assert_eq(Config.get_default_line_width(), Feature.MAX_LINE_WIDTH, "and survives a reload")
	_done()
