extends RenderedCase

# The cratons of the sample files really are drawn, in their own colour, at the
# probe points documented in Tests/Data/README.md.

# Zoomed in this far the pale rim a filled polygon carried before GP-0033, 0.001
# wide as a chord length, would be several pixels across.
const BOUNDARY_ZOOM := 20.0

# How many pixels either side of the middle of an edge are looked at. The globe
# is a tessellated mesh, so where a place lands on screen can be a few pixels
# off the analytic position at this zoom; the square is wide enough to hold the
# boundary anyway.
const BOUNDARY_REACH := 10

# How much green a pixel may carry beside a blue polygon on a red raster.
const GREEN_TOLERANCE := 0.1


func test_the_red_triangle_is_drawn_where_it_is_hit_tested() -> void:
	await load_sample("triangle.geotekt")
	await _check_probe(-3.0, 0.0, "red")
	await _check_probe(5.0, 40.0, "")


func test_three_cratons_are_drawn_in_their_own_colours() -> void:
	await load_sample("two_cratons.geotekt")
	await _check_probe(-3.0, 0.0, "red")
	await _check_probe(30.0, 45.0, "blue")
	await _check_probe(-3.0, -60.0, "green")


func test_a_polyline_and_a_multipoint_are_drawn_in_their_own_colours() -> void:
	await load_sample("mixed_geometry.geotekt")
	# The line runs along the meridian at 40 degrees east from (-25, 40) to
	# (25, 40), so it passes through (0, 40); the markers sit at (-30, -30)
	# and (30, -30).
	await _check_probe(-3.0, 0.0, "red")
	await _check_probe(0.0, 40.0, "blue")
	await _check_probe(-30.0, -30.0, "green")
	await _check_probe(30.0, -30.0, "green")


func test_the_earth_shows_beside_a_line_and_a_marker() -> void:
	await load_sample("mixed_geometry.geotekt")
	# Both points are a few degrees off, well beyond the width they are drawn
	# with, and off the grid, which is on multiples of 15 degrees.
	await _check_probe(3.0, 33.0, "")
	await _check_probe(-27.0, -33.0, "")


func test_an_empty_file_draws_no_craton() -> void:
	await load_sample("empty.middle-earth")
	await _check_probe(-3.0, 0.0, "")


# GP-0033: a filled polygon is one flat color right up to its boundary. It used
# to carry a pale rim there. The planet wears a flat red raster for the test,
# so around the middle of every edge of the ring every pixel is either the blue
# fill or the red beneath it, and both are there: a rim would be neither. The
# Earth itself is no use as the background, since its detail does not come out
# the same from one frame to the next.
func test_a_polygon_is_one_flat_color_up_to_its_boundary() -> void:
	await load_sample("craton.geotekt")
	var feature := _first_feature()
	if feature == null:
		return
	var ring := Feature.apply_basis(feature.rings[0],
		Feature.world_basis(app.features.root, feature, app.document.current_time))

	var red := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	view().planet.set_raster(ImageTexture.create_from_image(red), 1.0)
	view().set_zoom(BOUNDARY_ZOOM)
	var probed := 0
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var middle := Measure.along(a, b, 0.5)
		# The grid is drawn on multiples of 15 degrees and is pale too, so
		# an edge crossing one says nothing about the fill.
		if _near_grid(middle):
			continue
		await look_at_latlon(middle.x, middle.y)
		var centre: Variant = view().latlon_to_screen(middle.x, middle.y)
		if centre == null:
			continue
		var image := await capture()
		probed += 1
		var counts := {"blue": 0, "red": 0}
		var pale: Array[Color] = []
		for dy in range(-BOUNDARY_REACH, BOUNDARY_REACH + 1):
			for dx in range(-BOUNDARY_REACH, BOUNDARY_REACH + 1):
				var color := image.get_pixel(int(centre.x) + dx, int(centre.y) + dy)
				var channel := dominant_channel(color)
				if counts.has(channel):
					counts[channel] += 1
				# Neither the fill nor the raster has any green, and a pixel on
				# the boundary itself is a blend of the two, which has none
				# either. White, which the rim was, is all green.
				if color.g > GREEN_TOLERANCE:
					pale.append(color)
		assert_true(counts["blue"] > 0 and counts["red"] > 0,
			"the edge %s-%s is in the square: %s" % [a, b, counts])
		assert_true(pale.is_empty(),
			"beside the edge %s-%s no pixel is paler than the fill and the raster, %d are: %s"
				% [a, b, pale.size(), pale.slice(0, 4)])
	view().set_zoom(PlanetView.DEFAULT_ZOOM)
	view().planet.set_raster(null, 0.0)
	await frames(2)

	assert_true(probed >= 10,
		"there were ring edges away from the grid to probe, found %d" % probed)


# The grid runs along every fifteenth degree of latitude and longitude.
func _near_grid(point: Vector2) -> bool:
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
