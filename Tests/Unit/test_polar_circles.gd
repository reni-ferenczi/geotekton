extends TestCase

# Polar circles: a feature whose two rings are rebuilt from an axis, a radius and
# a segment count, one circle around the axis and one around its antipode. See
# Feature.rebuild_polar_circles() and Document.set_polar_circles().

const SCRATCH := "user://test_polar_circles.middle-earth"

# Off the poles and off the prime meridian, so a sign slip in the antipode shows.
const AXIS := Vector2(80.7, -72.7)


func _polar(document: Document) -> Feature:
	var feature := Feature.create_feature("Aurora")
	document.root.children.append(feature)
	document.record()
	assert_eq(document.set_feature_type(feature, FeatureType.POLAR_CIRCLES), "",
		"an empty feature takes the type")
	return feature


func _antipode(point: Vector2) -> Vector2:
	return Vector2(-point.x, wrapf(point.y + 180.0, -180.0, 180.0))


# Two rings, each a closed polyline, the first at the radius from the axis and
# the second at the radius from its antipode.
func _check_rings(feature: Feature, label: String) -> void:
	assert_eq(feature.geometry_kind, Feature.GeometryKind.POLYLINE, "%s: polylines" % label)
	assert_eq(feature.rings.size(), 2, "%s: two rings" % label)
	if feature.rings.size() != 2:
		return
	var centres := [feature.axis, _antipode(feature.axis)]
	for part in 2:
		var ring := feature.rings[part]
		assert_eq(ring.size(), feature.circle_segments + 1,
			"%s: ring %d holds a vertex more than it has segments" % [label, part])
		assert_close(ring[ring.size() - 1], ring[0], 1e-9,
			"%s: ring %d closes on its first vertex" % [label, part])
		for vertex in ring:
			assert_close(Circle.radius_to(centres[part], vertex), feature.radius, 1e-3,
				"%s: a vertex of ring %d sits the radius from its pole" % [label, part])


func test_picking_the_type_builds_both_circles_at_once() -> void:
	var document := Document.new()
	var feature := _polar(document)
	assert_eq(feature.feature_type, FeatureType.POLAR_CIRCLES, "the feature is polar circles")
	assert_eq(feature.axis, Feature.DEFAULT_AXIS, "around the default axis")
	assert_eq(feature.radius, Feature.DEFAULT_RADIUS, "at the default radius")
	assert_eq(feature.circle_segments, Circle.DEFAULT_SEGMENTS, "cut into the default segments")
	assert_eq(feature.color, FeatureType.color(FeatureType.POLAR_CIRCLES), "in the type's color")
	_check_rings(feature, "default")


func test_changing_the_radius_rebuilds_both_circles() -> void:
	var document := Document.new()
	var feature := _polar(document)
	var versions := document.applied
	assert_eq(document.set_polar_circles(feature, AXIS, 10.0, 12), "", "the change goes through")
	assert_eq(document.applied, versions + 1, "as one undo version")
	_check_rings(feature, "moved axis")
	assert_eq(document.set_polar_circles(feature, AXIS, 30.0, 12), "", "a new radius goes through")
	assert_eq(feature.radius, 30.0, "the feature keeps it")
	_check_rings(feature, "wider")

	document.undo()
	var restored: Feature = document.root.children[0]
	assert_eq(restored.radius, 10.0, "undo gives the old radius back")
	_check_rings(restored, "after undo")


func test_values_out_of_range_are_refused() -> void:
	var document := Document.new()
	var feature := _polar(document)
	var versions := document.applied
	for bad: Array in [[Vector2(91.0, 0.0), 20.0, 36], [Vector2(0.0, 181.0), 20.0, 36],
			[AXIS, 0.0, 36], [AXIS, 91.0, 36], [AXIS, 20.0, 2], [AXIS, 20.0, 721]]:
		assert_true(not document.set_polar_circles(feature, bad[0], bad[1], bad[2]).is_empty(),
			"%s is refused" % [bad])
	assert_eq(document.applied, versions, "nothing was recorded")
	_check_rings(feature, "untouched")

	var line := Feature.create_feature("Line")
	document.root.children.append(line)
	line.add_ring(PackedVector2Array([Vector2(0, 0), Vector2(0, 10)]),
		Feature.GeometryKind.POLYLINE)
	assert_true(not document.set_polar_circles(line, AXIS, 20.0, 36).is_empty(),
		"a feature of another type has no axis to set")
	assert_true(not document.set_feature_type(line, FeatureType.POLAR_CIRCLES).is_empty(),
		"and one holding a shape cannot become polar circles")
	assert_eq(line.feature_type, FeatureType.LINE, "so it stays a line")


