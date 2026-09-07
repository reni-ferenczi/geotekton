extends TestCase

# The document editing API the Properties panel goes through: what it accepts,
# what it refuses, and that one edit is one undo version.


# A document holding one polygon feature, ready to be edited.
func _document(kind: Feature.GeometryKind = Feature.GeometryKind.POLYGON) -> Document:
	var document := Document.new()
	var feature := Feature.create_feature("Laurentia")
	feature.add_ring(PackedVector2Array([
		Vector2(0, 0), Vector2(10, 5), Vector2(0, 10)]), kind)
	document.root.children.append(feature)
	document.record()
	return document


func _feature(document: Document) -> Feature:
	return document.root.children[0]


### Titles, colours and switches


func test_a_rename_is_one_undo_version() -> void:
	var document := _document()
	var versions := document.applied
	document.rename(_feature(document), "Baltica")
	assert_eq(_feature(document).title, "Baltica")
	assert_eq(document.applied, versions + 1, "the rename recorded exactly one version")
	document.undo()
	assert_eq(_feature(document).title, "Laurentia", "undo brings the old name back")


func test_a_long_title_is_cut_down_the_way_the_tree_cuts_it() -> void:
	var document := _document()
	var long_title := "a".repeat(Feature.MAX_TITLE_LENGTH + 20)
	document.rename(_feature(document), long_title)
	assert_eq(_feature(document).title, Feature.clamp_title(long_title))
	assert_eq(_feature(document).title.length(), Feature.MAX_TITLE_LENGTH + 3,
		"the cut title ends in the ellipsis the tree adds")


func test_disabling_a_group_collapses_it() -> void:
	var document := _document()
	var group := Feature.create_group("Cratons")
	document.root.children.append(group)
	document.set_enabled(group, false)
	assert_true(not group.enabled)
	assert_true(group.collapsed, "a disabled group is collapsed, as in the tree")


func test_a_colour_change_is_one_undo_version() -> void:
	var document := _document()
	var versions := document.applied
	document.set_color(_feature(document), Color.MAGENTA)
	assert_eq(_feature(document).color, Color.MAGENTA)
	assert_eq(document.applied, versions + 1)


### Types


func test_a_type_that_allows_the_kind_keeps_the_geometry() -> void:
	var document := _document()
	var before := _feature(document).rings.duplicate(true)
	assert_eq(document.set_feature_type(_feature(document), "craton"), "",
		"a polygon may be a craton")
	assert_eq(_feature(document).feature_type, "craton")
	assert_eq(_feature(document).rings, before, "the geometry is untouched")


func test_a_type_that_forbids_the_kind_is_refused() -> void:
	var document := _document()
	var versions := document.applied
	var error := document.set_feature_type(_feature(document), "ridge")
	assert_true(not error.is_empty(), "a polygon cannot be a ridge, which is a polyline")
	assert_eq(_feature(document).feature_type, FeatureType.UNCLASSIFIED,
		"the refused type was not applied")
	assert_eq(document.applied, versions, "and nothing was recorded")


func test_a_feature_without_geometry_may_take_any_type() -> void:
	var document := Document.new()
	var feature := Feature.create_feature("Empty")
	document.root.children.append(feature)
	for type_id in FeatureType.CATALOG:
		assert_eq(document.set_feature_type(feature, type_id), "",
			"nothing is drawn yet, so %s is allowed" % type_id)


func test_an_unknown_type_is_refused() -> void:
	var document := _document()
	assert_true(not document.set_feature_type(_feature(document), "volcano").is_empty())
	assert_eq(_feature(document).feature_type, FeatureType.UNCLASSIFIED)


func test_the_colour_follows_the_type_until_someone_picks_one() -> void:
	var document := _document()
	document.set_feature_type(_feature(document), "craton")
	assert_eq(_feature(document).color, FeatureType.color("craton"),
		"the default colour follows the type")

	document.set_color(_feature(document), Color.MAGENTA)
	document.set_feature_type(_feature(document), "terrane")
	assert_eq(_feature(document).color, Color.MAGENTA,
		"a colour someone picked is not overwritten by the next type")


