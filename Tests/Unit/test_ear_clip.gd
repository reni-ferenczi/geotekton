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
# at mixed latitudes has the wrong one. Both are filled as a fan from the pole,
# so the polar cap is covered and the rest of the planet is not. The pole itself
# is the corner every fan triangle shares, which a hit test does not count as
# inside, so the probes sit a hair from it and off the cuts at the vertex
# longitudes.
func test_a_ring_round_the_pole_covers_the_pole() -> void:
	var level := PackedVector2Array()
	var mixed := PackedVector2Array()
	for i in range(12):
		level.append(Vector2(-82.0, -180.0 + 30.0 * i))
		mixed.append(Vector2(-80.0 if i % 2 == 0 else -83.0, -180.0 + 30.0 * i))
	for ring in [level, mixed]:
		var feature := _polygon(ring)
		assert_eq(feature.triangles.size(), ring.size() * 3,
			"a ring of %d vertices round the pole is a fan of as many triangles" % ring.size())
		var geometry := _geometry(feature)
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


# A repeated vertex on a ring round the pole makes no zero area fan triangle.
func test_a_repeated_vertex_round_the_pole_adds_no_triangle() -> void:
	var ring := PackedVector2Array()
	for i in range(12):
		ring.append(Vector2(-82.0, -180.0 + 30.0 * i))
	ring.append(ring[11])
	assert_eq(Feature.ear_clip(ring).size(), 12 * 3, "a fan of one triangle per distinct corner")


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
