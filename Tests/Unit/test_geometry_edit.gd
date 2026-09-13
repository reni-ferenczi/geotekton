extends TestCase

# The vertex edits and the splits as functions on rings, with nothing but a ring
# going in and coming out. What the Vertex tool does with them, and the undo
# version each edit records, are Document's and are tested with it.

# A five vertex polygon that is not convex, so a split of it has to be
# triangulated rather than assumed.
const PENTAGON := [
	Vector2(0, 0), Vector2(10, 0), Vector2(14, 10), Vector2(5, 6), Vector2(0, 12),
]


func _pentagon() -> PackedVector2Array:
	return PackedVector2Array(PENTAGON)


### Insert, move and delete


func test_inserting_puts_the_vertex_before_the_index() -> void:
	var ring := _pentagon()
	var got := GeometryEdit.inserted(ring, 2, Vector2(7, 3))
	assert_eq(got.size(), ring.size() + 1, "one vertex more")
	assert_eq(got[2], Vector2(7, 3), "the new one is at the index")
	assert_eq(got[1], ring[1], "with its neighbours either side")
	assert_eq(got[3], ring[2])


func test_inserting_past_the_last_vertex_appends() -> void:
	var ring := _pentagon()
	var got := GeometryEdit.inserted(ring, ring.size(), Vector2(1, 1))
	assert_eq(got[got.size() - 1], Vector2(1, 1))


func test_an_edit_leaves_the_ring_it_was_given_alone() -> void:
	var ring := _pentagon()
	GeometryEdit.inserted(ring, 0, Vector2(9, 9))
	GeometryEdit.moved(ring, 0, Vector2(9, 9))
	GeometryEdit.removed(ring, 0)
	assert_eq(ring, _pentagon(), "the ring that went in is unchanged")


func test_moving_changes_one_vertex_and_no_other() -> void:
	var ring := _pentagon()
	var got := GeometryEdit.moved(ring, 3, Vector2(-2, -2))
	assert_eq(got.size(), ring.size(), "the same number of vertices")
	assert_eq(got[3], Vector2(-2, -2))
	for i in range(ring.size()):
		if i != 3:
			assert_eq(got[i], ring[i], "vertex %d is where it was" % i)


func test_removing_takes_one_vertex_out() -> void:
	var ring := _pentagon()
	var got := GeometryEdit.removed(ring, 1)
	assert_eq(got.size(), ring.size() - 1)
	assert_eq(got[1], ring[2], "the ones after it moved up")


func test_a_polygon_of_three_vertices_refuses_a_deletion() -> void:
	var triangle := PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(0, 5)])
	assert_true(not GeometryEdit.removal_problem(triangle, 1,
		Feature.GeometryKind.POLYGON).is_empty(),
		"two vertices are not a polygon, so the deletion is refused")
	assert_eq(GeometryEdit.removal_problem(_pentagon(), 1, Feature.GeometryKind.POLYGON), "",
		"a pentagon has one to spare")


func test_each_kind_keeps_its_own_minimum() -> void:
	var two := PackedVector2Array([Vector2(0, 0), Vector2(5, 0)])
	assert_eq(GeometryEdit.removal_problem(two, 0, Feature.GeometryKind.MULTIPOINT), "",
		"one marker is still a multipoint")
	assert_true(not GeometryEdit.removal_problem(two, 0,
		Feature.GeometryKind.POLYLINE).is_empty(),
		"one vertex is not a polyline")


func test_a_vertex_that_is_not_there_cannot_be_deleted() -> void:
	assert_true(not GeometryEdit.removal_problem(_pentagon(), 9,
		Feature.GeometryKind.POLYGON).is_empty())
	assert_true(not GeometryEdit.removal_problem(_pentagon(), -1,
		Feature.GeometryKind.POLYGON).is_empty())


### An edited ring still triangulates


func test_a_ring_edited_every_way_still_covers_itself_without_overlap() -> void:
	for ring in [
		GeometryEdit.inserted(_pentagon(), 2, Vector2(12, 5)),
		GeometryEdit.moved(_pentagon(), 2, Vector2(20, 14)),
		GeometryEdit.removed(_pentagon(), 3),
	]:
		var feature := Feature.create_feature("Edited")
		feature.add_ring(ring, Feature.GeometryKind.POLYGON)
		assert_eq(feature.triangles.size(), (ring.size() - 2) * 3,
			"a ring of %d triangulates into %d triangles" % [ring.size(), ring.size() - 2])
		assert_close(_triangle_area(feature.triangles), _ring_area(ring), 1e-4,
			"the triangles cover the ring exactly once")


### Splitting a polyline


