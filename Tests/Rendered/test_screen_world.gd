extends RenderedCase

# PlanetView.latlon_to_screen and PlanetView.screen_to_latlon against the real window.
# The runner checks that the window transform is the identity, so the screen
# coordinates these return are window pixels.
# Every test starts by pointing the globe somewhere known, the other rendered
# tests turn it around and the order of the files is not part of the contract.

# The camera sits 1.05 in front of a globe of radius 0.5, so the visible cap ends
# where the angle from the centre of the disc reaches acos(0.5 / 1.05), 61.55 degrees.
const VISIBLE_CAP_DEGREES: float = 61.55

# The round trip goes through floating point screen coordinates, nothing is rounded
# to whole pixels, so it comes back within a small fraction of a degree everywhere.
const EPS_DEGREES: float = 0.01

const KINDS := [
	MapProjection.Kind.RECTANGULAR,
	MapProjection.Kind.MERCATOR,
	MapProjection.Kind.MOLLWEIDE,
	MapProjection.Kind.ROBINSON,
	MapProjection.Kind.ORTHOGRAPHIC,
]


func test_the_centre_maps_to_the_centre_of_the_view() -> void:
	await look_at_latlon(0.0, 0.0)
	var screen: Variant = view().latlon_to_screen(0.0, 0.0)
	assert_true(screen != null, "lat/lon (0, 0) must be visible")
	if screen == null:
		return
	assert_close(screen, view().get_global_rect().get_center(), 1.0,
		"lat/lon (0, 0) sits at the centre of the view")
	assert_close(view().screen_to_latlon(screen), Vector2.ZERO, EPS_DEGREES,
		"the centre round trips")


func test_a_high_latitude_point_round_trips() -> void:
	# (60, -30) is behind the limb from the default view, so turn the globe half
	# way towards it. That also proves the mapping follows the globe rotation.
	await look_at_latlon(30.0, -15.0)
	_check_round_trip(60.0, -30.0)


func test_a_point_inside_the_visible_cap_round_trips() -> void:
	await look_at_latlon(0.0, 0.0)
	assert_true(55.0 < VISIBLE_CAP_DEGREES, "the probe must be inside the visible cap")
	_check_round_trip(0.0, 55.0)


func test_points_beyond_the_visible_cap_have_no_screen_position() -> void:
	await look_at_latlon(0.0, 0.0)
	for lon in [70.0, 90.0, 180.0]:
		assert_true(lon > VISIBLE_CAP_DEGREES, "the probe must be outside the visible cap")
		assert_eq(view().latlon_to_screen(0.0, lon), null,
			"lat/lon (0, %s) is on the far side" % lon)


func test_a_screen_point_off_the_globe_has_no_latlon() -> void:
	# The globe is a disc in the middle of the view, so its corner always misses.
	await look_at_latlon(0.0, 0.0)
	var corner: Vector2 = view().get_global_rect().position + Vector2(2.0, 2.0)
	assert_eq(view().screen_to_latlon(corner), null,
		"the corner of the view is not on the globe")


# The map goes through the same two functions as the globe, in every projection.
# The middle of the sheet is what the projection is centred on, a point on it
# round trips, and the corner of the view is off the sheet, since the whole
# planet is in view and there is room to spare around it.
func test_the_map_round_trips_in_every_projection() -> void:
	await look_at_latlon(0.0, 0.0)
	var planet: Planet = view().planet
	planet.show_map = true
	var corner: Vector2 = view().get_global_rect().position + Vector2(2.0, 2.0)
	for kind in KINDS:
		planet.projection = kind
		await frames(2)
		var name := MapProjection.name_of(kind)
		var centre: Variant = view().latlon_to_screen(0.0, 0.0)
		assert_true(centre != null, "the middle of the %s sheet is on screen" % name)
		if centre != null:
			assert_close(centre, view().get_global_rect().get_center(), 1.0,
				"the middle of the %s sheet sits at the middle of the view" % name)
		_check_round_trip(20.0, -40.0, name)
		assert_eq(view().screen_to_latlon(corner), null,
			"the corner of the view is off the %s sheet" % name)
	planet.show_map = false
	planet.projection = MapProjection.Kind.RECTANGULAR
	await frames(1)


# The far side of an orthographic map is not drawn, so a point on it has no
# place on the sheet, exactly as it has none on the globe.
func test_the_far_side_of_an_orthographic_map_has_no_screen_position() -> void:
	await look_at_latlon(0.0, 0.0)
	var planet: Planet = view().planet
	planet.show_map = true
	planet.projection = MapProjection.Kind.ORTHOGRAPHIC
	await frames(2)
	for lon in [100.0, 180.0, -100.0]:
		assert_eq(view().latlon_to_screen(0.0, lon), null,
			"lat/lon (0, %s) is behind an orthographic map" % lon)
	planet.show_map = false
	planet.projection = MapProjection.Kind.RECTANGULAR
	await frames(1)


func _check_round_trip(lat: float, lon: float, where: String = "the globe") -> void:
	var screen: Variant = view().latlon_to_screen(lat, lon)
	assert_true(screen != null, "lat/lon (%s, %s) must be visible on %s" % [lat, lon, where])
	if screen == null:
		return
	assert_true(view().get_global_rect().has_point(screen),
		"lat/lon (%s, %s) lands inside the view on %s" % [lat, lon, where])
	assert_close(view().screen_to_latlon(screen), Vector2(lat, lon), EPS_DEGREES,
		"lat/lon (%s, %s) round trips on %s" % [lat, lon, where])
