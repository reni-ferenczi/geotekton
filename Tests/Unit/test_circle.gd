extends TestCase

# The two circle constructions in Logic/circle.gd: a circle from a
# centre and an angular radius, and the circle through three points. What is
# checked is the geometry itself, so the two are tested against each other as
# well: points sampled off one circle have to give that circle back.


# Centres away from the poles, on the equator and either side of it, so a
# construction that only worked near the origin cannot pass.
const CENTRES := [
	Vector2(0.0, 0.0),
	Vector2(35.0, -120.0),
	Vector2(-62.5, 47.25),
	Vector2(12.0, 179.0),
]


func test_every_vertex_sits_at_the_angular_radius_from_the_centre() -> void:
	for centre in CENTRES:
		for radius in [0.5, 15.0, 60.0, 90.0, 120.0]:
			var ring := Circle.vertices(centre, radius, 24)
			for vertex in ring:
				assert_close(Circle.radius_to(centre, vertex), radius, 1e-4,
					"a vertex of the circle at %s of radius %s" % [centre, radius])


func test_a_closed_circle_holds_one_vertex_per_segment() -> void:
	for segments in [3, 8, 36, 360]:
		var ring := Circle.vertices(Vector2(20.0, 30.0), 25.0, segments)
		assert_eq(ring.size(), segments,
			"a polygon of %d segments holds %d vertices" % [segments, segments])


# A polyline has one vertex more than it has segments, because it does not close
# on its own: without the repeat it would draw one segment short of the circle.
func test_an_open_circle_repeats_its_first_vertex_at_the_end() -> void:
	for segments in [3, 8, 36]:
		var line := Circle.vertices(Vector2(20.0, 30.0), 25.0, segments, false)
		assert_eq(line.size(), segments + 1,
			"a polyline of %d segments holds %d vertices" % [segments, segments + 1])
		assert_close(line[line.size() - 1], line[0], 1e-9,
			"the last vertex of an open circle is the first one again")


func test_the_segment_count_is_kept_inside_what_can_be_drawn() -> void:
	assert_eq(Circle.vertices(Vector2.ZERO, 10.0, 1).size(), Circle.MIN_SEGMENTS,
		"too few segments becomes the fewest a polygon can be drawn with")
	assert_eq(Circle.vertices(Vector2.ZERO, 10.0, 100000).size(), Circle.MAX_SEGMENTS,
		"too many becomes the most")


func test_the_first_vertex_sits_due_north_of_the_centre() -> void:
	var ring := Circle.vertices(Vector2(10.0, 40.0), 15.0, 12)
	assert_close(ring[0], Vector2(25.0, 40.0), 1e-4,
		"the circle starts at the point the radius north of its centre")


# The winding Feature.faces_outwards, Planet.hit_test and the geometry shader
# all require: counter-clockwise as seen from outside the sphere.
func test_a_circle_winds_the_way_a_polygon_has_to() -> void:
	for centre in CENTRES:
		var ring := Circle.vertices(centre, 20.0, 16)
		for i in range(ring.size()):
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			var c := ring[(i + 2) % ring.size()]
			assert_true(Feature.faces_outwards(a, b, c),
				"three consecutive vertices of the circle at %s face outwards" % centre)

		var feature := Feature.create_feature("Circle")
		feature.add_ring(ring, Feature.GeometryKind.POLYGON)
		assert_eq(feature.triangles.size(), (ring.size() - 2) * 3,
			"and the ring triangulates into one triangle per vertex less two")


# How closely the circle comes back depends on how large it is: the three points
# are pairs of 32-bit floats and the centre comes out of differences between
# them, so a circle keeps fewer digits. A degree across is the smallest
# tested and lands within a thousandth of a degree; see Circle.through.
func test_three_points_of_a_circle_give_that_circle_back() -> void:
	for entry in [[1.0, 2e-3], [20.0, 1e-4], [75.0, 1e-4]]:
		var radius: float = entry[0]
		var tolerance: float = entry[1]
		for centre in CENTRES:
			var ring := Circle.vertices(centre, radius, 12)
			var found := Circle.through(ring[0], ring[3], ring[7])
			assert_eq(found.size(), 2, "three points of a circle settle one circle")
			if found.size() != 2:
				continue
			assert_close(found[0], centre, tolerance,
				"the centre of the circle at %s of radius %s" % [centre, radius])
			assert_close(found[1], radius, tolerance,
				"the radius of the circle at %s of radius %s" % [centre, radius])


# Three points of one great circle are not a failure: the plane through them
# passes through the middle of the planet, and the circle it cuts has a radius
# of 90 degrees around either pole of that plane.
func test_three_points_of_a_great_circle_give_a_radius_of_ninety_degrees() -> void:
	var found := Circle.through(Vector2(0.0, 0.0), Vector2(0.0, 60.0), Vector2(0.0, 150.0))
	assert_eq(found.size(), 2, "the equator is a circle like any other")
	if found.size() != 2:
		return
	assert_close(found[1], 90.0, 1e-4, "a great circle has a radius of 90 degrees")
	assert_close(absf(found[0].x), 90.0, 1e-4, "and the equator's centre is a pole")


func test_two_points_that_have_come_together_settle_no_circle() -> void:
	var point := Vector2(10.0, 20.0)
	assert_eq(Circle.through(point, point, Vector2(30.0, 40.0)), [],
		"the same point twice names no circle")
	assert_eq(Circle.through(point, point, point), [],
		"and neither does one point three times")


func test_a_circle_round_a_pole_is_a_line_of_latitude() -> void:
	var ring := Circle.vertices(Vector2(90.0, 0.0), 30.0, 8)
	for vertex in ring:
		assert_close(vertex.x, 60.0, 1e-4,
			"every vertex of a circle 30 degrees from the north pole is at 60 north")
