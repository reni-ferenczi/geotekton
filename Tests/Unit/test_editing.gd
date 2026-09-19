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


### Splitting


# A document holding one five vertex polygon with a colour, a time range and a
# pair of keyframes, so a split has something to carry over.
func _splittable(kind: Feature.GeometryKind = Feature.GeometryKind.POLYGON) -> Document:
	var document := Document.new()
	var feature := Feature.create_feature("Gondwana", Color.CORNFLOWER_BLUE)
	feature.add_ring(PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(14, 10),
		Vector2(5, 16), Vector2(0, 12)]), kind)
	feature.feature_type = FeatureType.CIRCLE
	feature.icon = "shield"
	feature.time_range = Vector2i(20, 800)
	Keyframe.upsert(feature.keyframes, 0.0, Vector3(5, 0, 0))
	Keyframe.upsert(feature.keyframes, 300.0, Vector3(40, 10, 0))
	document.root.children.append(feature)
	document.record()
	return document


func test_a_polygon_becomes_two_features_side_by_side() -> void:
	var document := _splittable()
	var versions := document.applied
	assert_eq(document.split_feature(_feature(document), 0, 0, 2), "")
	assert_eq(document.root.children.size(), 2, "the tree holds two features now")
	assert_eq(document.root.children[0].title, "Gondwana", "the first keeps its title")
	assert_eq(document.root.children[1].title, "Gondwana 2", "and the second is named after it")
	assert_eq(document.applied, versions + 1, "the split recorded exactly one version")

	document.undo()
	assert_eq(document.root.children.size(), 1, "undo puts the one feature back")
	assert_eq(_feature(document).rings[0].size(), 5, "with all five vertices")


func test_both_halves_carry_what_the_feature_was() -> void:
	var document := _splittable()
	var whole := _feature(document)
	var type := whole.feature_type
	var color := whole.color
	var time_range := whole.time_range
	var keyframes := Keyframe.clone_list(whole.keyframes)

	assert_eq(document.split_feature(whole, 0, 1, 3), "")
	for half in document.root.children:
		assert_eq(half.geometry_kind, Feature.GeometryKind.POLYGON, "%s is a polygon" % half.title)
		assert_eq(half.feature_type, type, "%s keeps the type" % half.title)
		assert_eq(half.color, color, "%s keeps the colour" % half.title)
		assert_eq(half.icon, "shield", "%s keeps the icon" % half.title)
		assert_eq(half.time_range, time_range, "%s keeps the time range" % half.title)
		assert_eq(half.keyframes.size(), keyframes.size(), "%s keeps the keyframes" % half.title)
		for i in range(keyframes.size()):
			assert_close(half.keyframes[i].time, keyframes[i].time, 1e-9)
			assert_close(half.keyframes[i].rotation, keyframes[i].rotation, 1e-6)
		assert_true(half.pnid > 0, "%s has an id of its own" % half.title)
	assert_true(document.root.children[0].pnid != document.root.children[1].pnid,
		"the two halves are two features, not one twice")


func test_the_halves_of_a_polygon_are_triangulated_and_add_up() -> void:
	var document := _splittable()
	var whole_area := _area(_feature(document).triangles)
	assert_eq(document.split_feature(_feature(document), 0, 0, 2), "")
	var sum := 0.0
	for half in document.root.children:
		assert_true(half.triangles.size() > 0, "%s has triangles of its own" % half.title)
		assert_eq(half.triangles.size(), (half.rings[0].size() - 2) * 3,
			"%s is triangulated from its own ring" % half.title)
		sum += _area(half.triangles)
	assert_close(sum, whole_area, whole_area * 1e-4, "the two halves cover the original")


func test_a_polygon_splits_along_a_drawn_cut_in_one_version() -> void:
	var document := _splittable()
	var versions := document.applied
	var color := _feature(document).color
	assert_eq(document.split_feature_along(_feature(document), 0,
		PackedVector2Array([Vector2(5, -1), Vector2(6, 8), Vector2(5, 20)])), "")
	assert_eq(document.root.children.size(), 2, "the tree holds two features now")
	assert_eq(document.root.children[1].title, "Gondwana 2")
	assert_eq(document.root.children[1].color, color, "the second half keeps the colour")
	assert_eq(document.applied, versions + 1, "the split recorded exactly one version")
	document.undo()
	assert_eq(document.root.children.size(), 1, "undo puts the one feature back")
	assert_eq(_feature(document).rings[0].size(), 5, "with the five vertices it had")
	assert_true(not document.split_feature_along(_feature(document), 0,
		PackedVector2Array([Vector2(3, -1), Vector2(7, -1)])).is_empty(),
		"a cut with both ends on one edge is refused")
	assert_eq(document.applied, versions, "and records nothing")


