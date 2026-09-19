extends RenderedCase

# The scene around the features against the real window: the background, the
# star field, the grid, the light, the planet's color and the image it wears.
#
# Every claim is a pixel, and the pixels are read out of one capture per frame
# rather than one per probe, since a capture copies the whole window back off
# the graphics card.

const RASTER := "res://Tests/Data/Rasters/quarters.png"

# A patch in the corner of the view, well clear of the planet in every view, and
# how far into the view it starts.
const CORNER := Vector2(3.0, 3.0)
const CORNER_PATCH := 120

# A saturated blue and a mid grey, the backgrounds the stars are checked on.
const BACKGROUNDS: Array[Color] = [Color(0.1, 0.2, 0.8), Color(0.5, 0.5, 0.5)]

# A place on the globe clear of the grid lines at their default spacing of 15
# degrees, and near enough the middle of the default view to face the light.
const PLANET_PROBE := Vector2(7.5, 7.5)

# The default grid spacing, and a latitude or longitude half way between lines.
const GRID_STEP := ViewSettings.DEFAULT_GRID_SPACING
const HALF_CELL := 7.5

# A spacing that divides neither 90 nor 180, which is where the pole and the
# date line the grid used to be counted from showed, and half a cell of it.
const ODD_STEP := 25.0
const ODD_HALF_CELL := 12.5

# The grid in a solid green for those probes: brighter than the planet, so
# assert_grid_line() can tell a line from the surface under it, and on another
# channel than the planet's blue, so a probe can say no line is there.
const ODD_GRID_COLOR := Color(0.0, 1.0, 0.0, 1.0)

# Where the old shader drew its parallels at that spacing. Both are half a cell
# from a meridian, so only a parallel could put a line there.
const NO_PARALLEL: Array[Vector2] = [Vector2(65.0, 12.5), Vector2(-60.0, 12.5)]

# Two planet colors far from each other and from the default.
const PLANET_COLORS: Array[Color] = [Color(0.8, 0.3, 0.1), Color(0.2, 0.7, 0.3)]

# How far a pixel of the planet may be from the same place under an image of
# its color: the two differ only by how the texture is sampled.
const PLANET_TOLERANCE := 0.02

# Places on the Earth image well away from each other: land and sea on either
# side of the Atlantic, the Sahara and the Gulf of Guinea, all in the default
# view and between grid lines. The ocean in the image is darker than the
# planet color, so not even the sea matches it.
const EARTH_PROBES: Array[Vector2] = [
	Vector2(22.5, 7.5), Vector2(7.5, -7.5), Vector2(-7.5, 22.5), Vector2(37.5, -22.5)]


# The star field is added onto the background, so the colour shows between the
# stars. The corner is read as the median of a patch rather than one pixel, so
# a star landing on the probe does not decide the answer.
func test_the_background_colour_reaches_the_corner_of_the_view() -> void:
	await load_sample("triangle.geotekt")
	await use_settings({"star_field": true})
	assert_close(await corner_colour(), Color.BLACK, 0.02, "the default background")

	for colour: Color in BACKGROUNDS:
		await use_settings({"background_color": colour})
		assert_close(await corner_colour(), colour, 0.02,
			"the colour the document asks for, behind the stars")
	await use_settings({"background_color": ViewSettings.DEFAULT_BACKGROUND})


# A star is one bright pixel on a dark ground, so what is counted is how many of
# them a patch of background holds rather than the colour at one place.
func test_the_star_field_can_be_turned_off() -> void:
	await load_sample("triangle.geotekt")
	await use_settings({"star_field": true})
	var with_stars := await count_bright_pixels()
	await use_settings({"star_field": false})
	var without := await count_bright_pixels()
	assert_true(with_stars > 20, "the star field puts stars in the corner: %d" % with_stars)
	assert_eq(without, 0, "and turning it off takes every one away")
	await use_settings({"star_field": true})


