extends RenderedCase

# The map in each of its five projections, against the real window: that a
# feature is drawn where the projection puts it, that a click there picks it,
# that a place the projection does not draw shows the sky instead, and that the
# zoom and the camera controls do what they say.
#
# Where a feature is on screen comes from PlanetView.latlon_to_screen, which
# goes through MapProjection.forward; the pixel there comes from the shader,
# which goes through the inverse in GLSL. A probe that finds the colour is the
# two of them agreeing, which is the whole point of keeping both.

const KINDS := [
	MapProjection.Kind.RECTANGULAR,
	MapProjection.Kind.MERCATOR,
	MapProjection.Kind.MOLLWEIDE,
	MapProjection.Kind.ROBINSON,
	MapProjection.Kind.ORTHOGRAPHIC,
]

# The middle of the red triangle of triangle.geotekt, and a point well
# clear of it. Both are away from the grid, which is drawn on multiples of
# fifteen degrees.
const RED_TRIANGLE := Vector2(-3.0, 0.0)
const BARE_PLANET := Vector2(-3.0, 47.0)


func test_a_craton_is_drawn_where_every_projection_puts_it() -> void:
	await load_sample("triangle.geotekt")
	await show_map()
	for kind in KINDS:
		var name := await use_projection(kind)
		var screen: Variant = view().latlon_to_screen(RED_TRIANGLE.x, RED_TRIANGLE.y)
		assert_true(screen != null, "the red triangle is on the %s sheet" % name)
		if screen == null:
			continue
		assert_eq(dominant_channel(await probe(screen)), "red",
			"the red triangle is drawn at its %s position" % name)
	await show_globe()


func test_clicking_a_craton_selects_it_in_every_projection() -> void:
	await load_sample("triangle.geotekt")
	await show_map()
	for kind in KINDS:
		var name := await use_projection(kind)
		app.features.feature_tree.select_node(app.document.root)
		await frames(1)
		var screen: Variant = view().latlon_to_screen(RED_TRIANGLE.x, RED_TRIANGLE.y)
		if screen == null:
			fail("the red triangle is on the %s sheet" % name)
			continue
		await click(screen)
		var selected: Feature = app.features.feature_tree.get_selected_node()
		assert_eq("" if selected == null else selected.title, "Red Triangle",
			"clicking the red triangle on the %s sheet selects it" % name)
	await show_globe()


# A pixel the projection does not cover shows what is behind the sheet, which is
# the star field. The corner of the view is outside every projection's outline
# while the whole planet is in view.
func test_the_sky_shows_through_where_a_projection_draws_nothing() -> void:
	await load_sample("triangle.geotekt")
	await show_map()
	var corner: Vector2 = view().get_global_rect().position + Vector2(3.0, 3.0)
	for kind in KINDS:
		var name := await use_projection(kind)
		var color := await probe(corner)
		assert_true(color.r < 0.3 and color.g < 0.3 and color.b < 0.3,
			"the corner of the %s view is sky, not planet: %s" % [name, color])
	await show_globe()


# What a projection does not draw is not clickable either, and what it does draw
# comes back as the point it was asked for.
func test_the_pointer_is_off_the_planet_outside_a_projection() -> void:
	await load_sample("triangle.geotekt")
	await show_map()
	var corner: Vector2 = view().get_global_rect().position + Vector2(3.0, 3.0)
	for kind in KINDS:
		var name := await use_projection(kind)
		assert_eq(view().screen_to_latlon(corner), null,
			"the corner of the %s view is off the planet" % name)
		var screen: Variant = view().latlon_to_screen(BARE_PLANET.x, BARE_PLANET.y)
		if screen != null:
			assert_close(view().screen_to_latlon(screen), BARE_PLANET, 0.05,
				"a point of the %s sheet says which place it shows" % name)
	await show_globe()


