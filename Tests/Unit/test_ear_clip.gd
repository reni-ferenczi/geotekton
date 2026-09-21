extends TestCase

# Feature.ear_clip triangulates a polygon given in the (latitude, longitude)
# plane and returns a flat triangle list, 3 vertices per triangle.

# A convex quad and an L shape, both wound the same way.
static var QUAD := PackedVector2Array([Vector2(0, 0), Vector2(0, 30), Vector2(30, 30), Vector2(30, 0)])
static var L_SHAPE := PackedVector2Array([
	Vector2(0, 0), Vector2(0, 30), Vector2(10, 30),
	Vector2(10, 10), Vector2(30, 10), Vector2(30, 0),
])


func test_convex_quad_yields_two_triangles() -> void:
	var result := Feature.ear_clip(QUAD)
	assert_eq(result.size(), 6, "a quad becomes 2 triangles")

	var seen := PackedVector2Array()
	for v in result:
		if not v in seen:
			seen.append(v)
	assert_eq(seen.size(), QUAD.size(), "no vertex is invented")
	for v in QUAD:
		assert_true(v in seen, "input vertex %s is missing from the triangulation" % v)


func test_concave_polygon_yields_four_triangles() -> void:
	var result := Feature.ear_clip(L_SHAPE)
	assert_eq(result.size(), 12, "an L shape of 6 vertices becomes 4 triangles")

	var winding := signf(_signed_area(L_SHAPE))
	for i in range(0, result.size() - 2, 3):
		var a := result[i]
		var b := result[i + 1]
		var c := result[i + 2]
		var area := _signed_area(PackedVector2Array([a, b, c]))
		assert_true(signf(area) == winding,
			"triangle %d has area %s, which contradicts the polygon winding %s" % [i / 3, area, winding])
		for v in L_SHAPE:
			if v == a or v == b or v == c:
				continue
			assert_true(not Feature.point_in_triangle(v, a, b, c),
				"triangle %d covers the unrelated vertex %s" % [i / 3, v])


func test_degenerate_input_yields_nothing() -> void:
	assert_eq(Feature.ear_clip(PackedVector2Array()).size(), 0)
	assert_eq(Feature.ear_clip(PackedVector2Array([Vector2(0, 0)])).size(), 0)
	assert_eq(Feature.ear_clip(PackedVector2Array([Vector2(0, 0), Vector2(10, 10)])).size(), 0)


func test_triangulation_preserves_the_signed_area() -> void:
	for polygon in [QUAD, L_SHAPE]:
		var result := Feature.ear_clip(polygon)
		var total := 0.0
		for i in range(0, result.size() - 2, 3):
			total += _signed_area(PackedVector2Array([result[i], result[i + 1], result[i + 2]]))
		assert_close(total, _signed_area(polygon), 1e-6, "area of the triangulated polygon")



# A ring round the south pole at one latitude has no area in the plane, and one
# at mixed latitudes has the wrong one. Projected about the pole both are
# plain polygons round the origin, so the polar cap is covered, pole included,
# and the rest of the planet is not.
func test_a_ring_round_the_pole_covers_the_pole() -> void:
	var level := PackedVector2Array()
	var mixed := PackedVector2Array()
	for i in range(12):
		level.append(Vector2(-82.0, -180.0 + 30.0 * i))
		mixed.append(Vector2(-80.0 if i % 2 == 0 else -83.0, -180.0 + 30.0 * i))
	for ring in [level, mixed]:
		var feature := _polygon(ring)
		assert_eq(feature.triangles.size(), (ring.size() - 2) * 3,
			"a ring of %d vertices round the pole is clipped like any other" % ring.size())
		var geometry := _geometry(feature)
		assert_eq(Planet.hit_test(-90.0, 0.0, geometry), feature, "the pole itself is inside")
		for lon in [-170.0, -45.0, 10.0, 100.0]:
			assert_eq(Planet.hit_test(-89.999, lon, geometry), feature, "the pole at %s is inside" % lon)
			assert_eq(Planet.hit_test(-85.0, lon, geometry), feature, "85 S at %s is inside" % lon)
			assert_eq(Planet.hit_test(-75.0, lon, geometry), null, "75 S at %s is outside" % lon)
		assert_eq(Planet.hit_test(89.999, 0.0, geometry), null, "the north pole is outside")


# The polygon of the Documents/FillBugRepro.geotekt report: its last vertex was
# put down twice by a double click, and the fill stopped short of it. The
# repeated vertex is a corner the clipping cannot get past, so it is left out,
# and the triangles cover every distinct corner of the ring.
func test_a_repeated_vertex_does_not_lose_its_corner() -> void:
	var ring := PackedVector2Array([
		Vector2(35.5755, 9.1832), Vector2(27.7471, -5.7835), Vector2(15.1366, 7.6085),
		Vector2(24.9287, 18.8818), Vector2(32.5129, 15.9223), Vector2(32.5129, 15.9223),
	])
	var result := Feature.ear_clip(ring)
	assert_eq(result.size(), 9, "five distinct corners become 3 triangles")
	for v in ring:
		assert_true(v in result, "corner %s is covered" % v)
	assert_close(_area_of(result), _signed_area(ring), 1e-6, "area of the filled polygon")

	var indices := Feature.ear_clip_indices(ring)
	assert_true(not 5 in indices, "the repeated vertex is not a corner of any triangle")