func test_a_polyline_splits_into_two_that_share_the_vertex() -> void:
	var ring := PackedVector2Array([
		Vector2(0, 0), Vector2(0, 5), Vector2(0, 10), Vector2(0, 15), Vector2(0, 20)])
	var halves := GeometryEdit.split_polyline(ring, 2)
	assert_eq(halves.size(), 2)
	assert_eq(halves[0], PackedVector2Array([Vector2(0, 0), Vector2(0, 5), Vector2(0, 10)]))
	assert_eq(halves[1], PackedVector2Array([Vector2(0, 10), Vector2(0, 15), Vector2(0, 20)]))
	assert_eq(halves[0][halves[0].size() - 1], halves[1][0], "the split vertex is in both")
	assert_eq(halves[0].size() + halves[1].size(), ring.size() + 1,
		"every vertex once, and the shared one twice")


func test_every_vertex_of_a_split_polyline_is_accounted_for() -> void:
	var ring := PackedVector2Array([
		Vector2(1, 1), Vector2(2, 2), Vector2(3, 3), Vector2(4, 4), Vector2(5, 5), Vector2(6, 6)])
	for index in range(1, ring.size() - 1):
		var halves := GeometryEdit.split_polyline(ring, index)
		var seen := PackedVector2Array(halves[0])
		seen.append_array(halves[1].slice(1))
		assert_eq(seen, ring, "split at %d puts the vertices back in order" % index)


func test_a_polyline_does_not_split_at_an_end() -> void:
	var ring := PackedVector2Array([Vector2(0, 0), Vector2(0, 5), Vector2(0, 10)])
	assert_true(not GeometryEdit.polyline_split_problem(ring, 0).is_empty())
	assert_true(not GeometryEdit.polyline_split_problem(ring, 2).is_empty())
	assert_eq(GeometryEdit.polyline_split_problem(ring, 1), "", "but it does in the middle")


### Splitting a polygon


func test_a_polygon_splits_into_two_that_share_both_vertices() -> void:
	var ring := _pentagon()
	var halves := GeometryEdit.split_polygon(ring, 0, 2)
	assert_eq(halves[0], PackedVector2Array([ring[0], ring[1], ring[2]]))
	assert_eq(halves[1], PackedVector2Array([ring[2], ring[3], ring[4], ring[0]]))
	assert_eq(halves[0].size() + halves[1].size(), ring.size() + 2,
		"every vertex once, and the two on the cut twice")


# Every cut the ring accepts, rather than a list written out here, so that a
# ring the split refuses is never quietly left unchecked.
func test_the_two_halves_of_a_polygon_cover_the_original() -> void:
	var ring := _pentagon()
	var whole := _feature_area(ring)
	var checked := 0
	for a in range(ring.size()):
		for b in range(a + 1, ring.size()):
			if not GeometryEdit.polygon_split_problem(ring, a, b).is_empty():
				continue
			var halves := GeometryEdit.split_polygon(ring, a, b)
			var sum := _feature_area(halves[0]) + _feature_area(halves[1])
			assert_close(sum, whole, whole * 1e-4,
				"the halves of the cut from %d to %d add up to the whole" % [a, b])
			checked += 1
	assert_true(checked >= 2, "the pentagon has cuts to check, not %d" % checked)


# The pentagon is dented at vertex 3, which sits inside the line from 2 to 4.
# A cut there runs outside the shape, and the two rings it would leave overlap
# rather than cover it, so it is refused instead.
func test_a_cut_across_the_mouth_of_a_dent_is_refused() -> void:
	var ring := _pentagon()
	assert_true(not GeometryEdit.polygon_split_problem(ring, 2, 4).is_empty(),
		"the cut from 2 to 4 passes outside the pentagon")
	assert_eq(GeometryEdit.cut_problem(ring, 2, 4), GeometryEdit.CutProblem.OUTSIDE)
	assert_eq(GeometryEdit.cut_problem(ring, 0, 2), GeometryEdit.CutProblem.NONE,
		"while the cut from 0 to 2 is inside")


func test_a_cut_that_crosses_an_edge_is_refused() -> void:
	# An L. The line from the end of one arm to the end of the other leaves the
	# shape through the inner corner and comes back, crossing an edge each way.
	var el := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 4),
		Vector2(4, 4), Vector2(4, 10), Vector2(0, 10)])
	assert_eq(GeometryEdit.cut_problem(el, 1, 5), GeometryEdit.CutProblem.CROSSES,
		"the line from one arm to the other crosses the edge at the inner corner")
	assert_true(not GeometryEdit.polygon_split_problem(el, 1, 5).is_empty())
	assert_eq(GeometryEdit.cut_problem(el, 0, 3), GeometryEdit.CutProblem.NONE,
		"while the line to the inner corner itself stays inside")


