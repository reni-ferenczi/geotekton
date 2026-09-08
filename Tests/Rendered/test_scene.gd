extends RenderedCase

# The scene around the features against the real window: the background, the
# star field, the graticule, the light and the image the planet wears.
#
# Every claim is a pixel, and the pixels are read out of one capture per frame
# rather than one per probe, since a capture copies the whole window back off
# the graphics card.

const BACKDROP := "res://Tests/Data/Backdrops/quarters.png"

# A patch in the corner of the view, well clear of the planet in every view, and
# how far into the view it starts.
const CORNER := Vector2(3.0, 3.0)
const CORNER_PATCH := 120


func test_the_background_colour_reaches_the_corner_of_the_view() -> void:
	await load_sample("triangle.middle-earth")
	await use_settings({"star_field": false})
	assert_close(await probe(corner()), Color.BLACK, 0.02, "the default background")

	await use_settings({"background_color": Color(0.2, 0.0, 0.4)})
	assert_close(await probe(corner()), Color(0.2, 0.0, 0.4), 0.02,
		"the colour the document asks for")
	await use_settings({"background_color": ViewSettings.DEFAULT_BACKGROUND, "star_field": true})


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


# The graticule is drawn in the colour the document asks for, on multiples of
# the spacing. At ninety degrees apart the lines are wide enough to probe
# without hunting for them: the equator is one, and (20, 20) is clear of both
# the parallels and the meridians, which at that spacing are the equator and the
# prime meridian.
func test_the_graticule_is_drawn_where_and_how_the_document_says() -> void:
	await load_sample("empty.middle-earth")
	await look_at_latlon(0.0, 0.0)
	await use_settings({
		"graticule_spacing": 90.0,
		"graticule_color": Color(1.0, 0.0, 0.0, 1.0),
	})
	var image := await capture()
	var on_line: Vector2 = view().latlon_to_screen(0.0, 0.0)
	var off_line: Vector2 = view().latlon_to_screen(20.0, 20.0)
	assert_eq(dominant_channel(image.get_pixel(int(on_line.x), int(on_line.y))), "red",
		"the equator is a line, in the colour the document asks for")
	assert_true(dominant_channel(image.get_pixel(int(off_line.x), int(off_line.y))) != "red",
		"and (20, 20) is clear of every line")
	await use_settings({
		"graticule_spacing": ViewSettings.DEFAULT_GRATICULE_SPACING,
		"graticule_color": ViewSettings.DEFAULT_GRATICULE_COLOR,
	})


# Changing the spacing redraws the lines somewhere else. Where each one lands is
# ViewSettings.graticule_split()'s to say and is checked there; what is checked
# here is that the number reaches the shader at all.
func test_the_graticule_spacing_moves_the_lines() -> void:
	await load_sample("empty.middle-earth")
	await look_at_latlon(0.0, 0.0)
	await use_settings({"graticule_spacing": 15.0})
	var fifteen := await capture()
	await use_settings({"graticule_spacing": 10.0})
	var ten := await capture()
	var moved := count_differing(fifteen, ten)
	assert_true(moved > 1000,
		"ten degrees apart draws the globe differently from fifteen: %d pixels" % moved)
	await use_settings({"graticule_spacing": ViewSettings.DEFAULT_GRATICULE_SPACING})


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


### The backdrop image


func test_an_image_is_drawn_on_the_planet_and_blended_at_half_opacity() -> void:
	await load_sample("empty.middle-earth")
	await look_at_latlon(0.0, 0.0)
	var here: Vector2 = view().latlon_to_screen(30.0, -30.0)
	var earth := await probe(here)

	await use_settings({"backdrop_path": backdrop_path()})
	assert_eq(app.backdrop.error, "", "the image loaded")
	var full := await probe(here)
	assert_eq(dominant_channel(full), "red", "the quarter of the image that lands there: %s" % full)

	await use_settings({"backdrop_opacity": 0.5})
	var half := await probe(here)
	assert_true(half.r < full.r and half.r > earth.r,
		"half opacity is between the image and the Earth: %s" % half)

	await use_settings({"backdrop_visible": false})
	assert_close(await probe(here), earth, 0.02, "hiding it brings the Earth back")
	await clear_backdrop()


# A document naming an image that is not there still opens: the planet keeps the
# built in Earth and the reason is there to be read.
func test_an_image_that_is_not_there_falls_back_to_the_earth() -> void:
	await load_sample("empty.middle-earth")
	await look_at_latlon(0.0, 0.0)
	var here: Vector2 = view().latlon_to_screen(30.0, -30.0)
	var earth := await probe(here)

	await use_settings({"backdrop_path": "C:/nowhere/missing.png"})
	assert_true(app.backdrop.error.contains("not there"),
		"the reason is recorded: %s" % app.backdrop.error)
	assert_close(await probe(here), earth, 0.02, "and the Earth is still what is drawn")
	await clear_backdrop()


### Helpers


# Change the document's view settings by the names ViewSettings holds them
# under, and let the frame catch up.
func use_settings(changes: Dictionary) -> void:
	for key in changes:
		app.document.view.set(str(key), changes[key])
	app.document.view_edited()
	app.apply_view_settings()
	await frames(2)


func clear_backdrop() -> void:
	await use_settings({
		"backdrop_path": "",
		"backdrop_opacity": ViewSettings.DEFAULT_BACKDROP_OPACITY,
		"backdrop_visible": true,
	})


func backdrop_path() -> String:
	return ProjectSettings.globalize_path(BACKDROP)


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


# How many pixels of a patch of background are brighter than the empty sky, in
# the corner of the view where no part of the planet reaches.
func count_bright_pixels() -> int:
	var image := await capture()
	var origin := corner()
	var count := 0
	for x in range(int(origin.x), int(origin.x) + CORNER_PATCH):
		for y in range(int(origin.y), int(origin.y) + CORNER_PATCH):
			if image.get_pixel(x, y).get_luminance() > 0.1:
				count += 1
	return count


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
