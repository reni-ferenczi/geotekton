extends TestCase

# Feature.compute_move_rotation: the angles that carry the grabbed anchor point
# onto the point under the cursor.


func test_maps_anchor_onto_target_without_a_base_rotation() -> void:
	var anchor := Feature._latlon_to_xyz_s(Vector2(10, 20))
	var target := Feature._latlon_to_xyz_s(Vector2(-35, 130))
	var result: Variant = Feature.compute_move_rotation(anchor, target, Vector3.ZERO)
	assert_true(result is Vector3, "a rotation must be found for non-antipodal points")
	if result is Vector3:
		var moved := Feature.build_rotation_basis(result) * anchor
		assert_close(moved, target, 1e-4, "the anchor must land on the target")


func test_composes_with_a_base_rotation() -> void:
	# The anchor is given in world space, so the feature's own rotation is already
	# applied to it. The returned angles replace the base rotation entirely.
	var base := Vector3(40, -15, 25)
	var base_basis := Feature.build_rotation_basis(base)
	var anchor_local := Feature._latlon_to_xyz_s(Vector2(5, -60))
	var anchor := base_basis * anchor_local
	var target := Feature._latlon_to_xyz_s(Vector2(60, 10))

	var result: Variant = Feature.compute_move_rotation(anchor, target, base)
	assert_true(result is Vector3, "a rotation must be found for non-antipodal points")
	if result is Vector3:
		var moved := Feature.build_rotation_basis(result) * anchor_local
		assert_close(moved, target, 1e-4, "the same anchor vertex must land on the target")


func test_identical_points_keep_the_base_rotation() -> void:
	var base := Vector3(12, 34, 56)
	var anchor := Feature._latlon_to_xyz_s(Vector2(-25, 75))
	var result: Variant = Feature.compute_move_rotation(anchor, anchor, base)
	assert_true(result is Vector3, "identical points must return a rotation")
	if result is Vector3:
		assert_close(result, base, 1e-6, "the base rotation is returned unchanged")


func test_antipodal_points_return_null() -> void:
	var anchor := Feature._latlon_to_xyz_s(Vector2(30, 45))
	var target := Feature._latlon_to_xyz_s(Vector2(-30, -135))
	assert_close(anchor.dot(target), -1.0, 1e-6, "the test points must be antipodal")
	assert_eq(Feature.compute_move_rotation(anchor, target, Vector3.ZERO), null,
		"an antipodal move has no unique rotation")
