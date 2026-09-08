extends TestCase

# Rotation conventions of Logic/feature.gd.
# Angles are YXZ Euler degrees: R = Ry(rot.x) * Rx(rot.y) * Rz(rot.z).


func test_decompose_inverts_build() -> void:
	for angles in [
		Vector3(30, 20, 10),
		Vector3(-120, 45, 0),
		Vector3(170, -60, -15),
		Vector3(0, 0, 0),
	]:
		var basis := Feature.build_rotation_basis(angles)
		var decomposed := Feature.decompose_rotation_degrees(basis)
		assert_close(decomposed, angles, 1e-4, "decomposition of %s" % angles)


func test_unapply_undoes_apply() -> void:
	var points: Array[Vector2] = [
		Vector2(0, 0), Vector2(45, 120), Vector2(-33.5, -170.25), Vector2(89, 15),
	]
	var angles := Vector3(35, -25, 80)
	var restored := Feature.unapply_rotation(Feature.apply_rotation(points, angles), angles)
	assert_eq(restored.size(), points.size())
	for i in range(mini(restored.size(), points.size())):
		assert_close(restored[i], points[i], 1e-3, "point %d after the round trip" % i)


func test_positive_y_rotation_decreases_longitude() -> void:
	# Ry(90) sends the unit vector of longitude L to the unit vector of L - 90:
	# x' = x cos90 + z sin90, z' = -x sin90 + z cos90, so lon' = lon - 90.
	var rotated := Feature.apply_rotation([Vector2(0, 0), Vector2(0, 45)] as Array[Vector2],
		Vector3(90, 0, 0))
	assert_close(rotated[0], Vector2(0, -90), 1e-4, "the equator point at longitude 0")
	assert_close(rotated[1], Vector2(0, -45), 1e-4, "the equator point at longitude 45")


func test_gimbal_lock_rebuilds_the_same_basis() -> void:
	# At beta = 90 the alpha and gamma rotations act on the same axis, so the
	# decomposition picks gamma = 0 and returns different angles for the same Basis.
	var angles := Vector3(30, 90, 15)
	var basis := Feature.build_rotation_basis(angles)
	var decomposed := Feature.decompose_rotation_degrees(basis)
	assert_close(decomposed.z, 0.0, 1e-6, "gamma is forced to zero under gimbal lock")
	assert_true(Feature.build_rotation_basis(decomposed).is_equal_approx(basis),
		"the rebuilt Basis must match: %s vs %s" % [Feature.build_rotation_basis(decomposed), basis])
