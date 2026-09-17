extends TestCase

# The rotations a drag on the planet computes: compute_move_rotation, the angles
# that carry the grabbed anchor point onto the point under the cursor, and
# compute_spin_rotation, the angles that turn a feature about an axis without
# carrying its middle anywhere. See Docs/Moving.md.


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


### Turning about an axis


# A polygon well clear of the poles and of the axes, so that nothing it is
# checked against is degenerate by accident.
const SPUN_RING := [
	Vector2(10, 20), Vector2(14, 34), Vector2(2, 40), Vector2(-6, 30), Vector2(-2, 18)]


func _polygon(title: String = "Plate") -> Feature:
	var feature := Feature.create_feature(title)
	feature.add_ring(PackedVector2Array(SPUN_RING), Feature.GeometryKind.POLYGON)
	return feature


func _tree(node: Feature) -> Feature:
	var root := Feature.create_group("Planet")
	root.is_root = true
	root.children.append(node)
	return root


# The great circle distance between two world points, in degrees.
func _apart(a: Vector2, b: Vector2) -> float:
	return rad_to_deg(acos(clampf(
		Feature._latlon_to_xyz_s(a).dot(Feature._latlon_to_xyz_s(b)), -1.0, 1.0)))


func test_a_quarter_turn_leaves_the_middle_where_it_was() -> void:
	var feature := _polygon()
	var root := _tree(feature)
	var axis := Feature.centroid_axis(root, feature, 0.0)
	var middle := Feature._xyz_to_latlon_s(axis)

	var turned := Feature.compute_spin_rotation(axis, PI / 2.0, Vector3.ZERO)
	var after := Feature.apply_rotation(feature.rings[0], turned)
	feature.rings[0] = after
	assert_close(Feature._xyz_to_latlon_s(Feature.centroid_axis(root, feature, 0.0)), middle,
		1e-3, "the middle of the feature stays where it was")

	# A vertex an angle t from the axis, turned a quarter of the way about it,
	# ends up acos(cos t * cos t) away from where it was.
	for index in SPUN_RING.size():
		var from_axis := deg_to_rad(_apart(middle, SPUN_RING[index]))
		var wanted := rad_to_deg(acos(cos(from_axis) * cos(from_axis)))
		assert_close(_apart(SPUN_RING[index], after[index]), wanted, 1e-3,
			"vertex %d moves the arc a quarter turn about the axis gives it" % index)


func test_a_turn_composes_onto_the_rotation_the_feature_has() -> void:
	var base := Vector3(35, -20, 15)
	var feature := _polygon()
	Keyframe.upsert(feature.keyframes, 0.0, base)
	var root := _tree(feature)
	var axis := Feature.centroid_axis(root, feature, 0.0)

	var turned := Feature.compute_spin_rotation(axis, deg_to_rad(40.0), base)
	var before := Feature.apply_rotation(feature.rings[0], base)
	var after := Feature.apply_rotation(feature.rings[0], turned)
	for index in SPUN_RING.size():
		var angle: float = Feature.angle_about_axis(axis,
			Feature._latlon_to_xyz_s(before[index]), Feature._latlon_to_xyz_s(after[index]))
		assert_close(rad_to_deg(angle), 40.0, 1e-3,
			"vertex %d turns 40 degrees about the axis, from where it already was" % index)


func test_a_pole_turn_moves_every_vertex_by_the_same_angle() -> void:
	# A pole far from the feature, so the turn is nothing like a spin in place.
	var pole := Feature._latlon_to_xyz_s(Vector2(-40, -80))
	var feature := _polygon()
	var turned := Feature.compute_spin_rotation(pole, deg_to_rad(-25.0), Vector3.ZERO)
	var after := Feature.apply_rotation(feature.rings[0], turned)
	for index in SPUN_RING.size():
		var angle: float = Feature.angle_about_axis(pole,
			Feature._latlon_to_xyz_s(SPUN_RING[index]), Feature._latlon_to_xyz_s(after[index]))
		assert_close(rad_to_deg(angle), -25.0, 1e-3,
			"vertex %d turns 25 degrees about the pole" % index)
		assert_close(_apart(Feature._xyz_to_latlon_s(pole), after[index]),
			_apart(Feature._xyz_to_latlon_s(pole), SPUN_RING[index]), 1e-3,
			"and vertex %d stays as far from the pole as it was" % index)


func test_a_childs_keyframe_comes_out_relative_to_its_parent() -> void:
	var parent := _polygon("Continent")
	Keyframe.upsert(parent.keyframes, 0.0, Vector3(25, 10, -5))
	parent.uuid = "parent"
	var child := _polygon("Terrane")
	child.uuid = "child"
	child.couplings.append(Coupling.create(1000.0, 0.0, parent.uuid))
	var root := Feature.create_group("Planet")
	root.is_root = true
	root.children.append(parent)
	root.children.append(child)

	var nodes := Coupling.index(root)
	var axis := Feature.centroid_axis(root, child, 0.0)
	var base := Feature.decompose_rotation_degrees(Feature.world_basis(root, child, 0.0))
	var turned := Feature.compute_spin_rotation(axis, deg_to_rad(30.0), base)
	var keyframe := Coupling.rotation_for(child, 0.0,
		Feature.build_rotation_basis(turned), nodes)
	Keyframe.upsert(child.keyframes, 0.0, keyframe)

	assert_true(not Feature.build_rotation_basis(keyframe).is_equal_approx(
		Feature.build_rotation_basis(turned)),
		"the keyframe is not the world rotation, since the parent is turned too")
	var world_after := Feature.world_basis(root, child, 0.0)
	assert_close(world_after * Vector3.RIGHT,
		Feature.build_rotation_basis(turned) * Vector3.RIGHT, 1e-4,
		"and it puts the child where the turn asked for, in world space")


func test_a_point_on_the_axis_has_no_angle_about_it() -> void:
	var axis := Feature._latlon_to_xyz_s(Vector2(20, 50))
	var off := Feature._latlon_to_xyz_s(Vector2(-10, 5))
	assert_eq(Feature.angle_about_axis(axis, axis, off), null,
		"a point on the axis has no direction about it")
	assert_eq(Feature.angle_about_axis(axis, off, -axis), null,
		"and neither has its antipode")
	assert_true(Feature.angle_about_axis(axis, off, off) is float,
		"two points off the axis do")


func test_a_feature_holding_nothing_has_no_axis_to_turn_about() -> void:
	var feature := Feature.create_feature("Empty")
	assert_eq(Feature.centroid_axis(_tree(feature), feature, 0.0), Vector3.ZERO,
		"with no vertices there is no middle to turn about")
