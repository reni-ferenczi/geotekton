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
	await load_sample("triangle.middle-earth")
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
	await load_sample("triangle.middle-earth")
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
	await load_sample("triangle.middle-earth")
	await use_settings({"star_field": true})
	for colour: Color in BACKGROUNDS:
		await use_settings({"background_color": colour})
		var stars := await count_bright_pixels(colour, 0.05)
		assert_true(stars > 20, "stars show on %s: %d" % [colour, stars])
	await use_settings({"background_color": ViewSettings.DEFAULT_BACKGROUND})


# The stars are worked out from where they are rather than drawn at random, so
# the same view shows the same sky every time.
func test_the_star_field_is_the_same_every_frame() -> void:
	await load_sample("triangle.middle-earth")
	await use_settings({"star_field": true})
	var first := await capture()
	await frames(2)
	var second := await capture()
	assert_eq(count_differing(first, second), 0, "two captures of one view agree")


# The stars give their own light, so where the planet's light comes from does
# not change them.
func test_the_light_does_not_reach_the_stars() -> void:
	await load_sample("triangle.middle-earth")
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
	await load_sample("empty.middle-earth")
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
	await load_sample("empty.middle-earth")
	await look_at_latlon(0.0, 0.0)
	await use_settings({"grid_spacing": 15.0})
	var fifteen := await capture()
	await use_settings({"grid_spacing": 10.0})
	var ten := await capture()
	var moved := count_differing(fifteen, ten)
	assert_true(moved > 1000,
		"ten degrees apart draws the globe differently from fifteen: %d pixels" % moved)
	await use_settings({"grid_spacing": ViewSettings.DEFAULT_GRID_SPACING})


# With the light off to one side, the other side of what is in view is in
# shadow. Raising the ambient level is what puts light back on it.
func test_the_ambient_level_lifts_the_night_side() -> void:
	await load_sample("empty.middle-earth")
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


# Dragging with the Light tool puts the light where the drag ended, and the
# planet is brightest there.
func test_the_light_tool_drags_the_light_round_the_globe() -> void:
	await load_sample("empty.middle-earth")
	await look_at_latlon(0.0, 0.0)
	await use_settings({"light_direction": ViewSettings.DEFAULT_LIGHT, "ambient": 0.0})
	app.set_active_tool(Application.Tool.LIGHT)
	await frames(1)

	var target := Vector2(20.0, -40.0)
	await drag(view().latlon_to_screen(0.0, 0.0), view().latlon_to_screen(target.x, target.y))
	assert_close(app.document.view.light_direction, target, 0.01,
		"the light is where the drag ended")

	var image := await capture()
	var here: Vector2 = view().latlon_to_screen(target.x, target.y)
	var away: Vector2 = view().latlon_to_screen(-20.0, 40.0)
	assert_true(
		image.get_pixel(int(here.x), int(here.y)).get_luminance()
			> image.get_pixel(int(away.x), int(away.y)).get_luminance() + 0.1,
		"and the planet is brightest under it")

	app.set_active_tool(Application.Tool.MOVE)
	await use_settings({"light_direction": ViewSettings.DEFAULT_LIGHT})


# The light is dragged on the globe, so the tool is not offered on a map and
# gives way rather than staying armed over a sheet it cannot work on.
func test_the_light_tool_gives_way_to_a_map() -> void:
	await load_sample("empty.middle-earth")
	app.set_active_tool(Application.Tool.LIGHT)
	await frames(1)
	assert_eq(app.active_tool, Application.Tool.LIGHT, "the tool is armed on the globe")

	view().planet.show_map = true
	await frames(2)
	assert_eq(app.active_tool, Application.Tool.MOVE, "and gives way when a map takes over")
	assert_true(app.light_button.disabled, "the button is not offered either")

	view().planet.show_map = false
	await frames(2)
	assert_true(not app.light_button.disabled, "and is offered again on the globe")


### The planet color and the raster


# The planet with no raster is its own color. The pixel is lit and encoded on
# its way to the screen, so it is not the number the document holds; what it is
# held against is the same place drawn under an opaque image of that one color,
# which goes through the same light, and its dominant channel.
func test_with_no_raster_the_planet_is_its_own_color() -> void:
	await load_sample("empty.middle-earth")
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
	await load_sample("empty.middle-earth")
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
	await load_sample("empty.middle-earth")
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
	await load_sample("empty.middle-earth")
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
	await load_sample("empty.middle-earth")
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
	await load_sample("empty.middle-earth")
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
	await load_sample("empty.middle-earth")
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


# Press at one window pixel, move to another and release, which is what the
# Light tool reads as a drag.
func drag(from: Vector2, to: Vector2) -> void:
	Input.use_accumulated_input = false
	_motion(from)
	await _physics_frames(2)
	_button(true)
	await _physics_frames(2)
	_motion(to)
	await _physics_frames(2)
	_button(false)
	await _physics_frames(2)
	await frames(2)


func _motion(screen: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	motion.relative = screen - mouse
	mouse = screen
	Input.parse_input_event(motion)


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