# The stars add their light to the background rather than replacing it, so they
# still stand out on a colour. On a light one the same star is a smaller step
# up, so the margin it has to clear is smaller too.
func test_the_stars_show_on_a_coloured_background() -> void:
	await load_sample("triangle.geotekt")
	await use_settings({"star_field": true})
	for colour: Color in BACKGROUNDS:
		await use_settings({"background_color": colour})
		var stars := await count_bright_pixels(colour, 0.05)
		assert_true(stars > 20, "stars show on %s: %d" % [colour, stars])
	await use_settings({"background_color": ViewSettings.DEFAULT_BACKGROUND})


# The stars are worked out from where they are rather than drawn at random, so
# the same view shows the same sky every time.
func test_the_star_field_is_the_same_every_frame() -> void:
	await load_sample("triangle.geotekt")
	await use_settings({"star_field": true})
	var first := await capture()
	await frames(2)
	var second := await capture()
	assert_eq(count_differing(first, second), 0, "two captures of one view agree")


# The stars give their own light, so where the planet's light comes from does
# not change them.
func test_the_light_does_not_reach_the_stars() -> void:
	await load_sample("triangle.geotekt")
	await use_settings({"star_field": true, "light_direction": ViewSettings.DEFAULT_LIGHT})
	var facing := await count_bright_pixels()
	await use_settings({"light_direction": Vector2(0.0, 150.0)})
	assert_eq(await count_bright_pixels(), facing, "a light from behind leaves the stars alone")
	await use_settings({"light_direction": ViewSettings.DEFAULT_LIGHT})


# The grid is drawn in the color the document asks for, on multiples of
# the spacing. At ninety degrees apart the lines are wide enough to probe
# without hunting for them: the equator is one, and (20, 20) is clear of both
# the parallels and the meridians, which at that spacing are the equator and the
# prime meridian.
func test_the_grid_is_drawn_where_and_how_the_document_says() -> void:
	await load_sample("empty.geotekt")
	await look_at_latlon(0.0, 0.0)
	await use_settings({
		"grid_spacing": 90.0,
		"grid_color": Color(1.0, 0.0, 0.0, 1.0),
	})
	var image := await capture()
	var on_line: Vector2 = view().latlon_to_screen(0.0, 0.0)
	var off_line: Vector2 = view().latlon_to_screen(20.0, 20.0)
	assert_eq(dominant_channel(image.get_pixel(int(on_line.x), int(on_line.y))), "red",
		"the equator is a line, in the colour the document asks for")
	assert_true(dominant_channel(image.get_pixel(int(off_line.x), int(off_line.y))) != "red",
		"and (20, 20) is clear of every line")
	await use_settings({
		"grid_spacing": ViewSettings.DEFAULT_GRID_SPACING,
		"grid_color": ViewSettings.DEFAULT_GRID_COLOR,
	})


# Changing the spacing redraws the lines somewhere else. Where each one lands is
# ViewSettings.grid_split()'s to say and is checked there; what is checked
# here is that the number reaches the shader at all.
func test_the_grid_spacing_moves_the_lines() -> void:
	await load_sample("empty.geotekt")
	await look_at_latlon(0.0, 0.0)
	await use_settings({"grid_spacing": 15.0})
	var fifteen := await capture()
	await use_settings({"grid_spacing": 10.0})
	var ten := await capture()
	var moved := count_differing(fifteen, ten)
	assert_true(moved > 1000,
		"ten degrees apart draws the globe differently from fifteen: %d pixels" % moved)
	await use_settings({"grid_spacing": ViewSettings.DEFAULT_GRID_SPACING})


# Every line of the default grid is on screen, on the map at zoom 1 where a
# line of a fraction of a degree is under a pixel, and on the globe. A row half
# way between two parallels crosses every meridian, a column half way between
# two meridians every parallel, and within a pixel of each crossing there is a
# pixel brighter than the planet half a cell away.
func test_every_grid_line_shows_on_the_rectangular_map() -> void:
	await load_sample("empty.geotekt")
	await clear_raster()
	await look_at_latlon(0.0, 0.0)
	view().planet.show_map = true
	view().planet.projection = MapProjection.Kind.RECTANGULAR
	await frames(2)
	var image := await capture()
	for k in range(1, 24):
		assert_grid_line(image, HALF_CELL, -180.0 + k * GRID_STEP, Vector2(0.0, GRID_STEP / 2.0))
	for k in range(1, 12):
		assert_grid_line(image, 90.0 - k * GRID_STEP, HALF_CELL, Vector2(GRID_STEP / 2.0, 0.0))
	view().planet.show_map = false
	await frames(2)