### Time range


func test_a_time_range_that_ends_before_it_starts_is_refused() -> void:
	var document := _document()
	var before := _feature(document).time_range
	var versions := document.applied
	assert_true(not document.set_time_range(_feature(document), Vector2i(900, 100)).is_empty())
	assert_eq(_feature(document).time_range, before, "the refused range was not applied")
	assert_eq(document.applied, versions, "and nothing was recorded")

	assert_eq(document.set_time_range(_feature(document), Vector2i(100, 900)), "")
	assert_eq(_feature(document).time_range, Vector2i(100, 900))
	assert_eq(document.set_time_range(_feature(document), Vector2i(500, 500)), "",
		"a range of a single moment is allowed")


### Coordinates


func test_moving_a_vertex_re_triangulates_and_records_one_version() -> void:
	var document := _document()
	var versions := document.applied
	assert_eq(document.set_vertex(_feature(document), 0, 1, Vector2(20, 5)), "")
	assert_eq(_feature(document).rings[0][1], Vector2(20, 5))
	assert_true(Vector2(20, 5) in _feature(document).triangles,
		"the triangles were derived again from the moved ring")
	assert_eq(document.applied, versions + 1, "the edit recorded exactly one version")

	document.undo()
	assert_eq(_feature(document).rings[0][1], Vector2(10, 5), "undo puts the vertex back")
	assert_true(Vector2(10, 5) in _feature(document).triangles,
		"and the triangles with it")


func test_a_vertex_off_the_planet_is_refused() -> void:
	var document := _document()
	assert_true(not document.set_vertex(_feature(document), 0, 0, Vector2(120, 0)).is_empty(),
		"latitude 120 is not on the planet")
	assert_true(not document.set_vertex(_feature(document), 0, 0, Vector2(0, 200)).is_empty(),
		"longitude 200 is not on the planet")
	assert_eq(_feature(document).rings[0][0], Vector2(0, 0), "neither was applied")


func test_a_vertex_of_a_part_that_is_not_there_is_refused() -> void:
	var document := _document()
	assert_true(not document.set_vertex(_feature(document), 1, 0, Vector2(0, 0)).is_empty())
	assert_true(not document.set_vertex(_feature(document), 0, 9, Vector2(0, 0)).is_empty())
	assert_true(not document.remove_vertex(_feature(document), 0, 9).is_empty())


func test_a_vertex_can_be_inserted_and_appended() -> void:
	var document := _document()
	assert_eq(document.insert_vertex(_feature(document), 0, 1, Vector2(5, 2)), "")
	assert_eq(_feature(document).rings[0][1], Vector2(5, 2))
	assert_eq(_feature(document).rings[0].size(), 4)

	var size := _feature(document).rings[0].size()
	assert_eq(document.insert_vertex(_feature(document), 0, size, Vector2(-5, 5)), "",
		"an index past the last vertex appends")
	assert_eq(_feature(document).rings[0][size], Vector2(-5, 5))


func test_removing_vertices_ends_with_the_part_gone() -> void:
	var document := _document()
	assert_eq(document.remove_vertex(_feature(document), 0, 0), "")
	assert_eq(_feature(document).rings.size(), 0,
		"a polygon of two vertices is not a shape, so the part went with the vertex")
	assert_eq(_feature(document).triangles.size(), 0)


func test_a_multipoint_keeps_its_last_vertex_until_it_is_removed() -> void:
	var document := _document(Feature.GeometryKind.MULTIPOINT)
	assert_eq(document.remove_vertex(_feature(document), 0, 0), "")
	assert_eq(_feature(document).rings[0].size(), 2, "one marker is still a multipoint")
	document.remove_vertex(_feature(document), 0, 0)
	document.remove_vertex(_feature(document), 0, 0)
	assert_eq(_feature(document).rings.size(), 0, "the part goes with the last marker")
