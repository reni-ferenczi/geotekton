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


func test_a_deletion_under_the_minimum_is_not_refused() -> void:
	# The part goes with the vertex instead; see Document.remove_vertex().
	var triangle := PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(0, 5)])
	assert_eq(GeometryEdit.removal_problem(triangle, 1), "",
		"the last vertices of a part can be taken out one by one")
	var one := PackedVector2Array([Vector2(0, 0)])
	assert_eq(GeometryEdit.removal_problem(one, 0), "", "down to the last one")


func test_a_vertex_that_is_not_there_cannot_be_deleted() -> void:
	assert_true(not GeometryEdit.removal_problem(_pentagon(), 9).is_empty())
	assert_true(not GeometryEdit.removal_problem(_pentagon(), -1).is_empty())


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
	# Each half starts with the cut, the first from 2 back to 0 and the second
	# from 0 to 2.
	assert_eq(halves[0], PackedVector2Array([ring[2], ring[0], ring[1]]))
	assert_eq(halves[1], PackedVector2Array([ring[0], ring[2], ring[3], ring[4]]))
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
		Vector2(5, 10), Vector2(5, 0), Vector2(10, 0), Vector2(10, 10)]),
		"the ends are where the line crosses the two edges")
	assert_eq(halves[1], PackedVector2Array([
		Vector2(5, 0), Vector2(5, 10), Vector2(0, 10), Vector2(0, 0)]))
	assert_close(_feature_area(halves[0]), 50.0, 1e-3)
	assert_close(_feature_area(halves[1]), 50.0, 1e-3)


func test_a_cut_with_two_points_between_its_ends_goes_to_both_halves() -> void:
	var ring := PackedVector2Array(SQUARE)
	var path := PackedVector2Array([Vector2(3, -1), Vector2(3, 4), Vector2(7, 6), Vector2(7, 11)])
	assert_eq(GeometryEdit.split_along_problem(ring, path), "")
	var halves := GeometryEdit.split_along(ring, path)
	assert_eq(halves[0], PackedVector2Array([
		Vector2(7, 10), Vector2(7, 6), Vector2(3, 4), Vector2(3, 0),
		Vector2(10, 0), Vector2(10, 10)]), "the first half starts back along the cut")
	assert_eq(halves[1], PackedVector2Array([
		Vector2(3, 0), Vector2(3, 4), Vector2(7, 6), Vector2(7, 10),
		Vector2(0, 10), Vector2(0, 0)]), "and the second forwards along it")
	assert_close(_feature_area(halves[0]) + _feature_area(halves[1]), 100.0, 1e-3,
		"the halves add up to the square")


func test_the_halves_hold_every_vertex_once_and_the_ends_twice() -> void:
	var ring := _pentagon()
	# The first and last stretches cross the boundary square on, so the ends
	# are exact.
	var path := PackedVector2Array([Vector2(5, -2), Vector2(5, 2), Vector2(2, 6), Vector2(-1, 6)])
	assert_eq(GeometryEdit.split_along_problem(ring, path), "")
	var halves := GeometryEdit.split_along(ring, path)
	var together := PackedVector2Array(halves[0])
	together.append_array(halves[1])
	for vertex in ring:
		assert_eq(together.count(vertex), 1, "%s is in one half" % vertex)
	for shared in [Vector2(5, 0), Vector2(5, 2), Vector2(2, 6), Vector2(0, 6)]:
		assert_eq(together.count(shared), 2, "%s is in both halves" % shared)
	assert_eq(together.size(), ring.size() + 2 * 4,
		"nothing else: the five vertices, and the two ends and the points between twice")


func test_a_line_that_misses_the_shape_is_refused() -> void:
	# The pentagon is dented at vertex 3; this runs past the mouth of the dent.
	assert_eq(GeometryEdit.split_along_problem(_pentagon(),
		PackedVector2Array([Vector2(15, 11), Vector2(0, 13)])),
		"The cut runs outside the shape.")
	assert_true(not GeometryEdit.split_along_problem(_pentagon(),
		PackedVector2Array([Vector2(3, -1)])).is_empty(), "one point is no cut")


# The pieces on each side, and their areas added up.
func _side_areas(cut: Dictionary) -> Array:
	var areas := []
	for side in [GeometryEdit.LEFT, GeometryEdit.RIGHT]:
		var total := 0.0
		for piece: PackedVector2Array in cut["pieces"][side]:
			total += _ring_area(piece)
		areas.append(total)
	return areas