func test_every_meridian_in_front_shows_on_the_globe() -> void:
	await load_sample("empty.geotekt")
	await clear_raster()
	await look_at_latlon(0.0, 0.0)
	var image := await capture()
	var seen := 0
	for k in range(-5, 6):
		var lon := k * GRID_STEP
		# The camera is near enough that the limb is short of 90 degrees.
		if view().latlon_to_screen(HALF_CELL, lon) == null:
			continue
		seen += 1
		# The planet is compared on the side nearer the middle, which the light
		# reaches no less than the line.
		var inward := -signf(lon) * GRID_STEP / 2.0 if k != 0 else GRID_STEP / 2.0
		assert_grid_line(image, HALF_CELL, lon, Vector2(0.0, inward))
	assert_true(seen >= 9, "the front of the globe shows at least nine meridians: %d" % seen)


# Meridians converge on the poles. They fade out there instead of flooding the
# cap with the grid color, so near the pole the planet shows.
func test_the_globe_pole_is_not_flooded_by_the_grid() -> void:
	await load_sample("empty.geotekt")
	await clear_raster()
	await look_at_latlon(60.0, 0.0)
	await use_settings({"grid_color": Color(1.0, 0.0, 0.0, 1.0)})
	var image := await capture()
	for lon in [0.0, 45.0, -45.0, 90.0, -90.0, 180.0]:
		var near_pole: Vector2 = view().latlon_to_screen(89.5, lon)
		var pixel := image.get_pixel(int(near_pole.x), int(near_pole.y))
		assert_eq(dominant_channel(pixel), "blue",
			"(89.5, %s) is the planet color, not the grid color: %s" % [lon, pixel])
	await use_settings({"grid_color": ViewSettings.DEFAULT_GRID_COLOR})


# GP-0106: the lines are counted from the equator and the prime meridian, so a
# spacing that does not divide 90 still draws the equator and the same
# parallels on both hemispheres. The shader used to count from the north pole
# and the date line, which at 25 degrees put a parallel at 65 N and another at
# 60 S, and left out the equator and the prime meridian.
func test_the_grid_is_counted_from_the_equator_and_the_prime_meridian() -> void:
	await load_sample("empty.geotekt")
	await clear_raster()
	await look_at_latlon(0.0, 0.0)
	await use_settings({"grid_spacing": ODD_STEP, "grid_color": ODD_GRID_COLOR})

	assert_odd_grid_lines(await capture())
	# The limb of the globe is short of 62 degrees from the middle of the view,
	# so neither 65 N nor 60 S is drawn while it looks at (0, 0). Each is turned
	# to the front for its own probe.
	for place: Vector2 in NO_PARALLEL:
		await look_at_latlon(place.x, place.y)
		assert_no_grid_line(await capture(), place)

	await look_at_latlon(0.0, 0.0)
	view().planet.show_map = true
	view().planet.projection = MapProjection.Kind.RECTANGULAR
	await frames(2)
	var map := await capture()
	assert_odd_grid_lines(map)
	for place: Vector2 in NO_PARALLEL:
		assert_no_grid_line(map, place)
	view().planet.show_map = false
	await frames(2)

	await use_settings({
		"grid_spacing": ViewSettings.DEFAULT_GRID_SPACING,
		"grid_color": ViewSettings.DEFAULT_GRID_COLOR,
	})


# The equator, 25 N, 25 S, the prime meridian and 25 E are all drawn. A
# parallel is probed half a cell from a meridian and a meridian half a cell
# from a parallel, and each is held against the planet on the side away from
# the middle of the view, which the light reaches no more than the line does.
func assert_odd_grid_lines(image: Image) -> void:
	for lat: float in [0.0, ODD_STEP, -ODD_STEP]:
		var away := ODD_HALF_CELL if lat >= 0.0 else -ODD_HALF_CELL
		assert_grid_line(image, lat, ODD_HALF_CELL, Vector2(away, 0.0))
	for lon: float in [0.0, ODD_STEP]:
		assert_grid_line(image, ODD_HALF_CELL, lon, Vector2(0.0, ODD_HALF_CELL))


