extends TestCase

# A Circle feature: its rings are rebuilt from a center, a radius and a segment
# count, with a second circle around the antipode when it is polar. See
# Feature.rebuild_circle(), Document.set_circle() and Circle.fit().

const SCRATCH := "user://test_circle_feature.middle-earth"

# Off the poles and off the prime meridian, so a sign slip in the antipode shows.
const AXIS := Vector2(80.7, -72.7)


func _circle(document: Document) -> Feature:
	var feature := Feature.create_feature("Aurora")
	document.root.children.append(feature)
	document.record()
	assert_eq(document.set_feature_type(feature, FeatureType.CIRCLE), "",
		"an empty feature takes the type")
	return feature


func _antipode(point: Vector2) -> Vector2:
	return Vector2(-point.x, wrapf(point.y + 180.0, -180.0, 180.0))


# One ring, or two when the circle is polar, each a closed polyline the radius
# from its pole.
func _check_rings(feature: Feature, label: String) -> void:
	var count := 2 if feature.polar else 1
	assert_eq(feature.geometry_kind, Feature.GeometryKind.POLYLINE, "%s: polylines" % label)
	assert_eq(feature.rings.size(), count, "%s: %d rings" % [label, count])
	if feature.rings.size() != count:
		return
	var centers := [feature.axis, _antipode(feature.axis)]
	for part in count:
		var ring := feature.rings[part]
		assert_eq(ring.size(), feature.circle_segments + 1,
			"%s: ring %d holds a vertex more than it has segments" % [label, part])
		assert_close(ring[ring.size() - 1], ring[0], 1e-9,
			"%s: ring %d closes on its first vertex" % [label, part])
		for vertex in ring:
			assert_close(Circle.radius_to(centers[part], vertex), feature.radius, 1e-3,
				"%s: a vertex of ring %d sits the radius from its pole" % [label, part])


func test_picking_the_type_draws_nothing_yet() -> void:
	var document := Document.new()
	var feature := _circle(document)
	assert_true(not feature.has_geometry(), "the circle comes when it is drawn")
	assert_true(not feature.polar, "a circle is not polar to begin with")
	assert_true(not (feature.to_json() as Dictionary).has("axis"),
		"and an undrawn circle writes no parameters")
	assert_eq(feature.color, FeatureType.color(FeatureType.CIRCLE), "in the type's color")


func test_setting_the_parameters_rebuilds_the_circle() -> void:
	var document := Document.new()
	var feature := _circle(document)
	var versions := document.applied
	assert_eq(document.set_circle(feature, AXIS, 10.0, 12, false), "", "the change goes through")
	assert_eq(document.applied, versions + 1, "as one undo version")
	_check_rings(feature, "drawn")
	assert_eq(document.set_circle(feature, AXIS, 120.0, 12, false), "",
		"a plain circle may be wider than a hemisphere")
	_check_rings(feature, "wide")
	assert_eq(document.set_circle(feature, AXIS, 30.0, 12, false), "", "a new radius goes through")
	assert_eq(feature.radius, 30.0, "the feature keeps it")
	_check_rings(feature, "wider")

	document.undo()
	var restored: Feature = document.root.children[0]
	assert_eq(restored.radius, 120.0, "undo gives the old radius back")
	_check_rings(restored, "after undo")


func test_polar_adds_the_antipode_ring_and_takes_it_away() -> void:
	var document := Document.new()
	var feature := _circle(document)
	document.set_circle(feature, AXIS, 20.0, 16, false)
	var versions := document.applied
	assert_eq(document.set_circle(feature, AXIS, 20.0, 16, true), "", "the switch goes on")
	assert_eq(document.applied, versions + 1, "as one undo version")
	assert_true(feature.polar, "the feature is polar")
	_check_rings(feature, "polar")
	assert_eq(document.set_circle(feature, AXIS, 20.0, 16, false), "", "and off again")
	_check_rings(feature, "plain again")

	assert_true(not document.set_circle(feature, AXIS, 100.0, 16, true).is_empty(),
		"axis circles past 90 degrees would reach round each other")
	assert_true(not feature.polar, "so the refused switch is not applied")


func test_values_out_of_range_are_refused() -> void:
	var document := Document.new()
	var feature := _circle(document)
	document.set_circle(feature, AXIS, 20.0, 36, false)
	var versions := document.applied
	for bad: Array in [[Vector2(91.0, 0.0), 20.0, 36], [Vector2(0.0, 181.0), 20.0, 36],
			[AXIS, 0.0, 36], [AXIS, 180.0, 36], [AXIS, 20.0, 2], [AXIS, 20.0, 721]]:
		assert_true(not document.set_circle(feature, bad[0], bad[1], bad[2], false).is_empty(),
			"%s is refused" % [bad])
	assert_eq(document.applied, versions, "nothing was recorded")
	_check_rings(feature, "untouched")

	var line := Feature.create_feature("Line")
	document.root.children.append(line)
	line.add_ring(PackedVector2Array([Vector2(0, 0), Vector2(0, 10)]),
		Feature.GeometryKind.POLYLINE)
	assert_true(not document.set_circle(line, AXIS, 20.0, 36, false).is_empty(),
		"a feature of another type has no center to set")
	assert_true(not document.set_feature_type(line, FeatureType.CIRCLE).is_empty(),
		"and one holding a shape cannot become a circle")
	assert_eq(line.feature_type, FeatureType.LINE, "so it stays a line")


