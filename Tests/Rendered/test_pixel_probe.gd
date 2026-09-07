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


func test_an_empty_file_draws_no_craton() -> void:
	await load_sample("empty.middle-earth")
	await _check_probe(-3.0, 0.0, "")


func _check_probe(lat: float, lon: float, expected: String) -> void:
	await look_at_latlon(lat, lon)
	var screen: Variant = view().latlon_to_screen(lat, lon)
	assert_true(screen != null, "lat/lon (%s, %s) must be visible" % [lat, lon])
	if screen == null:
		return
	var color := await probe(screen)
	assert_eq(dominant_channel(color), expected,
		"the pixel at lat/lon (%s, %s) is %s" % [lat, lon, color])
