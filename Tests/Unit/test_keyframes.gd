extends TestCase

# Keyframe interpolation and the list a node keeps them in, and what a rotation
# resolved from the root down comes to once groups have had their say.

# Two rotations far enough apart that a slerp between them is not the same as
# interpolating the three angles, so the test can tell the two apart.
const FROM := Vector3(0, 0, 0)
const TO := Vector3(90, 40, 0)


### Interpolation


func test_a_keyframe_time_gives_that_keyframe_exactly() -> void:
	var keyframes := _two_keyframes(0.0, 100.0)
	assert_close(Keyframe.interpolate(keyframes, 0.0), FROM, 1e-6, "the younger keyframe")
	assert_close(Keyframe.interpolate(keyframes, 100.0), TO, 1e-6, "the older one")


func test_halfway_between_two_keyframes_is_the_slerp_midpoint() -> void:
	var keyframes := _two_keyframes(0.0, 100.0)
	var got := Keyframe.interpolate(keyframes, 50.0)

	# The same midpoint worked out from the quaternions the two rotations are,
	# rather than from the interpolation being tested.
	var a := Quaternion(Feature.build_rotation_basis(FROM))
	var b := Quaternion(Feature.build_rotation_basis(TO))
	var wanted := Feature.decompose_rotation_degrees(Basis(a.slerp(b, 0.5)))
	assert_close(got, wanted, 1e-4, "the midpoint is the slerp of the two")

	# And it really is halfway: the turn from the start to it is the same size
	# as the turn from it to the end.
	var midpoint := Quaternion(Feature.build_rotation_basis(got))
	assert_close(a.angle_to(midpoint), midpoint.angle_to(b), 1e-4,
		"the two halves of the turn are equal")


func test_a_quarter_of_the_way_is_a_quarter_of_the_turn() -> void:
	var keyframes := _two_keyframes(100.0, 500.0)
	var got := Quaternion(Feature.build_rotation_basis(
		Keyframe.interpolate(keyframes, 200.0)))
	var a := Quaternion(Feature.build_rotation_basis(FROM))
	var b := Quaternion(Feature.build_rotation_basis(TO))
	assert_close(a.angle_to(got), a.angle_to(b) * 0.25, 1e-4,
		"a quarter of the span is a quarter of the turn")


func test_beyond_either_end_the_nearest_keyframe_is_held() -> void:
	var keyframes := _two_keyframes(100.0, 500.0)
	assert_close(Keyframe.interpolate(keyframes, 0.0), FROM, 1e-6, "younger than the first")
	assert_close(Keyframe.interpolate(keyframes, 99.9), FROM, 1e-6, "just younger than the first")
	assert_close(Keyframe.interpolate(keyframes, 500.1), TO, 1e-6, "just older than the last")
	assert_close(Keyframe.interpolate(keyframes, 4000.0), TO, 1e-6, "far older than the last")


func test_one_keyframe_holds_at_every_time() -> void:
	var keyframes: Array[Keyframe] = [Keyframe.create(750.0, TO)]
	for time in [0.0, 750.0, 2000.0, 10000.0]:
		assert_close(Keyframe.interpolate(keyframes, time), TO, 1e-6,
			"one keyframe holds at %s Ma" % time)


func test_no_keyframes_is_no_rotation() -> void:
	var keyframes: Array[Keyframe] = []
	assert_eq(Keyframe.interpolate(keyframes, 500.0), Vector3.ZERO)


func test_the_middle_of_three_keyframes_uses_its_own_two_neighbours() -> void:
	var keyframes: Array[Keyframe] = [
		Keyframe.create(0.0, FROM),
		Keyframe.create(100.0, TO),
		Keyframe.create(200.0, FROM),
	]
	# Each span is worked out from the two keyframes around it alone, so the
	# two halves of this list mirror each other exactly.
	assert_close(Keyframe.interpolate(keyframes, 50.0),
		Keyframe.interpolate(keyframes, 150.0), 1e-6,
		"the two spans are mirror images, so their midpoints match")
	assert_close(Keyframe.interpolate(keyframes, 100.0), TO, 1e-6, "the middle keyframe itself")


### The list


func test_a_keyframe_at_a_new_time_keeps_the_list_sorted() -> void:
	var keyframes: Array[Keyframe] = []
	for time in [500.0, 0.0, 1000.0, 250.0]:
		Keyframe.upsert(keyframes, time, Vector3(time, 0, 0))
	assert_eq(_times(keyframes), [0.0, 250.0, 500.0, 1000.0], "sorted, youngest first")
	for keyframe in keyframes:
		assert_close(keyframe.rotation.x, keyframe.time, 1e-6,
			"every keyframe kept the rotation it was given")


func test_a_keyframe_at_an_existing_time_replaces_it() -> void:
	var keyframes := _two_keyframes(0.0, 100.0)
	Keyframe.upsert(keyframes, 100.0, Vector3(12, 34, 0))
	assert_eq(keyframes.size(), 2, "no keyframe was added")
	assert_close(keyframes[1].rotation, Vector3(12, 34, 0), 1e-6, "the rotation was replaced")