func test_a_circle_may_become_a_line_and_keeps_its_ring() -> void:
	var document := Document.new()
	var feature := _circle(document)
	document.set_circle(feature, AXIS, 20.0, 12, true)
	var rings := feature.rings.duplicate(true)
	assert_eq(document.set_feature_type(feature, FeatureType.LINE), "", "the type goes")
	assert_eq(feature.rings, rings, "and the rings stay as they were")


func test_a_shape_cannot_be_pasted_into_a_circle() -> void:
	var document := Document.new()
	var feature := _circle(document)
	document.set_circle(feature, AXIS, 20.0, 12, false)
	var shape := {"kind": Feature.GeometryKind.POLYLINE,
		"rings": [PackedVector2Array([Vector2(0, 0), Vector2(0, 10)])]}
	assert_true(not document.paste_shape(feature, shape).is_empty(), "the paste is refused")
	assert_eq(feature.rings.size(), 1, "and the circle is all there is")


func test_the_file_round_trips_the_parameters_and_the_rings() -> void:
	var document := Document.new()
	var feature := _circle(document)
	document.set_circle(feature, AXIS, 17.5, 20, true)
	assert_eq(document.save_to_file(SCRATCH), "", "the document is written")

	var file := FileAccess.open(SCRATCH, FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var leaf: Dictionary = raw["features"]["children"][0]
	assert_close(Vector2(leaf["axis"][0], leaf["axis"][1]), AXIS, 1e-4, "the axis is written")
	assert_close(float(leaf["radius"]), 17.5, 1e-6, "so is the radius")
	assert_eq(int(leaf["circle_segments"]), 20, "and the segment count")
	assert_eq(leaf.get("polar"), true, "and the switch")
	assert_eq((leaf["rings"] as Array).size(), 2, "the two rings are written for other readers")

	var reloaded := Document.new()
	assert_eq(reloaded.load_from_file(SCRATCH), "", "the file loads back")
	var back: Feature = reloaded.root.children[0]
	assert_eq(back.feature_type, FeatureType.CIRCLE, "as a circle")
	assert_true(back.polar, "drawn at both ends of the axis")
	assert_close(back.axis, AXIS, 1e-4, "around the same axis")
	assert_close(back.radius, 17.5, 1e-6, "at the same radius")
	assert_eq(back.circle_segments, 20, "with the same segment count")
	for part in 2:
		for index in back.rings[part].size():
			assert_close(back.rings[part][index], feature.rings[part][index], 1e-4,
				"vertex %d of ring %d comes back" % [index, part])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# The parameters win over the rings a file holds, a plain circle writes no
# switch, and a leaf of another type writes none of the keys.
func test_the_parameters_win_on_load() -> void:
	var data := {"type": "Feature", "title": "Edited elsewhere", "feature_type": "circle",
		"geometry_kind": "polyline", "rings": [[[0.0, 0.0], [0.0, 10.0]]],
		"axis": [AXIS.x, AXIS.y], "radius": 12.0, "circle_segments": 8}
	var feature := Feature.from_json(data)
	_check_rings(feature, "loaded")
	assert_eq(feature.radius, 12.0, "at the radius the file gives")
	assert_true(not (feature.to_json() as Dictionary).has("polar"), "a plain circle writes no switch")

	var line := Feature.create_feature("Line")
	line.add_ring(PackedVector2Array([Vector2(0, 0), Vector2(0, 10)]),
		Feature.GeometryKind.POLYLINE)
	var written: Dictionary = line.to_json()
	for key in ["axis", "radius", "circle_segments", "polar"]:
		assert_true(not written.has(key), "a line writes no %s" % key)

	feature.polar = true
	var clone := feature.clone()
	assert_eq([clone.axis, clone.radius, clone.circle_segments, clone.polar],
		[feature.axis, feature.radius, feature.circle_segments, true],
		"a clone keeps the parameters")


# A ring cut from a circle and nothing else, as a file written before 0.21.0 or
# a script holds it, gives back the circle it was cut from.
func test_a_ring_without_parameters_gives_back_its_circle() -> void:
	for closed in [false, true]:
		var ring := Circle.vertices(AXIS, 33.3, 24, closed)
		var circle := Circle.fit(ring)
		assert_close(circle[0], AXIS, 1e-3, "the center comes back (closed %s)" % closed)
		assert_close(circle[1], 33.3, 1e-3, "and the radius")
		assert_eq(circle[2], 24, "and the segment count")

	var data := {"type": "Feature", "title": "Drawn", "feature_type": "circle",
		"geometry_kind": "polyline",
		"rings": Feature.rings_to_json([Circle.vertices(AXIS, 33.3, 24, false)])}
	var feature := Feature.from_json(data)
	assert_close(feature.axis, AXIS, 1e-3, "a leaf without the keys is given the center")
	assert_true(not data.has("axis"), "without the data handed in being changed")
	_check_rings(feature, "fitted")

	assert_true(Circle.fit(PackedVector2Array([Vector2(0, 0), Vector2(0, 10)])).is_empty(),
		"two vertices are no circle")


# A keyframe turns the feature as a whole, so both circles move with it.
func test_a_keyframe_moves_both_circles() -> void:
	var document := Document.new()
	var feature := _circle(document)
	document.set_circle(feature, Vector2(0.0, 0.0), 20.0, 12, true)
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