func test_a_cut_in_and_out_of_a_dent_makes_three_pieces_on_two_sides() -> void:
	# In at the bottom, out into the dent, and in again to leave on the left:
	# two stretches, so three pieces, the two ends of the pentagon on one side.
	var ring := _pentagon()
	var cut := GeometryEdit.cut_pieces(ring,
		PackedVector2Array([Vector2(5, -1), Vector2(7, 9), Vector2(-1, 6)]))
	assert_eq(cut["problem"], "")
	assert_eq(cut["stretches"], 2)
	var counts := [cut["pieces"][GeometryEdit.LEFT].size(), cut["pieces"][GeometryEdit.RIGHT].size()]
	counts.sort()
	assert_eq(counts, [1, 2], "one piece on one side and two on the other")
	var areas := _side_areas(cut)
	assert_close(areas[0] + areas[1], _ring_area(ring), 1e-3, "the pieces add up to the pentagon")


func test_a_cut_across_both_arms_of_a_c_makes_two_features_of_two_parts() -> void:
	# A C opening to the east; a line down the middle crosses both arms.
	var ring := PackedVector2Array([Vector2(0, 0), Vector2(0, 10), Vector2(3, 10),
		Vector2(3, 3), Vector2(7, 3), Vector2(7, 10), Vector2(10, 10), Vector2(10, 0)])
	var cut := GeometryEdit.cut_pieces(ring, PackedVector2Array([Vector2(-1, 6), Vector2(11, 6)]))
	assert_eq(cut["problem"], "")
	assert_eq(cut["stretches"], 2)
	assert_eq(cut["pieces"][GeometryEdit.LEFT].size() + cut["pieces"][GeometryEdit.RIGHT].size(), 3)
	var areas := _side_areas(cut)
	assert_close(areas[0] + areas[1], _ring_area(ring), 1e-3)
	# The tips of the arms, 3 by 4 each, are on one side together.
	assert_true(is_equal_approx(areas[0], 24.0) or is_equal_approx(areas[1], 24.0),
		"the two tips are one side: %s" % [areas])


func test_a_bite_out_of_one_edge_is_made() -> void:
	var ring := PackedVector2Array(SQUARE)
	var cut := GeometryEdit.cut_pieces(ring,
		PackedVector2Array([Vector2(3, -1), Vector2(5, 5), Vector2(7, -1)]))
	assert_eq(cut["problem"], "")
	var areas := _side_areas(cut)
	areas.sort()
	# The triangle from where the line crosses the edge, (3 1/3, 0) and
	# (6 2/3, 0), up to (5, 5).
	assert_close(areas[0], 25.0 / 3.0, 1e-3, "the bite")
	assert_close(areas[1], 275.0 / 3.0, 1e-3, "and the rest")


func test_a_cut_that_crosses_itself_inside_is_refused() -> void:
	assert_eq(GeometryEdit.split_along_problem(PackedVector2Array(SQUARE), PackedVector2Array([
		Vector2(2, -1), Vector2(8, 11), Vector2(8, 5), Vector2(2, 5), Vector2(2, 11)])),
		"The cut crosses itself.")


# Three cratons of worlds/TestA.geotekt, as stored, on which a cut clicked
# outside the outline used to go to the nearest point of it, which is on
# another edge often enough to refuse one clean cut in five; see
# notes/split-refusals in the workspace.
const PURPLE_CRATON := [[-24.6, 30.2], [-22.5, 21.7], [-14.4, 19.1], [-9.0, 30.5],
	[-12.5, 39.2], [-19.2, 35.7], [-22.5, 37.6]]
const BIG_BOI := [[-3.5, 81.4], [-3.4, 70.6], [3.0, 66.5], [2.9, 60.1], [7.9, 51.7],
	[18.9, 45.7], [21.1, 40.4], [38.5, 40.3], [40.5, 59.9], [35.0, 94.9], [16.5, 102.0],
	[6.9, 86.6], [15.8, 70.5], [13.1, 67.0]]
const BIG_BOI_2 := [[21.1, 40.4], [18.9, 45.7], [7.9, 51.7], [2.9, 60.1], [3.0, 66.5],
	[-3.4, 70.6], [-3.5, 81.4], [-11.5, 88.4], [-23.3, 68.9], [-21.2, 62.0], [-32.8, 66.5],
	[-39.2, 72.5], [-36.9, 58.3], [-31.9, 42.3], [-41.5, 45.8], [-47.2, 41.9], [-38.0, 33.4],
	[-42.8, 21.3], [-37.4, 18.2], [-28.1, 0.9], [-15.0, 0.8], [-3.9, 6.7], [4.2, 25.1],
	[3.6, 40.4]]