# Nothing is drawn at a place. The channels are held against each other rather
# than against a level, because how much light a place gets scales all three of
# them together, and a place this far from the middle of the globe gets little.
func assert_no_grid_line(image: Image, place: Vector2) -> void:
	var at = view().latlon_to_screen(place.x, place.y)
	assert_true(at != null, "(%s, %s) is drawn at all" % [place.x, place.y])
	if at == null:
		return
	var pixel := image.get_pixel(int(at.x), int(at.y))
	assert_true(pixel.b > pixel.g,
		"(%s, %s) shows the planet, not a grid line: %s" % [place.x, place.y, pixel])


# GP-0085: a polygon round the south pole at 82 S fills the bottom of the
# rectangular map from its scalloped top edge down to the pole, which the
# projection stretches across the whole sheet. The grid is drawn over the fill,
# so the meridians run through the band. The vertices sit half way between
# meridians, so the probes at their longitudes are clear of the grid.
func test_a_polygon_round_the_pole_is_a_band_with_the_grid_through_it() -> void:
	await load_sample("empty.geotekt")
	await clear_raster()
	var ring := PackedVector2Array()
	for i in range(12):
		ring.append(Vector2(-82.0, -172.5 + 30.0 * i))
	var polar := Feature.create_feature("Polar", Color(0.9, 0.1, 0.0))
	polar.add_ring(ring, Feature.GeometryKind.POLYGON)
	app.features.root.children.append(polar)
	app.refresh_geometry()
	app.features.feature_tree.select_node(polar)
	await look_at_latlon(0.0, 0.0)
	view().planet.show_map = true
	view().planet.projection = MapProjection.Kind.RECTANGULAR
	await frames(2)
	var image := await capture()

	for vertex in ring:
		for entry in [[-84.0, "red"], [-89.0, "red"], [-80.0, "blue"]]:
			var at: Vector2 = view().latlon_to_screen(entry[0], vertex.y)
			var pixel := image.get_pixel(int(at.x), int(at.y))
			assert_eq(dominant_channel(pixel), entry[1],
				"(%s, %s) is %s: %s" % [entry[0], vertex.y, entry[1], pixel])
	for k in range(1, 24):
		assert_grid_line(image, -86.0, -180.0 + k * GRID_STEP, Vector2(0.0, GRID_STEP / 2.0))

	app.features.feature_tree.select_root()
	view().planet.show_map = false
	await frames(2)

# Whether a pixel within one of where (lat, lon) lands on screen, along the
# row or column through it, is brighter than the planet at `offset` degrees
# away.
func assert_grid_line(image: Image, lat: float, lon: float, offset: Vector2) -> void:
	var at: Vector2 = view().latlon_to_screen(lat, lon)
	var bare: Vector2 = view().latlon_to_screen(lat + offset.x, lon + offset.y)
	var planet := image.get_pixel(int(bare.x), int(bare.y)).get_luminance()
	var step := Vector2(1.0, 0.0) if offset.y != 0.0 else Vector2(0.0, 1.0)
	var brightest := 0.0
	for i in range(-1, 2):
		var p := at + step * i
		brightest = maxf(brightest, image.get_pixel(int(p.x), int(p.y)).get_luminance())
	assert_true(brightest > planet,
		"the line through (%s, %s) shows: %.3f against the planet's %.3f"
			% [lat, lon, brightest, planet])


# With the light off to one side, the other side of what is in view is in
# shadow. Raising the ambient level is what puts light back on it.
func test_the_ambient_level_lifts_the_night_side() -> void:
	await load_sample("empty.geotekt")
	await look_at_latlon(0.0, 0.0)
	await use_settings({"light_direction": Vector2(0.0, 60.0), "ambient": 0.0})
	var night: Vector2 = view().latlon_to_screen(0.0, -55.0)
	var dark := await probe(night)
	assert_true(dark.get_luminance() < 0.02, "the night side is dark: %s" % dark)

	await use_settings({"ambient": 0.6})
	var lifted := await probe(night)
	assert_true(lifted.get_luminance() > dark.get_luminance() + 0.2,
		"and the ambient level lifts it: %s against %s" % [lifted, dark])
	await use_settings({"ambient": 0.0, "light_direction": ViewSettings.DEFAULT_LIGHT})


