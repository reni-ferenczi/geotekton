extends TestCase

# Planet.collect_triangles and Planet.hit_test_craton, the CPU counterpart of the
# craton shader. The winding must be counter-clockwise as seen from outside the
# sphere, the same rule Application._ensure_front_winding enforces when drawing.

# Counter-clockwise from outside; see test_winding_matches_the_front_face_rule.
const TRIANGLE: Array[Vector2] = [Vector2(-10, -10), Vector2(10, 0), Vector2(-10, 10)]


func test_winding_matches_the_front_face_rule() -> void:
	assert_true(_is_front_facing(TRIANGLE[0], TRIANGLE[1], TRIANGLE[2]),
		"the test triangle must be wound counter-clockwise from outside")
	assert_true(not _is_front_facing(TRIANGLE[0], TRIANGLE[2], TRIANGLE[1]),
		"swapping two vertices must flip the facing")


func test_hit_inside_and_miss_outside() -> void:
	var feature := _make_feature("Craton", Color.RED, Vector3.ZERO)
	var triangles := Planet.collect_triangles(_make_root([feature]))
	assert_eq(triangles.size(), 1, "one triangle is collected")
	assert_eq(triangles[0]["color"], Color.RED)
	assert_eq(Planet.hit_test_craton(0, 0, triangles), feature, "the centre is inside")
	assert_eq(Planet.hit_test_craton(40, 40, triangles), null, "a far away point misses")


func test_disabled_features_are_not_collected() -> void:
	var feature := _make_feature("Craton", Color.RED, Vector3.ZERO)
	feature.enabled = false
	assert_eq(Planet.collect_triangles(_make_root([feature])).size(), 0)


func test_rotated_feature_is_hit_at_the_rotated_location() -> void:
	var rotation := Vector3(90, 0, 0)
	var feature := _make_feature("Craton", Color.RED, rotation)
	var triangles := Planet.collect_triangles(_make_root([feature]))

	var moved := Feature.apply_rotation([Vector2(0, 0)] as Array[Vector2], rotation)[0]
	assert_close(moved, Vector2(0, -90), 1e-4,
		"a positive rotation around Y decreases the longitude")
	assert_eq(Planet.hit_test_craton(moved.x, moved.y, triangles), feature,
		"the craton is hit at its rotated position")
	assert_eq(Planet.hit_test_craton(0, 0, triangles), null,
		"the craton is no longer at its unrotated position")


func test_overlapping_features_resolve_to_the_first_child() -> void:
	# collect_triangles walks the tree with a stack, so the last child ends up
	# first in the array, and hit_test_craton scans the array backwards.
	# The first child of the group therefore wins an overlap.
	var first := _make_feature("First", Color.RED, Vector3.ZERO)
	var second := _make_feature("Second", Color.BLUE, Vector3.ZERO)
	var triangles := Planet.collect_triangles(_make_root([first, second]))
	assert_eq(triangles.size(), 2)
	assert_eq(Planet.hit_test_craton(0, 0, triangles), first)


func _make_feature(title: String, color: Color, rotation: Vector3) -> Feature:
	var feature := Feature.create_feature(title, color)
	feature.vertices = TRIANGLE.duplicate()
	feature.rotation_angles = rotation
	return feature


func _make_root(features: Array) -> Feature:
	var root := Feature.create_group("Planet")
	root.is_root = true
	var group := Feature.create_group("Cratons")
	root.children.append(group)
	for feature in features:
		group.children.append(feature)
	return root


# The rule from Application._ensure_front_winding: the triangle normal must point away
# from the centre of the sphere.
func _is_front_facing(a: Vector2, b: Vector2, c: Vector2) -> bool:
	var pa := Feature._latlon_to_xyz_s(a)
	var pb := Feature._latlon_to_xyz_s(b)
	var pc := Feature._latlon_to_xyz_s(c)
	return (pb - pa).cross(pc - pa).dot((pa + pb + pc) / 3.0) >= 0.0