func test_a_polyline_splits_at_one_vertex() -> void:
	var document := _splittable(Feature.GeometryKind.POLYLINE)
	assert_eq(document.split_feature(_feature(document), 0, 2), "")
	assert_eq(document.root.children[0].rings[0].size(), 3)
	assert_eq(document.root.children[1].rings[0].size(), 3)
	assert_eq(document.root.children[0].rings[0][2], document.root.children[1].rings[0][0],
		"both halves keep the vertex the cut was made at")


func test_a_split_that_cannot_be_made_changes_nothing() -> void:
	var document := _splittable()
	var versions := document.applied
	for attempt in [[0, 0, 1], [0, 2, 2], [0, 9, 2], [3, 0, 2]]:
		assert_true(not document.split_feature(
			_feature(document), attempt[0], attempt[1], attempt[2]).is_empty(),
			"part %d from %d to %d is refused" % attempt)
	assert_eq(document.root.children.size(), 1, "the tree is untouched")
	assert_eq(_feature(document).rings[0].size(), 5)
	assert_eq(document.applied, versions, "and no version was recorded")


func test_a_multipoint_has_no_path_to_split() -> void:
	var document := _splittable(Feature.GeometryKind.MULTIPOINT)
	assert_true(not document.split_feature(_feature(document), 0, 2).is_empty())
	assert_eq(document.root.children.size(), 1)


func test_a_group_cannot_be_split() -> void:
	var document := _splittable()
	var group := Feature.create_group("Cratons")
	document.root.children.append(group)
	assert_true(not document.split_feature(group, 0, 0, 2).is_empty())


func test_the_other_parts_of_a_feature_stay_with_the_first_half() -> void:
	var document := _splittable()
	var feature := _feature(document)
	feature.add_ring(PackedVector2Array([
		Vector2(-30, -30), Vector2(-20, -30), Vector2(-25, -20)]),
		Feature.GeometryKind.POLYGON)
	document.record()

	assert_eq(document.split_feature(feature, 0, 0, 2), "")
	assert_eq(document.root.children[0].rings.size(), 2,
		"the first half keeps the part that was not split")
	assert_eq(document.root.children[1].rings.size(), 1,
		"and the second holds its half alone")


