extends RenderedCase

# The cratons of the sample files really are drawn, in their own colour, at the
# probe points documented in Tests/Data/README.md.


func test_the_red_triangle_is_drawn_where_it_is_hit_tested() -> void:
	await load_sample("triangle.middle-earth")
	await _check_probe(-3.0, 0.0, "red")
	await _check_probe(5.0, 40.0, "")


func test_three_cratons_are_drawn_in_their_own_colours() -> void:
	await load_sample("two_cratons.middle-earth")
	await _check_probe(-3.0, 0.0, "red")
	await _check_probe(30.0, 45.0, "blue")
	await _check_probe(-3.0, -60.0, "green")


func test_a_polyline_and_a_multipoint_are_drawn_in_their_own_colours() -> void:
	await load_sample("mixed_geometry.middle-earth")
	# The line runs along the meridian at 40 degrees east from (-25, 40) to
	# (25, 40), so it passes through (0, 40); the markers sit at (-30, -30)
	# and (30, -30).
	await _check_probe(-3.0, 0.0, "red")
	await _check_probe(0.0, 40.0, "blue")
	await _check_probe(-30.0, -30.0, "green")
	await _check_probe(30.0, -30.0, "green")


func test_the_earth_shows_beside_a_line_and_a_marker() -> void:
	await load_sample("mixed_geometry.middle-earth")
	# Both points are a few degrees off, well beyond the width they are drawn
	# with, and off the graticule, which is on multiples of 15 degrees.
	await _check_probe(3.0, 33.0, "")
	await _check_probe(-27.0, -33.0, "")


func test_an_empty_file_draws_no_craton() -> void:
	await load_sample("empty.middle-earth")
	await _check_probe(-3.0, 0.0, "")


# GP-0027: a filled polygon used to be drawn with a pale rim around every one of
# its triangles, so the fan ear clipping cut it into showed through the fill.
# The rim now follows the ring alone.
#
# The probe points are the midpoints of the edges the triangulation cut, read
# out of the same triangle_edges the shader is given, so the test asks about the
# exact places the seams used to be rather than a guess at where they were.
func test_a_polygon_is_filled_without_showing_its_triangles() -> void:
	await load_sample("craton.middle-earth")
	var feature := _first_feature()
	if feature == null:
		return
	# The tests share one application, and the ones before this turn the globe.
	# The craton is centred near (0, 0), so bring it back to face the camera:
	# away from there the surface is barely lit and its blue reads as dark
	# rather than as blue at all.
	await look_at_latlon(0.0, 0.0)

	var image := await capture()
	var probed := 0
	for midpoint in _cut_edge_midpoints(feature):
		# The graticule is drawn on multiples of 15 degrees and is pale too, so
		# a midpoint sitting on one says nothing about the fill.
		if _near_graticule(midpoint):
			continue
		var screen: Variant = app.planet_view.latlon_to_screen(midpoint.x, midpoint.y)
		if screen == null:
			continue
		var at: Vector2 = screen
		if at.x < 0.0 or at.y < 0.0 or at.x >= image.get_width() or at.y >= image.get_height():
			continue
		probed += 1
		var color := image.get_pixel(int(at.x), int(at.y))
		assert_eq(dominant_channel(color), "blue",
			"the middle of the cut at %s is fill, not a seam: %s" % [midpoint, color])

	assert_true(probed >= 8,
		"there were cut edges away from the graticule to probe, found %d" % probed)


# The midpoints, in world coordinates, of every edge ear clipping cut rather
# than took from the ring. A cut is shared by the two triangles either side of
# it, so each midpoint comes back twice; probing it twice costs nothing.
func _cut_edge_midpoints(feature: Feature) -> PackedVector2Array:
	var midpoints := PackedVector2Array()
	var bits := [Feature.EDGE_AB, Feature.EDGE_BC, Feature.EDGE_CA]
	var m := Feature.world_basis(app.features.root, feature, app.document.current_time)
	for t in range(feature.triangle_edges.size()):
		var corners := [
			feature.triangles[t * 3], feature.triangles[t * 3 + 1], feature.triangles[t * 3 + 2]]
		for e in range(3):
			if feature.triangle_edges[t] & bits[e]:
				continue
			var middle := Measure.along(corners[e], corners[(e + 1) % 3], 0.5)
			midpoints.append(Feature.apply_basis(PackedVector2Array([middle]), m)[0])
	return midpoints


# The graticule runs along every fifteenth degree of latitude and longitude.
func _near_graticule(point: Vector2) -> bool:
	for value in [point.x, point.y]:
		if absf(value - roundf(value / 15.0) * 15.0) < 1.5:
			return true
	return false


func _first_feature() -> Feature:
	var stack: Array[Feature] = [app.features.root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if not node.is_group:
			return node
		stack.append_array(node.children)
	fail("the sample holds no feature")
	return null


func _check_probe(lat: float, lon: float, expected: String) -> void:
	await look_at_latlon(lat, lon)
	var screen: Variant = view().latlon_to_screen(lat, lon)
	assert_true(screen != null, "lat/lon (%s, %s) must be visible" % [lat, lon])
	if screen == null:
		return
	var color := await probe(screen)
	assert_eq(dominant_channel(color), expected,
		"the pixel at lat/lon (%s, %s) is %s" % [lat, lon, color])
