extends RenderedCase

# The cratons of the sample files really are drawn, in their own colour, at the
# probe points documented in Tests/Data/README.md.

# How wide the pale rim along the boundary of a filled polygon was, as a chord
# length, before GP-0033 made a polygon one flat colour. Everything closer to
# the boundary than half of it was drawn white.
const OLD_RIM_WIDTH := 0.001

# Zoomed in this far a pixel is a small fraction of that rim, so there are
# pixels inside the polygon well within where it used to be.
const BOUNDARY_ZOOM := 20.0


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


# GP-0033: a filled polygon is one flat colour right up to its boundary. It used
# to carry a pale rim there. At the middle of every edge of the ring, the pixel
# inside the polygon nearest the edge is probed: the place the rim was whitest.
func test_a_polygon_is_one_flat_colour_up_to_its_boundary() -> void:
	await load_sample("craton.middle-earth")
	var feature := _first_feature()
	if feature == null:
		return
	var ring := Feature.apply_basis(feature.rings[0],
		Feature.world_basis(app.features.root, feature, app.document.current_time))

	view().set_zoom(BOUNDARY_ZOOM)
	var probed := 0
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var middle := Measure.along(a, b, 0.5)
		# The graticule is drawn on multiples of 15 degrees and is pale too, so
		# an edge crossing one says nothing about the fill.
		if _near_graticule(middle):
			continue
		await look_at_latlon(middle.x, middle.y)
		var centre: Variant = view().latlon_to_screen(middle.x, middle.y)
		if centre == null:
			continue
		var pixel: Variant = _nearest_pixel_inside(feature, a, b, centre)
		if pixel == null:
			continue
		probed += 1
		var color := (await capture()).get_pixel(pixel.x, pixel.y)
		assert_eq(dominant_channel(color), "blue",
			"the fill beside the edge %s-%s is not a rim: %s" % [a, b, color])
	view().set_zoom(PlanetView.DEFAULT_ZOOM)
	await frames(2)

	assert_true(probed >= 10,
		"there were ring edges away from the graticule to probe, found %d" % probed)


# The window pixel near a screen position whose centre lies inside the feature
# and closest to the arc from a to b, when that is within where the old rim was
# drawn white. Null when no pixel is. Pixels closer than a hair are left out,
# where the graphics card and the hit test could disagree on the side.
func _nearest_pixel_inside(feature: Feature, a: Vector2, b: Vector2, centre: Vector2) -> Variant:
	var unit_a := Planet._latlon_to_unit(deg_to_rad(a.x), deg_to_rad(a.y))
	var unit_b := Planet._latlon_to_unit(deg_to_rad(b.x), deg_to_rad(b.y))
	var best: Variant = null
	var best_distance := OLD_RIM_WIDTH * 0.5
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var pixel := Vector2i(int(centre.x) + dx, int(centre.y) + dy)
			var place: Variant = view().screen_to_latlon(Vector2(pixel) + Vector2(0.5, 0.5))
			if place == null or Planet.hit_test(place.x, place.y, app.geometry) != feature:
				continue
			var p := Planet._latlon_to_unit(deg_to_rad(place.x), deg_to_rad(place.y))
			var distance := Planet.arc_distance(unit_a, unit_b, p)
			if distance > 2e-5 and distance < best_distance:
				best_distance = distance
				best = pixel
	return best


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
