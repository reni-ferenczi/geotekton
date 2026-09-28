extends TestCase

# Planet.collect_geometry and Planet.hit_test, the CPU counterpart of the
# geometry shader. A polygon is hit inside its triangles, which must be wound
# counter-clockwise as seen from outside the sphere, the rule
# Feature.faces_outwards enforces. A polyline and a multipoint are hit
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
	assert_eq(geometry.colors, [Color.RED] as Array[Color], "one color for the one feature")
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


### The bounding cap
#
# The cap is what lets the hit test throw a feature away with one multiply
# instead of walking its triangles. Everything here checks that it never throws
# away something it should have kept; that it is faster is measured by
# Tests/performance.py rather than asserted here.


func test_the_cap_holds_every_vertex_of_its_feature() -> void:
	var feature := _make_feature("Craton", Color.RED, Vector3.ZERO)
	var geometry := Planet.collect_geometry(_make_root([feature]))
	assert_eq(geometry.features.size(), 1)
	assert_true(geometry.cap_cosines[0] > -1.0, "a small triangle gets a cap worth having")

	for vertex in TRIANGLE:
		var unit := Planet._latlon_to_unit(deg_to_rad(vertex.x), deg_to_rad(vertex.y))
		assert_true(unit.dot(geometry.cap_centres[0]) >= geometry.cap_cosines[0],
			"the vertex at %s is inside the cap" % vertex)


func test_the_cap_covers_the_click_tolerance_around_a_marker() -> void:
	# A multipoint is hit within POINT_HIT_RADIUS of its marker, so the cap has
	# to reach that far too or the hit would be rejected before it is tested.
	var feature := _make_feature("Islands", Color.RED, Vector3.ZERO,
		PackedVector2Array([Vector2(0, 0)]), Feature.GeometryKind.MULTIPOINT)
	var geometry := Planet.collect_geometry(_make_root([feature]))
	var edge := Vector2(0.0, rad_to_deg(2.0 * asin(Planet.POINT_HIT_RADIUS * 0.5)) * 0.99)
	assert_eq(Planet.hit_test(edge.x, edge.y, geometry), feature,
		"a click just inside the tolerance still reaches the marker")


func test_a_feature_that_covers_the_planet_keeps_a_cap_of_everything() -> void:
	# Four markers at the poles and on opposite sides of the equator. No cap
	# smaller than the whole sphere holds them, so the hit test walks the
	# feature as it would have without caps at all.
	var feature := _make_feature("Everywhere", Color.RED, Vector3.ZERO,
		PackedVector2Array([Vector2(90, 0), Vector2(-90, 0), Vector2(0, 0), Vector2(0, 180)]),
		Feature.GeometryKind.MULTIPOINT)
	var geometry := Planet.collect_geometry(_make_root([feature]))
	assert_close(geometry.cap_cosines[0], -1.0, 1e-9, "the cap holds the whole sphere")
	assert_eq(Planet.hit_test(90, 0, geometry), feature, "and every marker is still hit")
	assert_eq(Planet.hit_test(0, 180, geometry), feature)


func test_the_cap_follows_the_feature_when_the_time_moves_it() -> void:
	# The cap is in the feature's own frame, so it is the point being asked
	# about that is carried into that frame, not the cap out of it. A feature
	# with two keyframes is hit in two different places at two times, with the
	# cap never rebuilt in between.
	var feature := _make_feature("Craton", Color.RED, Vector3.ZERO)
	Keyframe.upsert(feature.keyframes, 0.0, Vector3.ZERO)
	Keyframe.upsert(feature.keyframes, 100.0, Vector3(90, 0, 0))
	var root := _make_root([feature])
	var geometry := Planet.collect_geometry(root, 0.0)
	assert_eq(Planet.hit_test(0, 0, geometry), feature, "at time zero it is where it was drawn")

	geometry.resolve(root, 100.0)
	assert_eq(Planet.hit_test(0, 0, geometry), null, "at 100 it has moved off that point")
	assert_eq(Planet.hit_test(0, -90, geometry), feature, "and onto this one")


func test_a_feature_of_several_parts_is_capped_around_all_of_them() -> void:
	var feature := Feature.create_feature("Two blobs", Color.RED)
	feature.add_ring(PackedVector2Array([Vector2(-5, -35), Vector2(5, -25), Vector2(-5, -15)]),
		Feature.GeometryKind.POLYGON)
	feature.add_ring(PackedVector2Array([Vector2(-5, 15), Vector2(5, 25), Vector2(-5, 35)]),
		Feature.GeometryKind.POLYGON)
	var geometry := Planet.collect_geometry(_make_root([feature]))
	assert_eq(geometry.starts[0], 0, "both parts belong to the one feature")
	assert_eq(geometry.ends[0], geometry.primitives.size())
	assert_eq(Planet.hit_test(-2, -25, geometry), feature, "the first part is hit")
	assert_eq(Planet.hit_test(-2, 25, geometry), feature, "and so is the second")
	assert_eq(Planet.hit_test(0, 0, geometry), null, "the gap between them is not")


### The shader's blocks
#
# GP-0023: the shader skips a column, and a block of up to BLOCK_SIZE of its
# primitives, whose cap the fragment is outside. That is only safe if every
# primitive is in exactly one block of its own column and inside that block's
# cap, and if reordering a column never moves a primitive across one of
# another kind, which would change what is drawn over what.


