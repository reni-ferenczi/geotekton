extends TestCase

# The craton sample is the one fixture shaped like something real: a ring of
# twenty-one vertices with a bay cut into its east coast, a narrow neck joining
# a northern lobe, and a pair of vertices half a degree apart. Every other
# polygon in Tests/Data is a triangle or a quad on whole degrees.
#
# What is checked here is that the shape keeps the properties it was built for.
# A sample that quietly became convex, or lost its neck, would go on passing the
# probe checks in test_sample_files.gd while testing much less than it looks.
# See GP-0026 and Tests/Data/README.md.

const SAMPLE := "res://Tests/Data/craton.middle-earth"

# How many vertices make it worth calling an outline rather than a shape.
const ENOUGH_VERTICES := 12


func test_the_outline_has_enough_vertices_to_be_an_outline() -> void:
	var ring := _ring()
	assert_true(ring.size() >= ENOUGH_VERTICES,
		"the outline has %d vertices, wanted at least %d" % [ring.size(), ENOUGH_VERTICES])


func test_the_outline_is_concave() -> void:
	var ring := _ring()
	var reflex := 0
	for i in range(ring.size()):
		if _turn(ring, i) < 0.0:
			reflex += 1
	assert_true(reflex >= 4,
		"the outline turns back on itself at %d vertices, wanted at least 4" % reflex)


func test_the_outline_does_not_cross_itself() -> void:
	var ring := _ring()
	var size := ring.size()
	for i in range(size):
		for j in range(i + 1, size):
			if j == i or (j + 1) % size == i or (i + 1) % size == j:
				continue
			assert_eq(Geometry2D.segment_intersects_segment(
				ring[i], ring[(i + 1) % size], ring[j], ring[(j + 1) % size]), null,
				"edges %d and %d do not cross" % [i, j])


func test_the_outline_keeps_its_close_pair_and_its_long_edges() -> void:
	var ring := _ring()
	var shortest := INF
	var longest := 0.0
	for i in range(ring.size()):
		var length := ring[i].distance_to(ring[(i + 1) % ring.size()])
		shortest = minf(shortest, length)
		longest = maxf(longest, length)
	assert_true(shortest < 1.0,
		"two vertices are under a degree apart, the shortest edge is %.2f" % shortest)
	assert_true(longest / shortest > 10.0,
		"and the longest edge is %.0f times the shortest, wanted more than 10"
			% (longest / shortest))


func test_the_outline_keeps_its_narrow_neck() -> void:
	# The closest two parts of the boundary come that are not neighbours. A
	# corridor that narrow is what makes ear clipping and the polygon split
	# work for their living.
	var ring := _ring()
	var size := ring.size()
	var narrowest := INF
	for i in range(size):
		for j in range(size):
			if absi(i - j) <= 2 or absi(i - j) >= size - 2:
				continue
			narrowest = minf(narrowest, Geometry2D.get_closest_point_to_segment(
				ring[i], ring[j], ring[(j + 1) % size]).distance_to(ring[i]))
	assert_true(narrowest < 6.0,
		"the boundary comes within %.2f degrees of itself, wanted under 6" % narrowest)


func test_the_outline_triangulates_into_one_triangle_per_vertex_less_two() -> void:
	var feature := _feature()
	var ring := _ring()
	assert_eq(feature.triangles.size(), (ring.size() - 2) * 3,
		"a ring of %d gives %d triangles" % [ring.size(), ring.size() - 2])


func test_the_triangles_cover_the_outline_exactly_once() -> void:
	# Ear clipping that overlapped itself, or left a hole, would show as a
	# triangle area that does not match the area of the ring.
	var feature := _feature()
	var ring := _ring()
	var covered := 0.0
	for i in range(0, feature.triangles.size() - 2, 3):
		covered += absf((feature.triangles[i + 1] - feature.triangles[i]).cross(
			feature.triangles[i + 2] - feature.triangles[i])) * 0.5

	var enclosed := 0.0
	for i in range(ring.size()):
		enclosed += ring[i].cross(ring[(i + 1) % ring.size()])
	enclosed = absf(enclosed) * 0.5

	assert_close(covered, enclosed, enclosed * 1e-4,
		"the triangles cover the ring and no more")


func test_the_bounding_cap_is_worth_having() -> void:
	# The cap added in GP-0007 is only worth measuring on a feature that covers
	# an area. This one spans about fifty degrees, so its cap should be a good
	# deal smaller than the hemisphere a cap of -1 stands for.
	var root := _root()
	if root == null:
		return
	var geometry := Planet.collect_geometry(root)
	assert_eq(geometry.features.size(), 1, "the sample holds one feature")
	assert_true(geometry.cap_cosines[0] > 0.5,
		"the cap is tighter than sixty degrees, its cosine is %.3f"
			% geometry.cap_cosines[0])

	for vertex in _ring():
		var unit := Planet._latlon_to_unit(deg_to_rad(vertex.x), deg_to_rad(vertex.y))
		assert_true(unit.dot(geometry.cap_centres[0]) >= geometry.cap_cosines[0],
			"and still holds the vertex at %s" % vertex)


func test_the_bay_is_outside_the_shape_and_the_neck_inside() -> void:
	# The two places the shape was built to have. Both are checked through the
	# real hit test, which works on the sphere, rather than in the flat
	# latitude and longitude plane the outline was drawn in.
	var root := _root()
	if root == null:
		return
	var geometry := Planet.collect_geometry(root)
	assert_eq(Planet.hit_test(2, 19, geometry), null,
		"the bay is cut out of the shape, so a point in it hits nothing")
	assert_true(Planet.hit_test(13, 6, geometry) != null,
		"the neck is part of the shape, so a point in it hits the feature")
	assert_true(Planet.hit_test(19, 4, geometry) != null,
		"and so is the lobe the neck leads to")


### Helpers


func _root() -> Feature:
	var document := Document.new()
	var error := document.load_from_file(ProjectSettings.globalize_path(SAMPLE))
	if not error.is_empty():
		fail(error)
		return null
	return document.root


func _feature() -> Feature:
	var root := _root()
	if root == null:
		return null
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if not node.is_group:
			return node
		stack.append_array(node.children)
	fail("the sample holds no feature")
	return null


func _ring() -> PackedVector2Array:
	var feature := _feature()
	if feature == null or feature.rings.is_empty():
		return PackedVector2Array()
	return feature.rings[0]


# Which way the outline turns at one vertex. Negative is a turn back on itself,
# given the counter-clockwise winding the samples are written in.
func _turn(ring: PackedVector2Array, i: int) -> float:
	var before := ring[(i - 1 + ring.size()) % ring.size()]
	var at := ring[i]
	var after := ring[(i + 1) % ring.size()]
	return (at - before).cross(after - at)