# GPlates closes a polygon by repeating its first vertex at the end, and a
# vertex may be repeated in the middle of a ring as well. Neither repeat is a
# corner.
func test_repeats_anywhere_in_the_ring_are_skipped() -> void:
	var closed := QUAD.duplicate()
	closed.append(QUAD[0])
	assert_eq(Feature.ear_clip(closed).size(), 6, "a quad closed by its first vertex is 2 triangles")
	assert_eq(Array(Feature.distinct_corners(closed)), [0, 1, 2, 3], "the closing vertex is no corner")

	var stutter := PackedVector2Array([QUAD[0], QUAD[1], QUAD[1], QUAD[1], QUAD[2], QUAD[3]])
	assert_eq(Feature.ear_clip(stutter).size(), 6, "a quad with a vertex three times is 2 triangles")
	assert_eq(Array(Feature.distinct_corners(stutter)), [0, 1, 4, 5])
	assert_close(_area_of(Feature.ear_clip(stutter)), _signed_area(QUAD), 1e-6)

	var one_place := PackedVector2Array([QUAD[0], QUAD[0], QUAD[0]])
	assert_eq(Feature.ear_clip(one_place).size(), 0, "three vertices in one place are no polygon")
	var two_places := PackedVector2Array([QUAD[0], QUAD[1], QUAD[0]])
	assert_eq(Feature.ear_clip(two_places).size(), 0, "nor a ring that goes there and back")


# A repeated vertex on a ring round the pole makes no zero area triangle.
func test_a_repeated_vertex_round_the_pole_adds_no_triangle() -> void:
	var ring := PackedVector2Array()
	for i in range(12):
		ring.append(Vector2(-82.0, -180.0 + 30.0 * i))
	ring.append(ring[11])
	assert_eq(Feature.ear_clip(ring).size(), 10 * 3, "two triangles fewer than distinct corners")


func test_a_quad_across_the_date_line_is_filled_across_it() -> void:
	var quad := PackedVector2Array([Vector2(5, 175), Vector2(5, -175), Vector2(-5, -175), Vector2(-5, 175)])
	var indices := Feature.ear_clip_indices(quad)
	assert_eq(indices.size(), 6, "the quad becomes 2 triangles")
	var feature := _polygon(quad)
	var geometry := _geometry(feature)
	for point in [Vector2(0, 180), Vector2(0, -179), Vector2(4, 178)]:
		assert_eq(Planet.hit_test(point.x, point.y, geometry), feature, "%s is inside" % point)
	assert_eq(Planet.hit_test(0, 0, geometry), null, "the far side of the planet is outside")


func _polygon(ring: PackedVector2Array) -> Feature:
	var feature := Feature.create_feature("Polygon")
	feature.add_ring(ring, Feature.GeometryKind.POLYGON)
	return feature


func _geometry(feature: Feature) -> Planet.Geometry:
	var root := Feature.create_group("Planet")
	root.is_root = true
	root.children.append(feature)
	return Planet.collect_geometry(root)