func _ring_of(points: Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for point in points:
		ring.append(Vector2(point[0], point[1]))
	return ring


# How many times the line from a to b crosses the ring, or -1 when it passes
# within 0.05° of a vertex or of another crossing, which is a graze rather than
# a clean cut.
func _clean_crossings(ring: PackedVector2Array, a: Vector2, b: Vector2) -> int:
	var hits := PackedVector2Array()
	for i in ring.size():
		var j := (i + 1) % ring.size()
		var at: Variant = Geometry2D.segment_intersects_segment(a, b, ring[i], ring[j])
		if at == null:
			continue
		if (at as Vector2).distance_to(ring[i]) < 0.05 or (at as Vector2).distance_to(ring[j]) < 0.05:
			return -1
		for hit in hits:
			if hit.distance_to(at) < 0.05:
				return -1
		hits.append(at)
	return hits.size()


func test_a_clean_cut_clicked_outside_an_irregular_outline_is_never_refused() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for points in [PURPLE_CRATON, BIG_BOI, BIG_BOI_2]:
		var ring := _ring_of(points)
		for pad in [0.3, 2.0, 6.0]:
			var tried := 0
			var refused := 0
			var example := ""
			while tried < 200:
				var i := rng.randi_range(0, ring.size() - 1)
				var k := rng.randi_range(0, ring.size() - 1)
				var p := ring[i].lerp(ring[(i + 1) % ring.size()], rng.randf_range(0.1, 0.9))
				var q := ring[k].lerp(ring[(k + 1) % ring.size()], rng.randf_range(0.1, 0.9))
				if p.distance_to(q) < 3.0 or not Geometry2D.is_point_in_polygon((p + q) * 0.5, ring):
					continue
				var along: Vector2 = (q - p).normalized() * pad
				var path := PackedVector2Array([p - along, (p + q) * 0.5, q + along])
				if _clean_crossings(ring, path[0], path[2]) != 2:
					continue
				tried += 1
				var problem := GeometryEdit.split_along_problem(ring, path)
				if not problem.is_empty():
					refused += 1
					example = "%s: %s" % [path, problem]
			assert_eq(refused, 0, "%d-gon, ends %s° outside, e.g. %s" % [ring.size(), pad, example])


func test_an_end_clicked_outside_goes_where_the_cut_crosses_the_outline() -> void:
	# From Big Boi 2: the start click was put on another edge 6° away.
	var ring := _ring_of(BIG_BOI_2)
	var path := PackedVector2Array([Vector2(-2.6, 74.7), Vector2(-20.0, 50.0)])
	var cut := GeometryEdit.cut_across(ring, path)
	var start: Vector2 = cut[0][cut[1]]
	assert_true(start.distance_to(Vector2(-3.4, 74.7)) > 0.5, "not the nearest point, %s" % start)
	assert_true(GeometryEdit.nearest_segment(ring, start, true)[1] < 1e-4, "on the outline")
	assert_true(GeometryEdit.nearest_segment(path, start, false)[1] < 1e-4, "on the drawn line")
	assert_eq(GeometryEdit.split_along_problem(ring, path), "")


func test_an_end_stopped_inside_is_carried_on_to_the_outline() -> void:
	# Stopped half a degree short of the edges, and not heading straight at
	# them: each end goes on the way the line was going.
	var ring := PackedVector2Array(SQUARE)
	var cut := GeometryEdit.cut_pieces(ring,
		PackedVector2Array([Vector2(5, 0.5), Vector2(4, 5), Vector2(5, 9.5)]))
	assert_eq(cut["problem"], "")
	var edge: PackedVector2Array = cut["edge"]
	assert_eq(edge.size(), 5, "the reached ends, both clicks and the point between")
	assert_true(edge[0].is_equal_approx(Vector2(5.1111111, 0.0)), "on from the start: %s" % edge[0])
	assert_true(edge[4].is_equal_approx(Vector2(5.1111111, 10.0)), "and from the end: %s" % edge[4])


# An octagon of radius 5° around (lat, lon), stored with longitudes in
# -180..180 the way a feature drawn there holds them.
func _octagon_at(lat: float, lon: float) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for i in 8:
		var angle := TAU * (i + 0.5) / 8
		ring.append(Vector2(lat + 5.0 * cos(angle), wrapf(lon + 5.0 * sin(angle), -180.0, 180.0)))
	return ring


func _check_halves(ring: PackedVector2Array, path: PackedVector2Array, where: String) -> void:
	assert_eq(GeometryEdit.split_along_problem(ring, path), "", where)
	var halves := GeometryEdit.split_along(ring, path)
	var whole := Measure.ring_area(ring)
	var first := Measure.ring_area(halves[0])
	var second := Measure.ring_area(halves[1])
	assert_close(first + second, whole, whole * 1e-3, "%s: the halves add up to the whole" % where)
	assert_true(first > whole * 0.3 and second > whole * 0.3, "%s: cut through the middle" % where)


func test_a_polygon_across_the_dateline_splits() -> void:
	_check_halves(_octagon_at(0.0, 180.0),
		PackedVector2Array([Vector2(-7, 179.5), Vector2(0, -179.8), Vector2(7, 179.5)]), "on 180°")
	_check_halves(_octagon_at(20.0, 177.0),
		PackedVector2Array([Vector2(13, 177), Vector2(27, 177)]), "reaching over 180°")


func test_a_polygon_round_a_pole_splits() -> void:
	var ring := PackedVector2Array()
	for i in 8:
		ring.append(Vector2(80.0, -157.5 + 45.0 * i))
	_check_halves(ring, PackedVector2Array([Vector2(75, 0), Vector2(75, 180)]), "round the pole")


func test_the_vertex_tool_splits_a_polygon_across_the_dateline() -> void:
	var ring := _octagon_at(0.0, 180.0)
	assert_eq(GeometryEdit.polygon_split_problem(ring, 0, 4), "")


func test_a_cut_across_the_dateline_is_clipped_to_the_ring() -> void:
	var ring := _octagon_at(0.0, 180.0)
	var cut := GeometryEdit.clip_path(ring,
		PackedVector2Array([Vector2(-7, 179.5), Vector2(7, 179.5)]))
	assert_eq(cut.size(), 2, "from where the path goes in to where it comes out")
	for end in cut:
		assert_true(absf(end.y - 179.5) < 0.1 and absf(end.x) > 4.0, "an end on the outline: %s" % end)
	assert_true(GeometryEdit.contains(ring, Vector2(0, -179.0)), "the middle of the ring is in it")
	assert_true(GeometryEdit.touches(ring, PackedVector2Array([Vector2(-10, 179.0), Vector2(10, 179.0)])))


### Dividing the parts of a feature


# Two triangles side by side, west and east of the prime meridian.
func _two_parts() -> Array:
	return [
		PackedVector2Array([Vector2(-5, -20), Vector2(5, -20), Vector2(0, -10)]),
		PackedVector2Array([Vector2(-5, 10), Vector2(5, 10), Vector2(0, 20)]),
	]


func test_a_path_touches_a_ring_by_crossing_it_or_ending_inside_it() -> void:
	var ring: PackedVector2Array = _two_parts()[0]
	assert_true(GeometryEdit.touches(ring, PackedVector2Array([Vector2(0, -30), Vector2(0, -15)])),
		"a path that crosses the edge touches the ring")
	assert_true(GeometryEdit.touches(ring, PackedVector2Array([Vector2(0, -18), Vector2(1, -17)])),
		"so does one that lies inside it")
	assert_true(not GeometryEdit.touches(ring, PackedVector2Array([Vector2(-20, 0), Vector2(20, 0)])),
		"one that passes beside it does not")


func test_the_side_of_a_point_follows_the_nearest_stretch_of_the_divider() -> void:
	var divider := PackedVector2Array([Vector2(-20, 0), Vector2(20, 0)])
	assert_true(GeometryEdit.side_of(divider, Vector2(0, -10)) != GeometryEdit.side_of(divider, Vector2(0, 10)),
		"the two sides of a straight divider differ")
	assert_eq(GeometryEdit.side_of(divider, Vector2(40, -10)), GeometryEdit.side_of(divider, Vector2(0, -10)),
		"a point past the end is on the side the extended divider puts it")
	# A divider that bends round: the far side of the bend is the same side as
	# the near stretch says, since the nearest stretch decides.
	var bent := PackedVector2Array([Vector2(-20, 0), Vector2(0, 0), Vector2(0, 20)])
	assert_eq(GeometryEdit.side_of(bent, Vector2(-10, 5)), GeometryEdit.side_of(bent, Vector2(-5, 10)),
		"inside the bend is one side")
	assert_true(GeometryEdit.side_of(bent, Vector2(-10, 5)) != GeometryEdit.side_of(bent, Vector2(-10, -5)),
		"and outside it the other")


func test_the_far_parts_are_those_across_the_divider_from_the_first() -> void:
	var parts := _two_parts()
	var divider := PackedVector2Array([Vector2(-20, 0), Vector2(20, 0)])
	assert_eq(GeometryEdit.far_parts(parts, divider), PackedInt32Array([1]),
		"the eastern part is across from the western first one")
	parts.reverse()
	assert_eq(GeometryEdit.far_parts(parts, divider), PackedInt32Array([1]),
		"whichever of them is first, the other is far")
	assert_eq(GeometryEdit.far_parts(parts, PackedVector2Array([Vector2(-20, 40), Vector2(20, 40)])),
		PackedInt32Array(), "a divider east of both leaves both near")


func test_a_divide_needs_two_parts_on_two_sides() -> void:
	var parts := _two_parts()
	assert_eq(GeometryEdit.divide_problem(parts, PackedVector2Array([Vector2(-20, 0), Vector2(20, 0)])), "")
	assert_eq(GeometryEdit.divide_problem(parts, PackedVector2Array([Vector2(-20, 40), Vector2(20, 40)])),
		"The cut leaves every part on one side.")
	assert_eq(GeometryEdit.divide_problem([parts[0]], PackedVector2Array([Vector2(-20, 0), Vector2(20, 0)])),
		"The cut runs outside the shape.")
	assert_eq(GeometryEdit.divide_problem(parts, PackedVector2Array([Vector2(-20, 0)])),
		"A cut needs a start and an end.")

### Simplifying a run


func test_a_straight_run_keeps_its_two_ends() -> void:
	var run := PackedVector2Array()
	for i in 20:
		run.append(Vector2(i * 5.0, 0.3 * (i % 2)))
	assert_eq(GeometryEdit.simplified(run, 1.0), PackedInt32Array([0, 19]),
		"a jitter under the tolerance is let go")
	assert_eq(GeometryEdit.simplified(run, 0.1), PackedInt32Array(range(20)),
		"and kept when the tolerance is under it")


func test_a_corner_is_kept_and_the_points_along_the_sides_are_not() -> void:
	var run := PackedVector2Array()
	for i in 11:
		run.append(Vector2(i * 10.0, 0.0))
	for i in range(1, 11):
		run.append(Vector2(100.0, i * 10.0))
	assert_eq(GeometryEdit.simplified(run, 2.0), PackedInt32Array([0, 10, 20]),
		"the two ends and the corner")


func test_short_runs_and_a_zero_tolerance() -> void:
	assert_eq(GeometryEdit.simplified(PackedVector2Array(), 1.0), PackedInt32Array())
	assert_eq(GeometryEdit.simplified(PackedVector2Array([Vector2(1, 1)]), 1.0), PackedInt32Array([0]))
	assert_eq(GeometryEdit.simplified(PackedVector2Array([Vector2(1, 1), Vector2(1, 1)]), 1.0),
		PackedInt32Array([0, 1]), "two points in one place are both kept")
	var bent := PackedVector2Array([Vector2(0, 0), Vector2(5, 1), Vector2(10, 0)])
	assert_eq(GeometryEdit.simplified(bent, 0.0), PackedInt32Array([0, 1, 2]),
		"at zero every point off the line is kept")
	assert_eq(GeometryEdit.simplified(bent, 1.0), PackedInt32Array([0, 2]),
		"a point exactly at the tolerance is let go")
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


func test_a_segment_with_a_hidden_end_is_not_offered() -> void:
	# A square with its third corner round the back: the two edges that meet
	# there are out, the other two are in, closed or not.
	var points := [Vector2(0, 0), Vector2(100, 0), null, Vector2(0, 100)]
	var got := GeometryEdit.nearest_visible_segment(points, Vector2(97, 50), true)
	assert_eq(got[0], 0, "three pixels from the hidden right hand edge, the bottom one is offered")
	assert_close(got[1], 50.0, 1e-4, "at its real distance")
	got = GeometryEdit.nearest_visible_segment(points, Vector2(3, 50), true)
	assert_eq(got[0], 3, "the closing edge is offered, both its ends being visible")
	assert_close(got[2], 0.5, 1e-4, "halfway along it")
	got = GeometryEdit.nearest_visible_segment(points, Vector2(3, 50), false)
	assert_eq(got[0], 0, "open, with no closing edge, the bottom edge is all that is left")
	var hidden := [null, null, null]
	assert_eq(GeometryEdit.nearest_visible_segment(hidden, Vector2(1, 1), true)[0], -1,
		"a ring wholly round the back offers nothing")
	var same := GeometryEdit.nearest_segment(PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)]), Vector2(97, 50), false)
	var visible := GeometryEdit.nearest_visible_segment([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)], Vector2(97, 50), false)
	assert_eq(visible, same, "with nothing hidden the two agree")


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