func test_the_cut_runs_the_same_way_round_whichever_order_it_is_given() -> void:
	var ring := _pentagon()
	var forwards := GeometryEdit.split_polygon(ring, 1, 3)
	var backwards := GeometryEdit.split_polygon(ring, 3, 1)
	assert_eq(forwards[0], backwards[0])
	assert_eq(forwards[1], backwards[1])


func test_a_polygon_does_not_split_between_neighbours() -> void:
	var ring := _pentagon()
	assert_true(not GeometryEdit.polygon_split_problem(ring, 1, 2).is_empty(),
		"neighbours would leave one half a line")
	assert_true(not GeometryEdit.polygon_split_problem(ring, 0, 4).is_empty(),
		"and so would the two ends of the ring, which are neighbours too")
	assert_true(not GeometryEdit.polygon_split_problem(ring, 2, 2).is_empty(),
		"nor does it split a vertex from itself")
	assert_eq(GeometryEdit.polygon_split_problem(ring, 0, 2), "",
		"but two apart, with the cut inside, is fine")


func test_a_triangle_cannot_be_split_at_all() -> void:
	var triangle := PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(0, 5)])
	for pair in [[0, 1], [1, 2], [0, 2]]:
		assert_true(not GeometryEdit.polygon_split_problem(triangle, pair[0], pair[1]).is_empty(),
			"every pair of a triangle is a pair of neighbours: %d and %d" % pair)


### Splitting a polygon along a drawn cut


const SQUARE := [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]


func test_a_straight_cut_puts_its_ends_on_the_boundary() -> void:
	var ring := PackedVector2Array(SQUARE)
	var path := PackedVector2Array([Vector2(5, -1), Vector2(5, 11)])
	assert_eq(GeometryEdit.split_along_problem(ring, path), "")
	var halves := GeometryEdit.split_along(ring, path)
	assert_eq(halves[0], PackedVector2Array([
		Vector2(5, 0), Vector2(10, 0), Vector2(10, 10), Vector2(5, 10)]),
		"the ends were projected onto the two edges they were clicked beside")
	assert_eq(halves[1], PackedVector2Array([
		Vector2(5, 10), Vector2(0, 10), Vector2(0, 0), Vector2(5, 0)]))
	assert_close(_feature_area(halves[0]), 50.0, 1e-3)
	assert_close(_feature_area(halves[1]), 50.0, 1e-3)


func test_a_cut_with_two_points_between_its_ends_goes_to_both_halves() -> void:
	var ring := PackedVector2Array(SQUARE)
	var path := PackedVector2Array([Vector2(5, -1), Vector2(3, 4), Vector2(7, 6), Vector2(5, 11)])
	assert_eq(GeometryEdit.split_along_problem(ring, path), "")
	var halves := GeometryEdit.split_along(ring, path)
	assert_eq(halves[0], PackedVector2Array([
		Vector2(5, 0), Vector2(10, 0), Vector2(10, 10), Vector2(5, 10),
		Vector2(7, 6), Vector2(3, 4)]), "the first half runs back along the cut")
	assert_eq(halves[1], PackedVector2Array([
		Vector2(5, 10), Vector2(0, 10), Vector2(0, 0), Vector2(5, 0),
		Vector2(3, 4), Vector2(7, 6)]), "and the second forwards")
	assert_close(_feature_area(halves[0]) + _feature_area(halves[1]), 100.0, 1e-3,
		"the halves add up to the square")


func test_the_halves_hold_every_vertex_once_and_the_projected_ends_twice() -> void:
	var ring := _pentagon()
	# Both ends land halfway along an edge, so the projected points are exact.
	var path := PackedVector2Array([Vector2(5, -2), Vector2(4, 4), Vector2(-1, 6)])
	assert_eq(GeometryEdit.split_along_problem(ring, path), "")
	var halves := GeometryEdit.split_along(ring, path)
	var together := PackedVector2Array(halves[0])
	together.append_array(halves[1])
	for vertex in ring:
		assert_eq(together.count(vertex), 1, "%s is in one half" % vertex)
	for shared in [Vector2(5, 0), Vector2(4, 4), Vector2(0, 6)]:
		assert_eq(together.count(shared), 2, "%s is in both halves" % shared)
	assert_eq(together.size(), ring.size() + 2 * 3,
		"nothing else: the five vertices, and the two ends and the point between twice")


