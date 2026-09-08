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


### Which edges came from the ring
#
# GP-0027: the pale rim of a filled polygon follows the boundary of the shape,
# not the edges ear clipping cut it along, so a triangle in the middle of a
# large polygon carries no marked edge at all. The rule is the same one the
# triangulation knows and used to throw away: an edge is on the boundary when
# its two vertices are neighbours in the ring.


func test_a_triangle_has_three_boundary_edges() -> void:
	var feature := _polygon(PackedVector2Array([
		Vector2(-10, -10), Vector2(10, 0), Vector2(-10, 10)]))
	assert_eq(feature.triangle_edges.size(), 1, "one triangle")
	assert_eq(feature.triangle_edges[0],
		Feature.EDGE_AB | Feature.EDGE_BC | Feature.EDGE_CA,
		"every edge of it is part of the ring")


func test_a_quad_marks_five_of_its_six_edges() -> void:
	# Two triangles, four ring edges between them, and the cut they share
	# counted once on each side.
	var feature := _polygon(PackedVector2Array([
		Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)]))
	assert_eq(feature.triangle_edges.size(), 2, "two triangles")
	var marked := 0
	for edges in feature.triangle_edges:
		for bit in [Feature.EDGE_AB, Feature.EDGE_BC, Feature.EDGE_CA]:
			if edges & bit:
				marked += 1
	assert_eq(marked, 4, "the four edges of the quad are marked and the cut is not")


func test_every_marked_edge_is_a_ring_edge_and_every_ring_edge_is_marked() -> void:
	# The craton sample, which is the one shape with enough triangles for the
	# question to mean anything: 21 vertices, 19 triangles, 21 ring edges.
	var document := Document.new()
	var error := document.load_from_file(
		ProjectSettings.globalize_path("res://Tests/Data/craton.middle-earth"))
	if not assert_loaded(error):
		return
	var feature := _first_feature(document.root)
	if feature == null:
		return

	var ring: PackedVector2Array = feature.rings[0]
	var wanted := {}
	for i in range(ring.size()):
		wanted[_key(ring[i], ring[(i + 1) % ring.size()])] = true

	var found := {}
	var triangles := feature.triangles
	for t in range(feature.triangle_edges.size()):
		var edges := feature.triangle_edges[t]
		var corners := [triangles[t * 3], triangles[t * 3 + 1], triangles[t * 3 + 2]]
		var bits := [Feature.EDGE_AB, Feature.EDGE_BC, Feature.EDGE_CA]
		for e in range(3):
			if not (edges & bits[e]):
				continue
			var key := _key(corners[e], corners[(e + 1) % 3])
			assert_true(wanted.has(key), "the marked edge %s is a ring edge" % key)
			found[key] = true

	assert_eq(found.size(), wanted.size(),
		"every one of the %d ring edges is marked, found %d" % [wanted.size(), found.size()])


func test_most_of_a_large_polygon_is_drawn_without_a_rim() -> void:
	# What the whole change is for. Before it every one of the craton's 19
	# triangles drew a rim on all three of its edges, 57 in all; now only the 21
	# that lie on the ring do, so two thirds of the lines are gone.
	var document := Document.new()
	if not assert_loaded(document.load_from_file(
			ProjectSettings.globalize_path("res://Tests/Data/craton.middle-earth"))):
		return
	var feature := _first_feature(document.root)
	if feature == null:
		return

	var marked := 0
	for edges in feature.triangle_edges:
		for bit in [Feature.EDGE_AB, Feature.EDGE_BC, Feature.EDGE_CA]:
			if edges & bit:
				marked += 1
	var all_edges := feature.triangle_edges.size() * 3
	assert_eq(marked, feature.rings[0].size(),
		"one marked edge per ring edge")
	assert_true(marked * 2 < all_edges,
		"which is under half of the %d edges the triangles have, not %d" % [all_edges, marked])


func _polygon(ring: PackedVector2Array) -> Feature:
	var feature := Feature.create_feature("Shape")
	feature.add_ring(ring, Feature.GeometryKind.POLYGON)
	return feature


func _first_feature(root: Feature) -> Feature:
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if not node.is_group:
			return node
		stack.append_array(node.children)
	fail("the sample holds no feature")
	return null


func assert_loaded(error: String) -> bool:
	if not error.is_empty():
		fail(error)
		return false
	return true


# An edge as a key that does not depend on which way round it is given.
func _key(a: Vector2, b: Vector2) -> String:
	var first := a
	var second := b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		first = b
		second = a
	return "%.4f,%.4f-%.4f,%.4f" % [first.x, first.y, second.x, second.y]