# The signed area of a triangle list, which is that of the polygon it fills.
func _area_of(triangles: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(0, triangles.size() - 2, 3):
		total += _signed_area(PackedVector2Array([triangles[i], triangles[i + 1], triangles[i + 2]]))
	return total


# Shoelace area in the (latitude, longitude) plane; the sign follows the winding.
func _signed_area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		total += a.x * b.y - b.x * a.y
	return total / 2.0


### Filling on the sphere
#
# The shader fills each triangle as a spherical one, its edges great circles,
# so what matters is that the triangles cover the spherical polygon once: no
# point of it left out and no point covered twice, and nothing outside it
# filled. The reference for "inside" is a gnomonic projection about the probe
# itself, under which every great circle is a straight line, so a planar test
# at the origin is exact for any polygon within the hemisphere round the probe.


# Whether the point is inside the spherical polygon the ring outlines.
func _inside_on_sphere(ring: PackedVector2Array, point: Vector2) -> bool:
	var n := Feature._latlon_to_xyz_s(point)
	var e1 := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := n.cross(e1)
	var plane := PackedVector2Array()
	for vertex in ring:
		var v := Feature._latlon_to_xyz_s(vertex)
		var depth := v.dot(n)
		if depth <= 1e-6:
			return false
		plane.append(Vector2(v.dot(e1) / depth, v.dot(e2) / depth))
	return Geometry2D.is_point_in_polygon(Vector2.ZERO, plane)


# How many of the feature's triangles cover the point on the sphere, by the
# same half plane test the shader and the hit test use: [with the edges
# counted in, with them left out]. A point on the cut between two triangles
# is in both by the first count and in neither by the second.
func _covered_by(feature: Feature, point: Vector2) -> Array[int]:
	var p := Feature._latlon_to_xyz_s(point)
	var closed := 0
	var open := 0
	for i in range(0, feature.triangles.size() - 2, 3):
		var a := Feature._latlon_to_xyz_s(feature.triangles[i])
		var b := Feature._latlon_to_xyz_s(feature.triangles[i + 1])
		var c := Feature._latlon_to_xyz_s(feature.triangles[i + 2])
		var least := minf(a.cross(b).normalized().dot(p),
			minf(b.cross(c).normalized().dot(p), c.cross(a).normalized().dot(p)))
		if least > 1e-6:
			open += 1
		if least > -1e-6:
			closed += 1
	return [closed, open]


# Probe a grid of points over the given latitudes and longitudes: inside the
# spherical polygon each is covered exactly once, outside not at all. A point
# is a gap when no triangle covers it even with the edges counted in, and an
# overlap when two cover it with the edges left out, so a point on the cut
# between two triangles is neither. Points within a small angle of the ring's
# own edge are skipped, since the reference and the fill may round
# differently there.
func _check_fill(ring: PackedVector2Array, lats: Array, lons: Array, what: String) -> void:
	var feature := _polygon(ring)
	var gaps := 0
	var overlaps := 0
	var spills := 0
	var probed := 0
	for lat in lats:
		for lon in lons:
			var point := Vector2(lat, lon)
			if _near_an_edge(ring, point):
				continue
			probed += 1
			var covered := _covered_by(feature, point)
			if _inside_on_sphere(ring, point):
				if covered[0] == 0:
					gaps += 1
				elif covered[1] > 1:
					overlaps += 1
			elif covered[1] > 0:
				spills += 1
	assert_true(probed > 20, "%s: enough points probed (%d)" % [what, probed])
	assert_eq(gaps, 0, "%s: points inside left unfilled" % what)
	assert_eq(overlaps, 0, "%s: points inside filled twice" % what)
	assert_eq(spills, 0, "%s: points outside filled" % what)


# Whether the point is within a small angle of an edge of the ring.
func _near_an_edge(ring: PackedVector2Array, point: Vector2) -> bool:
	var p := Feature._latlon_to_xyz_s(point)
	for i in ring.size():
		var a := Feature._latlon_to_xyz_s(ring[i])
		var b := Feature._latlon_to_xyz_s(ring[(i + 1) % ring.size()])
		if Planet.arc_distance(a, b, p) < 0.004:
			return true
	return false


func _range(from: float, to: float, step: float) -> Array:
	var result := []
	var value := from
	while value <= to + 1e-9:
		result.append(value)
		value += step
	return result


# A polygon beside the pole, not round it: several vertices along 70 N and
# along 88 N between 60 W and 60 E. In the latitude and longitude plane it is
# a rectangle; on the sphere its edges bow towards the pole.
func test_a_polygon_beside_the_pole_is_filled_once() -> void:
	var ring := PackedVector2Array()
	for lon in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		ring.append(Vector2(70.0, lon))
	for lon in [60.0, 30.0, 0.0, -30.0, -60.0]:
		ring.append(Vector2(88.0, lon))
	_check_fill(ring, _range(60.0, 89.5, 1.0), _range(-90.0, 90.0, 5.0), "beside the pole")


# A ring round the pole with a bay in it that widens inside its mouth, the
# way a hand drawn Antarctica has one: the lips over the bay cannot be seen
# from the pole, so a fan from the pole fills the bay under them.
func test_a_ring_round_the_pole_with_a_bay_is_filled_once() -> void:
	var ring := PackedVector2Array()
	for i in range(12):
		var lon := -180.0 + 30.0 * i
		ring.append(Vector2(-70.0, lon))
		if i == 3:
			ring.append(Vector2(-70.0, -80.0))
			ring.append(Vector2(-74.0, -88.0))
			ring.append(Vector2(-82.0, -88.0))
			ring.append(Vector2(-82.0, -55.0))
			ring.append(Vector2(-74.0, -55.0))
			ring.append(Vector2(-70.0, -75.0))
	_check_fill(ring, _range(-89.5, -60.0, 1.0), _range(-180.0, 175.0, 2.5), "round the pole with a bay")


# The polygons of the existing tests still fill once when checked on the
# sphere rather than in the plane.
func test_the_plane_polygons_fill_once_on_the_sphere() -> void:
	_check_fill(QUAD, _range(-5.0, 35.0, 1.0), _range(-5.0, 35.0, 1.0), "the quad")
	_check_fill(L_SHAPE, _range(-5.0, 35.0, 1.0), _range(-5.0, 35.0, 1.0), "the L shape")