func test_a_cut_that_leaves_a_concave_polygon_is_refused() -> void:
	# The pentagon is dented at vertex 3. Clicked beyond vertices 2 and 4, the
	# ends land on them, and the line between runs across the mouth of the dent.
	var ring := _pentagon()
	assert_eq(GeometryEdit.split_along_problem(ring,
		PackedVector2Array([Vector2(15, 11), Vector2(0, 13)])),
		"The cut runs outside the shape.")
	# Through a point inside the dent, the cut crosses the edge on its way there.
	assert_eq(GeometryEdit.split_along_problem(ring,
		PackedVector2Array([Vector2(5, -1), Vector2(7, 9), Vector2(-1, 6)])),
		"The cut crosses the edge of the shape between its ends.")


func test_a_cut_with_both_ends_on_one_edge_is_refused() -> void:
	var ring := PackedVector2Array(SQUARE)
	assert_eq(GeometryEdit.split_along_problem(ring,
		PackedVector2Array([Vector2(3, -1), Vector2(5, 5), Vector2(7, -1)])),
		"Both ends of the cut land on the same edge.")
	assert_true(not GeometryEdit.split_along_problem(ring,
		PackedVector2Array([Vector2(3, -1)])).is_empty(), "one point is no cut")


### Picking


func test_the_nearest_point_inside_the_radius_is_found() -> void:
	var points := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(10, 10), Vector2(50, 50)])
	assert_eq(GeometryEdit.nearest_point(points, Vector2(12, 11), 10.0), 2,
		"the one two pixels away, not the one further off")
	assert_eq(GeometryEdit.nearest_point(points, Vector2(0, 2), 10.0), 0)


func test_a_point_outside_the_radius_is_not_picked() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(100, 100)])
	assert_eq(GeometryEdit.nearest_point(points, Vector2(20, 20), 10.0), -1,
		"nothing is near enough")
	assert_eq(GeometryEdit.nearest_point(points, Vector2(0, 10), 10.0), 0,
		"exactly on the radius still counts")
	assert_eq(GeometryEdit.nearest_point(points, Vector2(0, 10.001), 10.0), -1,
		"just outside it does not")


func test_nothing_is_picked_out_of_an_empty_list() -> void:
	assert_eq(GeometryEdit.nearest_point(PackedVector2Array(), Vector2.ZERO, 10.0), -1)


func test_two_points_at_the_same_distance_pick_the_earlier() -> void:
	var points := PackedVector2Array([Vector2(-1, 0), Vector2(1, 0)])
	assert_eq(GeometryEdit.nearest_point(points, Vector2(0, 0), 10.0), 0)


func test_the_nearest_segment_and_how_far_along_it() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])
	var got := GeometryEdit.nearest_segment(points, Vector2(25, 4), false)
	assert_eq(got[0], 0, "the first segment")
	assert_close(got[1], 4.0, 1e-4, "four pixels from it")
	assert_close(got[2], 0.25, 1e-4, "a quarter of the way along")

	got = GeometryEdit.nearest_segment(points, Vector2(97, 50), false)
	assert_eq(got[0], 1, "the second segment")
	assert_close(got[2], 0.5, 1e-4, "halfway along it")


func test_a_point_past_the_end_of_a_segment_stays_on_it() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	var got := GeometryEdit.nearest_segment(points, Vector2(150, 0), false)
	assert_close(got[2], 1.0, 1e-6, "clamped to the far end")
	assert_close(got[1], 50.0, 1e-4, "and measured from there")


func test_a_closed_run_has_the_segment_back_to_the_start() -> void:
	# A square, so the closing segment is the left side and a point four pixels
	# to the right of it is four pixels from that segment and no other.
	var points := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
	var open_run := GeometryEdit.nearest_segment(points, Vector2(4, 50), false)
	var closed := GeometryEdit.nearest_segment(points, Vector2(4, 50), true)
	assert_eq(closed[0], 3, "the closing segment is nearest")
	assert_close(closed[1], 4.0, 1e-4)
	assert_true(open_run[0] != 3, "which the open run does not have at all")


func test_a_run_with_no_segment_picks_nothing() -> void:
	assert_eq(GeometryEdit.nearest_segment(
		PackedVector2Array([Vector2(1, 1)]), Vector2.ZERO, false)[0], -1)


### Areas, for the split checks


# The area a ring covers, worked out through the triangulation rather than from
# the ring, so that the split checks compare what is actually drawn.
func _feature_area(ring: PackedVector2Array) -> float:
	var feature := Feature.create_feature("Half")
	feature.add_ring(ring, Feature.GeometryKind.POLYGON)
	return _triangle_area(feature.triangles)


func _triangle_area(triangles: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(0, triangles.size() - 2, 3):
		var a := triangles[i]
		var b := triangles[i + 1]
		var c := triangles[i + 2]
		total += absf((b - a).cross(c - a)) * 0.5
	return total


func _ring_area(ring: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		total += a.cross(b)
	return absf(total) * 0.5