# A polygon ring of many vertices round an ellipse, so ear clipping gives far
# more triangles than one block holds.
func _big_ring(vertices: int) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for i in vertices:
		var angle := -TAU * i / vertices
		ring.append(Vector2(20.0 * sin(angle), 30.0 * cos(angle)))
	return ring


func test_every_primitive_is_in_one_block_of_its_column_and_inside_its_cap() -> void:
	var big := _make_feature("Big", Color.RED, Vector3.ZERO, _big_ring(200))
	var line := _make_feature("Coast", Color.BLUE, Vector3.ZERO, _big_ring(120),
		Feature.GeometryKind.POLYLINE)
	var geometry := Planet.collect_geometry(_make_root([big, line]))
	assert_true(geometry.primitives.size() > 4 * Planet.BLOCK_SIZE, "enough to need blocks")
	var seen := {}
	for column in geometry.features.size():
		var next := geometry.starts[column]
		for block in range(geometry.block_starts[column], geometry.block_ends[column]):
			assert_eq(geometry.block_first[block], next, "block %d follows the last" % block)
			assert_true(geometry.block_last[block] - geometry.block_first[block] <= Planet.BLOCK_SIZE,
				"block %d holds no more than a block" % block)
			for i in range(geometry.block_first[block], geometry.block_last[block]):
				seen[i] = true
				for unit: Vector3 in Planet._units_of(geometry.primitives[i]):
					assert_true(unit.dot(geometry.block_centres[block])
						>= cos(geometry.block_angles[block]) - 1e-6,
						"primitive %d is inside the cap of block %d" % [i, block])
					assert_true(unit.dot(geometry.draw_centres[column])
						>= cos(geometry.draw_angles[column]) - 1e-6,
						"and inside its column's cap")
			next = geometry.block_last[block]
		assert_eq(next, geometry.ends[column], "the blocks of column %d end with it" % column)
	assert_eq(seen.size(), geometry.primitives.size(), "every primitive is in a block")


# A coast 120 degrees long along the equator, a vertex every degree. Its
# segments are drawn back to front here, so it is the order that has to put
# neighbours into the same block.
func _coast() -> PackedVector2Array:
	var ring := PackedVector2Array()
	for lon in range(60, -61, -1):
		ring.append(Vector2(0.4 * (lon % 2), lon))
	return ring


func test_the_blocks_of_a_long_coast_are_short_stretches_of_it() -> void:
	var coast := _make_feature("Coast", Color.RED, Vector3.ZERO, _coast(),
		Feature.GeometryKind.POLYLINE)
	var geometry := Planet.collect_geometry(_make_root([coast]))
	assert_true(geometry.block_centres.size() > 2, "the coast takes several blocks")
	var widest := 0.0
	for block in geometry.block_centres.size():
		widest = maxf(widest, geometry.block_angles[block])
	# A block of 32 one degree segments reaches about 16 degrees either way.
	assert_true(widest < deg_to_rad(20.0),
		"each block is a short stretch of the coast: %s rad of %s"
		% [widest, geometry.draw_angles[0]])


func test_reordering_keeps_each_kind_where_it_was() -> void:
	# A hotspot is its track's segments and then its sample dots, and a crust its
	# bands and then its lines: kinds that are drawn over each other in turn.
	var primitives: Array = []
	for i in 40:
		primitives.append({"kind": Planet.Primitive.SEGMENT, "verts": [Vector2(0, 40 - i)]})
	for i in 40:
		primitives.append({"kind": Planet.Primitive.SAMPLE, "verts": [Vector2(0, i)]})
	Planet._order_column(primitives, 0, primitives.size())
	for i in 40:
		assert_eq(primitives[i]["kind"], Planet.Primitive.SEGMENT, "segments stay first")
		assert_eq(primitives[40 + i]["kind"], Planet.Primitive.SAMPLE, "and the dots after them")


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


# GP-0030: features that carry the same keyframes, as every feature of an
# imported plate does, share one rotation per step, which has to be the one
# each would have got on its own. A feature moving otherwise shares nothing.
func test_features_that_move_alike_share_their_rotation() -> void:
	var one := _make_feature("One", Color.RED, Vector3.ZERO)
	var two := _make_feature("Two", Color.RED, Vector3.ZERO)
	var other := _make_feature("Other", Color.RED, Vector3.ZERO)
	for feature in [one, two]:
		Keyframe.upsert(feature.keyframes, 0.0, Vector3.ZERO)
		Keyframe.upsert(feature.keyframes, 100.0, Vector3(20.0, 5.0, 0.0))
	Keyframe.upsert(other.keyframes, 0.0, Vector3.ZERO)
	Keyframe.upsert(other.keyframes, 100.0, Vector3(-20.0, 0.0, 0.0))
	var geometry := Planet.collect_geometry(_make_root([one, two, other]))
	assert_eq(geometry.same_motion[geometry.index_for(two)],
		geometry.same_motion[geometry.index_for(one)], "two moves as one does")
	assert_eq(geometry.same_motion[geometry.index_for(other)], geometry.index_for(other),
		"other moves its own way")
	geometry.resolve(null, 40.0)
	for feature in [one, two, other]:
		assert_true(geometry.bases[geometry.index_for(feature)].is_equal_approx(feature.basis_at(40.0)),
			"%s is where its own keyframes put it" % feature.title)


func _is_front_facing(a: Vector2, b: Vector2, c: Vector2) -> bool:
	return Feature.faces_outwards(a, b, c)
