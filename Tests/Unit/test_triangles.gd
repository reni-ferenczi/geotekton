extends TestCase

# Feature.rebuild_triangles derives the drawn triangles from the stored rings.
# Only a polygon has any; a polyline and a multipoint are drawn from their
# vertices, so their triangle list stays empty.

static var QUAD := PackedVector2Array([Vector2(0, 0), Vector2(0, 30), Vector2(30, 30), Vector2(30, 0)])
static var L_SHAPE := PackedVector2Array([
	Vector2(0, 0), Vector2(0, 30), Vector2(10, 30),
	Vector2(10, 10), Vector2(30, 10), Vector2(30, 0),
])
static var FAR_AWAY := PackedVector2Array([Vector2(-40, -40), Vector2(-40, -20), Vector2(-20, -20)])


func test_a_ring_becomes_two_triangles_fewer_than_its_vertices() -> void:
	for ring in [QUAD, L_SHAPE]:
		var feature := _polygon([ring])
		assert_eq(feature.triangles.size(), (ring.size() - 2) * 3,
			"a ring of %d vertices covers %d triangles" % [ring.size(), ring.size() - 2])


func test_every_derived_triangle_faces_outwards() -> void:
	# The rule the shader and Planet.hit_test both rely on. The ring is given
	# clockwise here, the opposite of what the triangles must come out as.
	var reversed := PackedVector2Array()
	for i in range(L_SHAPE.size() - 1, -1, -1):
		reversed.append(L_SHAPE[i])

	for ring in [L_SHAPE, reversed]:
		var feature := _polygon([ring])
		for i in range(0, feature.triangles.size() - 2, 3):
			assert_true(_is_front_facing(
				feature.triangles[i], feature.triangles[i + 1], feature.triangles[i + 2]),
				"triangle %d of the ring %s faces inwards" % [i / 3, ring])


func test_a_concave_ring_triangulates_without_overlap() -> void:
	var feature := _polygon([L_SHAPE])
	for i in range(0, feature.triangles.size() - 2, 3):
		var a := feature.triangles[i]
		var b := feature.triangles[i + 1]
		var c := feature.triangles[i + 2]
		for v in L_SHAPE:
			if v == a or v == b or v == c:
				continue
			assert_true(not Feature.point_in_triangle(v, a, b, c),
				"triangle %d of the L shape covers the unrelated vertex %s" % [i / 3, v])


func test_several_rings_are_triangulated_one_by_one() -> void:
	var feature := _polygon([QUAD, FAR_AWAY])
	assert_eq(feature.triangles.size(), (2 + 1) * 3, "two rings, three triangles between them")
	# The rings stay separate: no triangle mixes vertices of both.
	for i in range(0, feature.triangles.size() - 2, 3):
		var from_quad := 0
		for j in range(3):
			if feature.triangles[i + j] in QUAD:
				from_quad += 1
		assert_true(from_quad == 0 or from_quad == 3,
			"triangle %d joins vertices of two different rings" % [i / 3])


func test_the_other_kinds_have_no_triangles() -> void:
	for kind in [Feature.GeometryKind.POLYLINE, Feature.GeometryKind.MULTIPOINT]:
		var feature := Feature.create_feature("Line")
		feature.add_ring(QUAD, kind)
		assert_eq(feature.triangles.size(), 0, "%s has no triangles" % Feature.KIND_NAMES[kind])


func test_a_clone_carries_the_triangles_over() -> void:
	var feature := _polygon([L_SHAPE])
	assert_eq(feature.clone().triangles, feature.triangles, "the clone is drawn the same way")


func _polygon(rings: Array) -> Feature:
	var feature := Feature.create_feature("Polygon")
	for ring in rings:
		feature.add_ring(ring, Feature.GeometryKind.POLYGON)
	return feature


# The rule from Feature.faces_outwards: the triangle normal must point
# away from the centre of the sphere.
func _is_front_facing(a: Vector2, b: Vector2, c: Vector2) -> bool:
	var pa := Feature._latlon_to_xyz_s(a)
	var pb := Feature._latlon_to_xyz_s(b)
	var pc := Feature._latlon_to_xyz_s(c)
	return (pb - pa).cross(pc - pa).dot((pa + pb + pc) / 3.0) >= 0.0