### The planet color and the raster


# The planet with no raster is its own color. The pixel is lit and encoded on
# its way to the screen, so it is not the number the document holds; what it is
# held against is the same place drawn under an opaque image of that one color,
# which goes through the same light, and its dominant channel.
func test_with_no_raster_the_planet_is_its_own_color() -> void:
	await load_sample("empty.geotekt")
	await look_at_latlon(0.0, 0.0)
	var here: Vector2 = view().latlon_to_screen(PLANET_PROBE.x, PLANET_PROBE.y)
	await use_settings({"raster_path": ""})
	await check_planet_colour(here, ViewSettings.DEFAULT_PLANET_COLOR)
	for colour: Color in PLANET_COLORS:
		await use_settings({"planet_color": colour})
		await check_planet_colour(here, colour)
	await clear_raster()


# The picker offers no alpha, and a color given with one anyway, as the
# automation port can, comes out opaque in the document and on the planet.
func test_a_planet_color_with_an_alpha_comes_back_opaque() -> void:
	await load_sample("empty.geotekt")
	await look_at_latlon(0.0, 0.0)
	await use_settings({"raster_path": ""})
	var here: Vector2 = view().latlon_to_screen(PLANET_PROBE.x, PLANET_PROBE.y)
	app.show_view_settings()
	var picker: ColorPickerButton = app.view_fields["planet_color"]
	assert_true(not picker.edit_alpha, "the picker offers no alpha")
	picker.color = Color(0.8, 0.3, 0.1, 0.2)
	app._on_view_field_changed()
	app.view_dialog.hide()
	await frames(2)
	assert_eq(app.document.view.planet_color, Color(0.8, 0.3, 0.1, 1.0),
		"the document holds the color opaque")
	assert_close(await probe(here), await flat_image_colour(here, Color(0.8, 0.3, 0.1)),
		PLANET_TOLERANCE, "and the planet shows it at full strength")
	await use_settings({"planet_color": ViewSettings.DEFAULT_PLANET_COLOR})
	await clear_raster()


# The Built in Earth button names the image that ships with the application, and
# the planet is no longer one flat color.
func test_the_built_in_earth_button_puts_the_earth_on_the_planet() -> void:
	await load_sample("empty.geotekt")
	await look_at_latlon(0.0, 0.0)
	await use_settings({"raster_path": ""})
	app.show_view_settings()
	var earth_button: Button = app.view_dialog.find_child("BuiltInEarth", true, false)
	assert_true(earth_button != null, "the dialog has the button")
	if earth_button == null:
		app.view_dialog.hide()
		return
	earth_button.pressed.emit()
	app.view_dialog.hide()
	await frames(2)
	assert_eq(app.document.view.raster_path, ViewSettings.BUILT_IN_EARTH,
		"the raster is the built in Earth")
	assert_eq(app.raster.error, "", "and it loaded")

	var image := await capture()
	for probe_at: Vector2 in EARTH_PROBES:
		var screen: Vector2 = view().latlon_to_screen(probe_at.x, probe_at.y)
		var pixel := image.get_pixel(int(screen.x), int(screen.y))
		var flat := await flat_image_colour(screen, ViewSettings.DEFAULT_PLANET_COLOR)
		assert_true(not _near(pixel, flat, PLANET_TOLERANCE),
			"%s is not the flat planet color: %s against %s" % [probe_at, pixel, flat])
	await clear_raster()


func test_an_image_is_drawn_on_the_planet_and_blended_at_half_opacity() -> void:
	await load_sample("empty.geotekt")
	await look_at_latlon(0.0, 0.0)
	var here: Vector2 = view().latlon_to_screen(30.0, -30.0)
	await use_settings({"raster_path": ""})
	var bare := await probe(here)

	await use_settings({"raster_path": raster_path()})
	assert_eq(app.raster.error, "", "the image loaded")
	var full := await probe(here)
	assert_eq(dominant_channel(full), "red", "the quarter of the image that lands there: %s" % full)

	await use_settings({"raster_opacity": 0.5})
	var half := await probe(here)
	assert_true(half.r < full.r and half.r > bare.r,
		"half opacity is between the image and the planet color: %s" % half)

	await use_settings({"raster_visible": false})
	assert_close(await probe(here), bare, 0.02, "hiding it brings the planet color back")
	await clear_raster()