func test_a_keyframe_is_found_by_its_time() -> void:
	var keyframes := _two_keyframes(0.0, 100.0)
	assert_eq(Keyframe.index_at(keyframes, 100.0), 1)
	assert_eq(Keyframe.index_at(keyframes, 50.0), -1, "no keyframe between them")


func test_a_file_holding_them_out_of_order_is_read_back_sorted() -> void:
	var keyframes := Keyframe.list_from_json([
		{"time": 800.0, "rotation": [1, 0, 0]},
		{"time": 20.0, "rotation": [2, 0, 0]},
		{"time": 400.0, "rotation": [3, 0, 0]},
	])
	assert_eq(_times(keyframes), [20.0, 400.0, 800.0])


func test_a_clone_is_a_copy_and_not_the_same_list() -> void:
	var keyframes := _two_keyframes(0.0, 100.0)
	var copy := Keyframe.clone_list(keyframes)
	copy[0].rotation = Vector3(9, 9, 9)
	copy[0].time = 5.0
	assert_close(keyframes[0].rotation, FROM, 1e-6, "the original rotation is untouched")
	assert_close(keyframes[0].time, 0.0, 1e-9, "and so is the original time")


### A node in the tree


func test_a_feature_exists_only_inside_its_time_range() -> void:
	var feature := Feature.create_feature("Craton")
	feature.time_range = Vector2i(100, 500)
	assert_true(not feature.exists_at(99.0), "younger than the range")
	assert_true(feature.exists_at(100.0), "the younger end counts as inside")
	assert_true(feature.exists_at(300.0), "inside")
	assert_true(feature.exists_at(500.0), "the older end counts as inside")
	assert_true(not feature.exists_at(501.0), "older than the range")


func test_a_group_is_there_whenever_its_children_are() -> void:
	var group := Feature.create_group("Cratons")
	for time in [0.0, 500.0, 10000.0]:
		assert_true(group.exists_at(time), "a group has no time range of its own")


func test_a_child_inherits_the_motion_of_its_group() -> void:
	var root := Feature.create_group("Planet")
	root.is_root = true
	var group := Feature.create_group("Craton")
	root.children.append(group)
	var terrane := Feature.create_feature("Terrane")
	group.children.append(terrane)

	# The group turns 30 degrees about the poles and the terrane 20 of its own,
	# both of them by the time the animation reaches 100 Ma.
	Keyframe.upsert(group.keyframes, 0.0, Vector3.ZERO)
	Keyframe.upsert(group.keyframes, 100.0, Vector3(30, 0, 0))
	Keyframe.upsert(terrane.keyframes, 0.0, Vector3.ZERO)
	Keyframe.upsert(terrane.keyframes, 100.0, Vector3(20, 0, 0))

	assert_true(Feature.world_basis(root, terrane, 0.0).is_equal_approx(Basis()),
		"at time zero nothing has turned")

	var world := Feature.world_basis(root, terrane, 100.0)
	assert_true(world.is_equal_approx(Feature.build_rotation_basis(Vector3(50, 0, 0))),
		"the two turns about the same axis add up: %s" %
			Feature.decompose_rotation_degrees(world))

	# Halfway through, both are half done, so the terrane is half way as well.
	var half := Feature.world_basis(root, terrane, 50.0)
	assert_close(Feature.decompose_rotation_degrees(half), Vector3(25, 0, 0), 1e-3,
		"halfway through both turns")


func test_a_group_carries_a_child_that_does_not_move_itself() -> void:
	var root := Feature.create_group("Planet")
	root.is_root = true
	var group := Feature.create_group("Craton")
	root.children.append(group)
	var terrane := Feature.create_feature("Terrane")
	group.children.append(terrane)
	Keyframe.upsert(group.keyframes, 0.0, Vector3(45, 0, 0))

	var point := PackedVector2Array([Vector2(0, 0)])
	var carried := Feature.apply_basis(point, Feature.world_basis(root, terrane, 0.0))[0]
	var group_itself := Feature.apply_basis(point, Feature.world_basis(root, group, 0.0))[0]
	assert_close(carried, group_itself, 1e-6,
		"the terrane goes exactly where the craton under it goes")


func test_a_node_outside_the_tree_does_not_rotate() -> void:
	var root := Feature.create_group("Planet")
	var stranger := Feature.create_feature("Elsewhere")
	Keyframe.upsert(stranger.keyframes, 0.0, Vector3(90, 0, 0))
	assert_true(Feature.world_basis(root, stranger, 0.0).is_equal_approx(Basis()),
		"a node the root cannot reach is left alone")


### Helpers


func _two_keyframes(first: float, second: float) -> Array[Keyframe]:
	var keyframes: Array[Keyframe] = []
	Keyframe.upsert(keyframes, first, FROM)
	Keyframe.upsert(keyframes, second, TO)
	return keyframes


func _times(keyframes: Array[Keyframe]) -> Array:
	var times: Array = []
	for keyframe in keyframes:
		times.append(keyframe.time)
	return times
