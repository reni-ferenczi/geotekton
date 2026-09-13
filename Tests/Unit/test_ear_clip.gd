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


# Shoelace area in the (latitude, longitude) plane; the sign follows the winding.
func _signed_area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		total += a.x * b.y - b.x * a.y
	return total / 2.0
