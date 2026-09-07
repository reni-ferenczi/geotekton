extends TestCase

# Planet.collect_geometry and Planet.hit_test, the CPU counterpart of the
# geometry shader. A polygon is hit inside its triangles, which must be wound
# counter-clockwise as seen from outside the sphere, the rule
# Feature.ensure_front_winding enforces. A polyline and a multipoint are hit
# within a tolerance of the line and of the marker.

# Counter-clockwise from outside; see test_winding_matches_the_front_face_rule.
static var TRIANGLE := PackedVector2Array([Vector2(-10, -10), Vector2(10, 0), Vector2(-10, 10)])

# A line along the equator and a pair of separate points.
static var LINE := PackedVector2Array([Vector2(0, 0), Vector2(0, 30)])
static var POINTS := PackedVector2Array([Vector2(45, 45), Vector2(-45, -45)])


func test_winding_matches_the_front_face_rule() -> void:
	assert_true(_is_front_facing(TRIANGLE[0], TRIANGLE[1], TRIANGLE[2]),
		"the test triangle must be wound counter-clockwise from outside")
	assert_true(not _is_front_facing(TRIANGLE[0], TRIANGLE[2], TRIANGLE[1]),
		"swapping two vertices must flip the facing")


func test_hit_inside_and_miss_outside() -> void:
	var feature := _make_feature("Craton", Color.RED, Vector3.ZERO)
	var geometry := Planet.collect_geometry(_make_root([feature]))
	assert_eq(geometry.primitives.size(), 1, "one triangle is collected")
	assert_eq(geometry.primitives[0]["kind"], Planet.Primitive.TRIANGLE)
	assert_eq(geometry.primitives[0]["color"], Color.RED)
	assert_eq(Planet.hit_test(0, 0, geometry), feature, "the centre is inside")
	assert_eq(Planet.hit_test(40, 40, geometry), null, "a far away point misses")


func test_a_polyline_is_collected_as_segments_and_hit_within_the_tolerance() -> void:
	var feature := _make_feature("Ridge", Color.BLUE, Vector3.ZERO, LINE, Feature.GeometryKind.POLYLINE)
	var geometry := Planet.collect_geometry(_make_root([feature]))
	assert_eq(geometry.primitives.size(), 1, "two vertices make one segment")
	assert_eq(geometry.primitives[0]["kind"], Planet.Primitive.SEGMENT)

	assert_eq(Planet.hit_test(0, 15, geometry), feature, "the middle of the line is a hit")
	assert_eq(Planet.hit_test(0, 0, geometry), feature, "an end of the line is a hit")

	# The tolerance is a chord length on the unit sphere; one degree is 0.0175.
	var inside := rad_to_deg(Planet.LINE_HIT_WIDTH) * 0.5
	assert_eq(Planet.hit_test(inside, 15, geometry), feature,
		"%s degrees off the line is still a hit" % inside)
	var outside := rad_to_deg(Planet.LINE_HIT_WIDTH) * 2.0
	assert_eq(Planet.hit_test(outside, 15, geometry), null,
		"%s degrees off the line misses" % outside)
	assert_eq(Planet.hit_test(0, 50, geometry), null, "past the end of the line misses")


func test_a_multipoint_is_hit_on_its_vertices() -> void:
	var feature := _make_feature("Stations", Color.GREEN, Vector3.ZERO, POINTS, Feature.GeometryKind.MULTIPOINT)
	var geometry := Planet.collect_geometry(_make_root([feature]))
	assert_eq(geometry.primitives.size(), 2, "one marker per vertex")
	assert_eq(geometry.primitives[0]["kind"], Planet.Primitive.POINT)

	for point in POINTS:
		assert_eq(Planet.hit_test(point.x, point.y, geometry), feature,
			"the marker at %s is a hit" % point)
	assert_eq(Planet.hit_test(0, 0, geometry), null, "between the markers is a miss")


func test_disabled_features_are_not_collected() -> void:
	var feature := _make_feature("Craton", Color.RED, Vector3.ZERO)
	feature.enabled = false
	assert_eq(Planet.collect_geometry(_make_root([feature])).primitives.size(), 0)


func test_rotated_feature_is_hit_at_the_rotated_location() -> void:
	var rotation := Vector3(90, 0, 0)
	var feature := _make_feature("Craton", Color.RED, rotation)
	var geometry := Planet.collect_geometry(_make_root([feature]))

	var moved := Feature.apply_rotation(PackedVector2Array([Vector2(0, 0)]), rotation)[0]
	assert_close(moved, Vector2(0, -90), 1e-4,
		"a positive rotation around Y decreases the longitude")
	assert_eq(Planet.hit_test(moved.x, moved.y, geometry), feature,
		"the craton is hit at its rotated position")
	assert_eq(Planet.hit_test(0, 0, geometry), null,
		"the craton is no longer at its unrotated position")


func test_overlapping_features_resolve_to_the_first_child() -> void:
	# collect_geometry walks the tree with a stack, so the last child ends up
	# first in the array, and hit_test scans the array backwards.
	# The first child of the group therefore wins an overlap.
	var first := _make_feature("First", Color.RED, Vector3.ZERO)
	var second := _make_feature("Second", Color.BLUE, Vector3.ZERO)
	var geometry := Planet.collect_geometry(_make_root([first, second]))
	assert_eq(geometry.primitives.size(), 2)
	assert_eq(Planet.hit_test(0, 0, geometry), first)


func _make_feature(title: String, color: Color, rotation: Vector3,
		ring: PackedVector2Array = TRIANGLE,
		kind: Feature.GeometryKind = Feature.GeometryKind.POLYGON) -> Feature:
	var feature := Feature.create_feature(title, color)
	feature.add_ring(ring.duplicate(), kind)
	if not rotation.is_zero_approx():
		Keyframe.upsert(feature.keyframes, 0.0, rotation)
	return feature


func _make_root(features: Array) -> Feature:
	var root := Feature.create_group("Planet")
	root.is_root = true
	var group := Feature.create_group("Cratons")
	root.children.append(group)
	for feature in features:
		group.children.append(feature)
	return root


# The rule from Feature.ensure_front_winding: the triangle normal must point
# away from the centre of the sphere.
func _is_front_facing(a: Vector2, b: Vector2, c: Vector2) -> bool:
	var pa := Feature._latlon_to_xyz_s(a)
	var pb := Feature._latlon_to_xyz_s(b)
	var pc := Feature._latlon_to_xyz_s(c)
	return (pb - pa).cross(pc - pa).dot((pa + pb + pc) / 3.0) >= 0.0