func test_a_shape_cannot_be_pasted_into_polar_circles() -> void:
	var document := Document.new()
	var feature := _polar(document)
	var shape := {"kind": Feature.GeometryKind.POLYLINE,
		"rings": [PackedVector2Array([Vector2(0, 0), Vector2(0, 10)])]}
	assert_true(not document.paste_shape(feature, shape).is_empty(), "the paste is refused")
	assert_eq(feature.rings.size(), 2, "and the two circles are all there is")


func test_the_file_round_trips_the_parameters_and_the_rings() -> void:
	var document := Document.new()
	var feature := _polar(document)
	document.set_polar_circles(feature, AXIS, 17.5, 20)
	assert_eq(document.save_to_file(SCRATCH), "", "the document is written")

	var file := FileAccess.open(SCRATCH, FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var leaf: Dictionary = raw["features"]["children"][0]
	assert_close(Vector2(leaf["axis"][0], leaf["axis"][1]), AXIS, 1e-4, "the axis is written")
	assert_close(float(leaf["radius"]), 17.5, 1e-6, "so is the radius")
	assert_eq(int(leaf["circle_segments"]), 20, "and the segment count")
	assert_eq((leaf["rings"] as Array).size(), 2, "the two rings are written for other readers")

	var reloaded := Document.new()
	assert_eq(reloaded.load_from_file(SCRATCH), "", "the file loads back")
	var back: Feature = reloaded.root.children[0]
	assert_eq(back.feature_type, FeatureType.POLAR_CIRCLES, "as polar circles")
	assert_close(back.axis, AXIS, 1e-4, "around the same axis")
	assert_close(back.radius, 17.5, 1e-6, "at the same radius")
	assert_eq(back.circle_segments, 20, "with the same segment count")
	for part in 2:
		for index in back.rings[part].size():
			assert_close(back.rings[part][index], feature.rings[part][index], 1e-4,
				"vertex %d of ring %d comes back" % [index, part])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# The parameters win over the rings a file holds, and a leaf of another type
# writes none of the three keys.
func test_the_parameters_win_on_load() -> void:
	var data := {"type": "Feature", "title": "Edited elsewhere", "feature_type": "polar_circles",
		"geometry_kind": "polyline", "rings": [[[0.0, 0.0], [0.0, 10.0]]],
		"axis": [AXIS.x, AXIS.y], "radius": 12.0, "circle_segments": 8}
	var feature := Feature.from_json(data)
	_check_rings(feature, "loaded")
	assert_eq(feature.radius, 12.0, "at the radius the file gives")

	var line := Feature.create_feature("Line")
	line.add_ring(PackedVector2Array([Vector2(0, 0), Vector2(0, 10)]),
		Feature.GeometryKind.POLYLINE)
	var written: Dictionary = line.to_json()
	for key in ["axis", "radius", "circle_segments"]:
		assert_true(not written.has(key), "a line writes no %s" % key)

	var clone := feature.clone()
	assert_eq([clone.axis, clone.radius, clone.circle_segments],
		[feature.axis, feature.radius, feature.circle_segments], "a clone keeps the parameters")


# A keyframe turns the feature as a whole, so both circles move with it.
func test_a_keyframe_moves_both_circles() -> void:
	var document := Document.new()
	var feature := _polar(document)
	document.set_polar_circles(feature, Vector2(0.0, 0.0), 20.0, 12)
	assert_eq(document.set_keyframe(feature, 0.0, Vector3(90.0, 0.0, 0.0)), "", "a keyframe")
	var shape := document.shape_of(feature)
	var world: Array = shape["rings"]
	var axis_world := Feature.apply_rotation(PackedVector2Array([feature.axis]),
		Vector3(90.0, 0.0, 0.0))[0]
	assert_true(Circle.radius_to(axis_world, feature.axis) > 45.0, "the keyframe moves the axis")
	for vertex in world[0]:
		assert_close(Circle.radius_to(axis_world, vertex), 20.0, 1e-3,
			"the first circle follows the axis")
	for vertex in world[1]:
		assert_close(Circle.radius_to(_antipode(axis_world), vertex), 20.0, 1e-3,
			"the second follows its antipode")