func _area(triangles: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(0, triangles.size() - 2, 3):
		total += absf((triangles[i + 1] - triangles[i]).cross(
			triangles[i + 2] - triangles[i])) * 0.5
	return total


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


# The glyph the tree row shows. Only a leaf has one, and only one the catalog
# knows; the rest of the program never reads it.
func test_an_icon_is_picked_from_the_catalog_and_is_one_undo_version() -> void:
	var document := _document()
	var versions := document.applied
	assert_eq(document.set_icon(_feature(document), "mountain"), "")
	assert_eq(_feature(document).icon, "mountain")
	assert_eq(document.applied, versions + 1)

	assert_true(not document.set_icon(_feature(document), "sombrero").is_empty(),
		"an icon the catalog does not know is refused")
	assert_eq(_feature(document).icon, "mountain", "and the feature keeps the one it had")
	assert_true(not document.set_icon(document.root, "mountain").is_empty(),
		"a group has no icon")

	assert_eq(document.set_icon(_feature(document), FeatureIcon.NONE), "",
		"and it can be taken off again")
	assert_eq(_feature(document).icon, FeatureIcon.NONE)


func test_a_colour_change_is_one_undo_version() -> void:
	var document := _document()
	var versions := document.applied
	document.set_color(_feature(document), Color.MAGENTA)
	assert_eq(_feature(document).color, Color.MAGENTA)
	assert_eq(document.applied, versions + 1)


### Types


# A circle is built from its center and radius, so a drawn polygon is not one.
func test_a_polygon_cannot_be_made_a_circle() -> void:
	var document := _document()
	var versions := document.applied
	assert_eq(_feature(document).feature_type, "polygon", "the geometry gives the type")
	assert_true(not document.set_feature_type(_feature(document), FeatureType.CIRCLE).is_empty(),
		"a polygon is refused as a circle")
	assert_eq(_feature(document).feature_type, "polygon", "and stays a polygon")
	assert_eq(document.applied, versions, "with nothing recorded")


func test_a_type_that_forbids_the_kind_is_refused() -> void:
	var document := _document()
	var versions := document.applied
	var error := document.set_feature_type(_feature(document), "line")
	assert_true(not error.is_empty(), "a polygon cannot be a line")
	assert_eq(_feature(document).feature_type, "polygon", "the refused type was not applied")
	assert_eq(document.applied, versions, "and nothing was recorded")


func test_a_feature_holding_nothing_takes_any_type() -> void:
	var document := Document.new()
	# A fresh feature for each type, since a hotspot builds its rings as soon as
	# it is picked.
	for type_id in FeatureType.CATALOG:
		var feature := Feature.create_feature("Empty")
		document.root.children.append(feature)
		assert_eq(feature.feature_type, "polygon", "a new feature is a Polygon")
		assert_eq(document.set_feature_type(feature, type_id), "",
			"nothing is drawn yet, so %s is free to pick" % type_id)
		assert_eq(feature.feature_type, type_id, "and the feature keeps it")


func test_an_unknown_type_is_refused() -> void:
	var document := _document()
	assert_true(not document.set_feature_type(_feature(document), "volcano").is_empty())
	assert_eq(_feature(document).feature_type, "polygon")


func test_the_colour_follows_the_type_until_someone_picks_one() -> void:
	var document := Document.new()
	var feature := Feature.create_feature("Empty")
	document.root.children.append(feature)
	document.set_feature_type(feature, FeatureType.CIRCLE)
	assert_eq(feature.color, FeatureType.color(FeatureType.CIRCLE),
		"the default colour follows the type")

	document.set_color(feature, Color.MAGENTA)
	document.set_feature_type(feature, "polygon")
	assert_eq(feature.color, Color.MAGENTA,
		"a colour someone picked is not overwritten by the next type")


### Time range


func test_a_feature_can_be_created_with_a_time_range() -> void:
	assert_eq(Feature.create_feature("Fresh").time_range, Feature.DEFAULT_TIME_RANGE,
		"a feature created without one covers the whole default span")
	assert_eq(Feature.create_feature("Late", Color.RED, Vector2i(0, 1500)).time_range,
		Vector2i(0, 1500), "one added at 1500 Ma starts there and runs to the present")
	assert_eq(Feature.create_feature("Now", Color.RED, Vector2i(0, 0)).time_range,
		Vector2i(0, 0), "one added at the present is there at the present only")


func test_a_time_range_that_ends_older_than_it_starts_is_refused() -> void:
	var document := _document()
	var before := _feature(document).time_range
	var versions := document.applied
	assert_eq(document.set_time_range(_feature(document), Vector2i(900, 100)),
		"The time range ends at 900, after it starts at 100.",
		"the message names the ends the way the panel reads them: From older, To younger")
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


### The shape clipboard


# A document holding a feature a keyframe has turned and an empty one beside it,
# so a shape can be carried from a frame that has moved into one that has not.
func _shapes() -> Document:
	var document := Document.new()
	var source := Feature.create_feature("Rodinia")
	source.add_ring(PackedVector2Array([
		Vector2(0, 0), Vector2(10, 5), Vector2(0, 10)]), Feature.GeometryKind.POLYGON)
	Keyframe.upsert(source.keyframes, 0.0, Vector3(30, -40, 15))
	document.root.children.append(source)
	document.root.children.append(Feature.create_feature("Tracing"))
	document.record()
	return document


func _world_ring(document: Document, feature: Feature, part: int) -> PackedVector2Array:
	return Feature.apply_basis(feature.rings[part],
		Feature.world_basis(document.root, feature, document.current_time))


func test_a_shape_copied_from_a_rotated_feature_lands_on_the_same_world_points() -> void:
	var document := _shapes()
	var source: Feature = document.root.children[0]
	var target: Feature = document.root.children[1]
	var world := _world_ring(document, source, 0)
	assert_true(world != source.rings[0], "the keyframe really has turned the source")

	var shape := document.shape_of(source)
	assert_eq(shape["kind"], Feature.GeometryKind.POLYGON, "the shape carries the kind")
	var versions := document.applied
	assert_eq(document.paste_shape(target, shape), "")
	assert_eq(document.applied, versions + 1, "the paste recorded exactly one version")

	var pasted := _world_ring(document, target, 0)
	assert_eq(pasted.size(), world.size(), "the pasted part holds the same vertices")
	for index in world.size():
		assert_close(pasted[index].x, world[index].x, 1e-4,
			"vertex %d is at the latitude it was copied from" % index)
		assert_close(pasted[index].y, world[index].y, 1e-4,
			"vertex %d is at the longitude it was copied from" % index)


func test_a_feature_holding_nothing_takes_the_kind_with_the_shape() -> void:
	var document := _shapes()
	var target: Feature = document.root.children[1]
	assert_eq(target.feature_type, FeatureType.POLYGON, "a new feature is a Polygon")

	var line := Feature.create_feature("Ridge")
	line.add_ring(PackedVector2Array([Vector2(0, 0), Vector2(5, 5)]),
		Feature.GeometryKind.POLYLINE)
	document.root.children.append(line)

	assert_eq(document.paste_shape(target, document.shape_of(line)), "")
	assert_eq(target.geometry_kind, Feature.GeometryKind.POLYLINE,
		"the empty feature took the kind the shape carried")
	assert_eq(target.feature_type, "line", "and its type followed the kind")


func test_pasting_again_appends_another_part() -> void:
	var document := _shapes()
	var source: Feature = document.root.children[0]
	var target: Feature = document.root.children[1]
	var shape := document.shape_of(source)
	document.paste_shape(target, shape)
	assert_eq(document.paste_shape(target, shape), "")
	assert_eq(target.rings.size(), 2, "the second paste appended a second part")
	document.undo()
	assert_eq(document.root.children[1].rings.size(), 1, "undo takes it off again")


func test_a_shape_of_another_kind_is_refused() -> void:
	var document := _shapes()
	var source: Feature = document.root.children[0]
	var line := Feature.create_feature("Ridge")
	line.add_ring(PackedVector2Array([Vector2(0, 0), Vector2(5, 5)]),
		Feature.GeometryKind.POLYLINE)
	document.root.children.append(line)
	document.record()

	var versions := document.applied
	var error := document.paste_shape(line, document.shape_of(source))
	assert_eq(error, "A polyline cannot take a polygon.",
		"the parts of a feature are all of one kind")
	assert_eq(line.rings.size(), 1, "the refused shape was not added")
	assert_eq(document.applied, versions, "and nothing was recorded")


func test_a_group_and_an_empty_feature_have_no_shape_to_copy() -> void:
	var document := _shapes()
	assert_eq(document.shape_of(document.root), {}, "a group holds no vertices of its own")
	assert_eq(document.shape_of(document.root.children[1]), {},
		"and neither does a feature holding nothing yet")
	assert_eq(document.paste_shape(document.root, document.shape_of(document.root.children[0])),
		"Only a feature takes a shape.")


func test_a_topology_copies_the_runs_its_sections_resolve_to() -> void:
	var document := _shapes()
	var source: Feature = document.root.children[0]
	var topology := Feature.create_feature("Boundary")
	topology.geometry_kind = Feature.GeometryKind.TOPOLOGY
	topology.sections.append(TopologySection.whole_part(source, 0))
	document.root.children.append(topology)

	var shape := document.shape_of(topology)
	assert_eq(shape["kind"], Feature.GeometryKind.POLYLINE,
		"a topology comes out as the line it resolves to")
	var runs: Array = shape["rings"]
	assert_eq(runs.size(), 1, "one run per section that resolved")
	var world := _world_ring(document, source, 0)
	assert_eq(runs[0], world, "holding the world vertices the section runs along")

	var target: Feature = document.root.children[1]
	assert_eq(document.paste_shape(target, shape), "")
	assert_eq(target.geometry_kind, Feature.GeometryKind.POLYLINE,
		"which is what makes a topology editable")
	assert_eq(document.paste_shape(topology, shape),
		"A topology borrows its vertices, so a shape cannot be added to it.")