# A document naming an image that is not there still opens: the planet shows
# its own color and the reason is there to be read.
func test_an_image_that_is_not_there_falls_back_to_the_planet_color() -> void:
	await load_sample("empty.geotekt")
	await look_at_latlon(0.0, 0.0)
	var here: Vector2 = view().latlon_to_screen(30.0, -30.0)
	await use_settings({"raster_path": ""})
	var bare := await probe(here)

	await use_settings({"raster_path": "C:/nowhere/missing.png"})
	assert_true(app.raster.error.contains("not there"),
		"the reason is recorded: %s" % app.raster.error)
	assert_close(await probe(here), bare, 0.02, "and the planet color is what is drawn")
	await clear_raster()


### The exported picture


# The projections whose sheet does not fill the rectangle it is exported in, so
# the corners of the picture are outside the planet.
const SHAPED_SHEETS: Array[MapProjection.Kind] = [
	MapProjection.Kind.MOLLWEIDE, MapProjection.Kind.ROBINSON,
	MapProjection.Kind.ORTHOGRAPHIC]

const EXPORT_WIDTH := 200


# A picture leaves out the stars and the background: the corners of a shaped
# sheet and of the globe come out clear, the planet opaque, and a sheet that
# fills the picture has no clear pixel at all. The star field is on, so a star
# drawn into a corner would show as alpha above zero.
func test_an_exported_picture_is_transparent_around_the_planet() -> void:
	await load_sample("empty.geotekt")
	await use_settings({"star_field": true, "background_color": BACKGROUNDS[1]})
	for kind: MapProjection.Kind in MapProjection.Kind.values():
		view().planet.show_map = true
		view().planet.projection = kind
		await frames(2)
		var size := PlanetView.export_size(kind, EXPORT_WIDTH)
		var image := await view().render_export(size, true)
		assert_eq(image.get_pixel(size.x / 2, size.y / 2).a8, 255,
			"the middle of projection %d is opaque" % kind)
		if kind in SHAPED_SHEETS:
			assert_eq(image.get_pixel(0, 0).a8, 0,
				"the corner of projection %d is clear" % kind)
		else:
			assert_eq(count_clear(image), 0,
				"projection %d fills its picture, with no clear pixel" % kind)
	view().planet.show_map = false
	view().planet.projection = MapProjection.Kind.RECTANGULAR
	await frames(2)

	var globe := await view().render_export(Vector2i(EXPORT_WIDTH, EXPORT_WIDTH), true)
	assert_eq(globe.get_pixel(0, 0).a8, 0, "the corner of the globe is clear")
	assert_eq(globe.get_pixel(EXPORT_WIDTH / 2, EXPORT_WIDTH / 2).a8, 255,
		"and the globe is opaque")
	await check_scene_restored()
	await use_settings({"background_color": ViewSettings.DEFAULT_BACKGROUND})


# A video frame keeps the background and the stars, since the encoder has no
# alpha to carry.
func test_an_opaque_export_keeps_the_background() -> void:
	await load_sample("empty.geotekt")
	await use_settings({"star_field": true, "background_color": BACKGROUNDS[1]})
	view().planet.show_map = true
	view().planet.projection = MapProjection.Kind.MOLLWEIDE
	await frames(2)
	var size := PlanetView.export_size(MapProjection.Kind.MOLLWEIDE, EXPORT_WIDTH)
	var image := await view().render_export(size, false)
	assert_eq(count_clear(image), 0, "no pixel of an opaque export is see-through")
	assert_true(image.get_pixel(0, 0).get_luminance() > 0.1,
		"and its corner is the grey background: %s" % image.get_pixel(0, 0))
	view().planet.show_map = false
	view().planet.projection = MapProjection.Kind.RECTANGULAR
	await frames(2)
	await check_scene_restored()
	await use_settings({"background_color": ViewSettings.DEFAULT_BACKGROUND})