func test_the_zoom_buttons_move_by_the_documented_step() -> void:
	await load_sample("triangle.geotekt")
	assert_eq(view().zoom, PlanetView.DEFAULT_ZOOM, "a fresh view is not zoomed in")
	view().zoom_in()
	assert_close(view().zoom, PlanetView.DEFAULT_ZOOM * PlanetView.ZOOM_STEP, 1e-6,
		"zooming in multiplies by the step")
	view().zoom_in()
	view().zoom_out()
	assert_close(view().zoom, PlanetView.DEFAULT_ZOOM * PlanetView.ZOOM_STEP, 1e-6,
		"zooming out divides by it again")
	view().set_zoom(PlanetView.DEFAULT_ZOOM)
	assert_eq(view().zoom, PlanetView.DEFAULT_ZOOM, "the default zoom is the whole planet")

	view().set_zoom(6.5)
	assert_close(view().zoom, 6.5, 1e-6, "a zoom set explicitly is the zoom")
	view().set_zoom(PlanetView.MAX_ZOOM * 10.0)
	assert_eq(view().zoom, PlanetView.MAX_ZOOM, "a zoom past the end stops at the end")
	view().set_zoom(0.0)
	assert_eq(view().zoom, PlanetView.MIN_ZOOM, "and one before the start at the start")
	view().set_zoom(PlanetView.DEFAULT_ZOOM)


# Zooming in narrows the field of view, so the same stretch of the planet covers
# more of the window. The globe is measured across its own equator, where the
# projection cannot be blamed for the change.
func test_zooming_in_makes_the_planet_larger() -> void:
	await load_sample("triangle.geotekt")
	await look_at_latlon(0.0, 0.0)
	var near: Variant = view().latlon_to_screen(0.0, -20.0)
	var far: Variant = view().latlon_to_screen(0.0, 20.0)
	assert_true(near != null and far != null, "both ends of the span are in view")
	if near == null or far == null:
		return
	var span: float = (far as Vector2).distance_to(near as Vector2)

	view().set_zoom(2.0)
	await frames(2)
	var zoomed_near: Variant = view().latlon_to_screen(0.0, -20.0)
	var zoomed_far: Variant = view().latlon_to_screen(0.0, 20.0)
	assert_true(zoomed_near != null and zoomed_far != null, "and still in view zoomed in")
	if zoomed_near != null and zoomed_far != null:
		assert_true((zoomed_far as Vector2).distance_to(zoomed_near as Vector2) > span * 1.5,
			"twenty degrees either side of the middle covers much more of the window")
	view().set_zoom(PlanetView.DEFAULT_ZOOM)
	await frames(1)


# Turning the view clockwise and back leaves it where it started, and the turn
# is what carries a point round the middle of the view.
func test_turning_the_view_and_turning_it_back() -> void:
	await load_sample("triangle.geotekt")
	await look_at_latlon(0.0, 0.0)
	var upright: Variant = view().latlon_to_screen(30.0, 0.0)
	assert_true(upright != null, "the point above the middle is in view")

	view().planet.angle = 90.0
	await frames(2)
	var turned: Variant = view().latlon_to_screen(30.0, 0.0)
	assert_true(turned != null, "and still in view once the camera has turned")
	if upright != null and turned != null:
		var centre := view().get_global_rect().get_center()
		assert_close(
			(turned as Vector2).distance_to(centre),
			(upright as Vector2).distance_to(centre), 1.0,
			"turning the view moves the point round the middle, not away from it")
		assert_true((turned as Vector2).distance_to(upright as Vector2) > 10.0,
			"and it really did move")

	view().planet.angle = 0.0
	await frames(2)
	assert_close(view().latlon_to_screen(30.0, 0.0), upright, 1.0,
		"turning back puts it where it was")


# The camera reset puts the view back to the middle of the planet, the right way
# up, whatever the three fields were set to.
func test_the_camera_reset_puts_every_field_back() -> void:
	await load_sample("triangle.geotekt")
	view().planet.lat = 35.0
	view().planet.lon = -70.0
	view().planet.angle = 40.0
	await frames(1)
	view().reset_camera()
	await frames(1)
	assert_eq(view().planet.lat, 0.0, "the latitude is back at the equator")
	assert_eq(view().planet.lon, 0.0, "the longitude at the prime meridian")
	assert_eq(view().planet.angle, 0.0, "and the view is the right way up")


func show_map() -> void:
	view().planet.show_map = true
	await frames(2)


func show_globe() -> void:
	view().planet.show_map = false
	view().planet.projection = MapProjection.Kind.RECTANGULAR
	await frames(2)


# Switch the map to one projection and say what it is called, for the messages.
func use_projection(kind: MapProjection.Kind) -> String:
	view().planet.projection = kind
	await frames(2)
	return MapProjection.name_of(kind)
