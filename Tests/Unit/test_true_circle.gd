extends TestCase

# GP-0100: a circle outline is drawn as the curve its center and radius
# describe, one Planet.Primitive.CIRCLE per ring, rather than as the segments of
# its ring. The ring stays on the feature for everything else. The shader reads
# the primitive the way _unpack() does here; Planet.circle_distance() is its
# counterpart of the shader's test.

# Coarse on purpose: twelve segments of a 30 degree circle leave the chord
# 0.85 degrees inside the circle halfway between two vertices.
const AXIS := Vector2(40.0, -60.0)
const RADIUS := 30.0
const SEGMENTS := 12


func _circle(polar := false, segments := SEGMENTS) -> Feature:
	var document := Document.new()
	var feature := Feature.create_feature("Circle")
	document.root.children.append(feature)
	document.record()
	assert_eq(document.set_feature_type(feature, FeatureType.CIRCLE), "", "a circle")
	assert_eq(document.set_circle(feature, AXIS, RADIUS, segments, polar), "", "drawn")
	return feature


func _collect(feature: Feature) -> Planet.Geometry:
	var root := Feature.create_group("Root")
	root.is_root = true
	root.children.append(feature)
	return Planet.collect_geometry(root)


# What the shader makes of the two texels: the axis, the radius in radians, the
# feature column and the kind.
func _unpack(texels: Array[Color]) -> Dictionary:
	return {
		"axis": Planet._latlon_to_unit(texels[0].r, texels[0].g),
		"radius": texels[0].b,
		"feature": int(texels[1].b + 0.5),
		"kind": int(texels[1].a + 0.5),
	}


func _unit(v: Vector2) -> Vector3:
	return Planet._latlon_to_unit(deg_to_rad(v.x), deg_to_rad(v.y))


# The middle of the chord between two vertices of the ring, carried out onto
# the sphere, and the point of the true circle beside it.
func _chord_middle(feature: Feature) -> Vector3:
	return (_unit(feature.rings[0][0]) + _unit(feature.rings[0][1])).normalized()


func _on_circle_beside(point: Vector3) -> Vector3:
	var axis := _unit(AXIS)
	var off_axis := (point - axis * axis.dot(point)).normalized()
	return axis * cos(deg_to_rad(RADIUS)) + off_axis * sin(deg_to_rad(RADIUS))


func test_a_circle_is_one_primitive_per_ring_and_keeps_its_ring() -> void:
	var feature := _circle()
	var geometry := _collect(feature)
	assert_eq(geometry.primitives.size(), 1, "one primitive")
	assert_eq(geometry.primitives[0]["kind"], Planet.Primitive.CIRCLE, "a CIRCLE")
	assert_close(geometry.primitives[0]["verts"][0], AXIS, 1e-9, "centered on the axis")
	assert_eq(feature.rings[0].size(), SEGMENTS + 1, "the ring is still there")
	assert_eq(Planet._primitive_count(feature), 1, "and counted as one")

	var polar := _circle(true)
	geometry = _collect(polar)
	assert_eq(geometry.primitives.size(), 2, "a polar circle is two")
	assert_close(geometry.primitives[1]["verts"][0], polar.circle_centers()[1], 1e-9,
		"the second around the antipode")
	assert_eq(Planet._primitive_count(polar), 2, "and counted as two")


func test_the_primitive_packs_its_center_and_radius() -> void:
	var geometry := _collect(_circle())
	var unpacked := _unpack(Planet._texels(geometry.primitives[0]))
	assert_eq(unpacked["kind"], int(Planet.Primitive.CIRCLE), "kind 4")
	assert_eq(unpacked["feature"], 0, "of the first feature")
	assert_close(unpacked["axis"], _unit(AXIS), 1e-6, "the axis")
	assert_close(unpacked["radius"], deg_to_rad(RADIUS), 1e-6, "the radius in radians")

	# The texels are 32-bit floats, as the shader gets them.
	var image := Image.create(1, 2, false, Image.FORMAT_RGBAF)
	var texels := Planet._texels(geometry.primitives[0])
	image.set_pixel(0, 0, texels[0])
	image.set_pixel(0, 1, texels[1])
	unpacked = _unpack([image.get_pixel(0, 0), image.get_pixel(0, 1)] as Array[Color])
	var chord := _chord_middle(_circle())
	var on := _on_circle_beside(chord)
	assert_close(Planet.circle_distance(unpacked["axis"], unpacked["radius"], on), 0.0, 1e-5,
		"a point of the circle is on it after the round trip")
	# The curve is most of a degree off the chord there: many pixels when zoomed in.
	var sagitta := rad_to_deg(Planet.circle_distance(unpacked["axis"], unpacked["radius"], chord))
	assert_true(sagitta > 0.8 and sagitta < 0.9,
		"the middle of a chord is 0.85 degrees inside the circle: %s" % sagitta)


# Six segments leave the chord 3.4 degrees inside, well past the click
# tolerance of a degree, so the curve and the chord cannot both be hits.
func test_a_click_on_the_curve_between_vertices_hits() -> void:
	var feature := _circle(false, 6)
	var geometry := _collect(feature)
	var on := Measure._to_latlon(_on_circle_beside(_chord_middle(feature)))
	var chord := Measure._to_latlon(_chord_middle(feature))
	assert_eq(Planet.hit_test(on.x, on.y, geometry), feature, "the curve is a hit")
	assert_eq(Planet.hit_test(chord.x, chord.y, geometry), null,
		"the chord 3.4 degrees inside is not")
	assert_eq(Planet.hit_test(AXIS.x, AXIS.y, geometry), null, "nor is the center")


func test_other_circles_keep_their_segments() -> void:
	# A filled circle from an older file is drawn from its triangles.
	var filled := Feature.create_feature("Filled")
	filled.add_ring(Circle.vertices(AXIS, RADIUS, SEGMENTS), Feature.GeometryKind.POLYGON)
	filled.feature_type = FeatureType.CIRCLE
	filled.rebuild_circle()
	assert_true(not filled.draws_true_circles(), "a filled circle is not an outline")
	assert_eq(_collect(filled).primitives[0]["kind"], Planet.Primitive.TRIANGLE, "triangles")

	# A ring too short to have been fitted is not the circle the defaults say.
	var short := Feature.create_feature("Short")
	short.add_ring(PackedVector2Array([Vector2(0, 0), Vector2(0, 10)]),
		Feature.GeometryKind.POLYLINE)
	short.feature_type = FeatureType.CIRCLE
	assert_true(not short.draws_true_circles(), "a ring that is not the parameters' ring")
	var geometry := _collect(short)
	assert_eq(geometry.primitives.size(), 1, "one segment")
	assert_eq(geometry.primitives[0]["kind"], Planet.Primitive.SEGMENT, "drawn as a segment")