### Helpers


# Change the document's view settings by the names ViewSettings holds them
# under, and let the frame catch up.
func use_settings(changes: Dictionary) -> void:
	for key in changes:
		app.document.view.set(str(key), changes[key])
	app.document.view_edited()
	app.apply_view_settings()
	await frames(2)


func clear_raster() -> void:
	await use_settings({
		"planet_color": ViewSettings.DEFAULT_PLANET_COLOR,
		"raster_path": "",
		"raster_opacity": ViewSettings.DEFAULT_RASTER_OPACITY,
		"raster_visible": true,
	})


func check_planet_colour(screen: Vector2, colour: Color) -> void:
	var pixel := await probe(screen)
	assert_close(pixel, await flat_image_colour(screen, colour), PLANET_TOLERANCE,
		"the planet is %s where no raster covers it" % colour)
	assert_eq(dominant_channel(pixel), dominant_channel(colour), "and looks it: %s" % pixel)


# The pixel at a place with the planet wearing an opaque image of one color,
# which is what the planet color is drawn as. The document's own raster is put
# back afterwards.
func flat_image_colour(screen: Vector2, colour: Color) -> Color:
	var flat := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	flat.fill(colour)
	view().planet.set_raster(ImageTexture.create_from_image(flat), 1.0)
	await frames(2)
	var pixel := await probe(screen)
	app.apply_view_settings()
	await frames(2)
	return pixel


func _near(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance 		and absf(a.b - b.b) <= tolerance


func raster_path() -> String:
	return ProjectSettings.globalize_path(RASTER)


func corner() -> Vector2:
	return view().get_global_rect().position + CORNER


# How many pixels of the view two captures disagree about, ignoring differences
# too small to be anything but rounding.
func count_differing(a: Image, b: Image) -> int:
	var rect := view().get_global_rect()
	var count := 0
	for x in range(int(rect.position.x), int(rect.end.x), 2):
		for y in range(int(rect.position.y), int(rect.end.y), 2):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			if maxf(maxf(absf(first.r - second.r), absf(first.g - second.g)),
					absf(first.b - second.b)) > 0.03:
				count += 1
	return count


# How many pixels of a patch of background are brighter than the empty sky by
# more than a margin, in the corner of the view where no part of the planet
# reaches.
func count_bright_pixels(sky := Color.BLACK, margin := 0.1) -> int:
	var image := await capture()
	var origin := corner()
	var count := 0
	for x in range(int(origin.x), int(origin.x) + CORNER_PATCH):
		for y in range(int(origin.y), int(origin.y) + CORNER_PATCH):
			if image.get_pixel(x, y).get_luminance() > sky.get_luminance() + margin:
				count += 1
	return count


# The colour most of the corner patch has: the median of each channel.
func corner_colour() -> Color:
	var image := await capture()
	var origin := corner()
	var channels: Array[PackedFloat32Array] = [
		PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for x in range(int(origin.x), int(origin.x) + CORNER_PATCH):
		for y in range(int(origin.y), int(origin.y) + CORNER_PATCH):
			var pixel := image.get_pixel(x, y)
			channels[0].append(pixel.r)
			channels[1].append(pixel.g)
			channels[2].append(pixel.b)
	for channel in channels:
		channel.sort()
	var middle := channels[0].size() / 2
	return Color(channels[0][middle], channels[1][middle], channels[2][middle])


# How many pixels of an image are not fully opaque.
func count_clear(image: Image) -> int:
	var clear := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a8 < 255:
				clear += 1
	return clear


# An export puts the window's own view back: the viewport draws opaque again,
# over the background color and with the stars the document asks for.
func check_scene_restored() -> void:
	assert_true(not view().viewport.transparent_bg, "the view is opaque again")
	assert_true(view().planet.background.visible, "the star field is back")
	assert_eq(view().world_environment.environment.background_mode, Environment.BG_COLOR,
		"and so is the background color")
	assert_close(await corner_colour(), BACKGROUNDS[1], 0.02,
		"which the window shows in the corner")
