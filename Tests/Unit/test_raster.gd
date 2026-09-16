extends TestCase

# Reading the image a document wears. The fixtures in Tests/Data/Rasters are
# the same four quarters in each of the four formats, so what is checked is that
# every format arrives with the picture intact and that a file that cannot be
# read says so instead of failing quietly.

const DIR := "res://Tests/Data/Rasters"

# Where each quarter of the fixture is, as a fraction across and down, and the
# colour it is painted. The image is 64 by 32; the probes sit in the middle of
# each quarter, away from the seams.
const QUARTERS := [
	[0.25, 0.25, Color(1, 0, 0)],
	[0.75, 0.25, Color(0, 1, 0)],
	[0.25, 0.75, Color(0, 0, 1)],
	[0.75, 0.75, Color(1, 1, 0)],
]

# JPEG is lossy and an SVG is rasterized and resampled, so a quarter comes back
# near its colour rather than at it.
const COLOR_TOLERANCE := 0.08


func test_every_format_loads_with_the_picture_intact() -> void:
	for name in ["quarters.png", "quarters.jpg", "quarters.webp", "quarters.svg"]:
		var raster := Raster.load_from(_path(name))
		if not assert_no_error(raster, name):
			continue
		var image := raster.texture.get_image()
		assert_true(image.get_width() > image.get_height(),
			"%s is wider than it is tall, as the fixture is" % name)
		for quarter in QUARTERS:
			var x := int(float(quarter[0]) * float(image.get_width()))
			var y := int(float(quarter[1]) * float(image.get_height()))
			assert_close(image.get_pixel(x, y), quarter[2], COLOR_TOLERANCE,
				"the quarter at (%s, %s) of %s" % [quarter[0], quarter[1], name])


# An SVG has no pixels of its own, so it is rasterized to a fixed width rather
# than to the number the file happens to name.
func test_an_svg_is_rasterized_large_enough_to_wrap_a_planet() -> void:
	var raster := Raster.load_from(_path("quarters.svg"))
	if not assert_no_error(raster, "quarters.svg"):
		return
	assert_eq(raster.texture.get_width(), int(Raster.SVG_WIDTH),
		"the SVG is drawn at the width Raster asks for")


func test_an_image_that_is_not_there_says_so() -> void:
	var raster := Raster.load_from(_path("no_such_file.png"))
	assert_eq(raster.texture, null, "there is no texture")
	assert_true(raster.error.contains("not there"), "and the reason says so: %s" % raster.error)


func test_a_format_that_is_not_an_image_says_so() -> void:
	var raster := Raster.load_from("res://Tests/Data/craton.middle-earth")
	assert_eq(raster.texture, null, "there is no texture")
	assert_true(raster.error.contains("not an image"),
		"and the reason names the formats: %s" % raster.error)


# A document that names no image is not a failure: there is nothing to load and
# nothing to complain about, and the built in Earth is what shows.
func test_no_image_at_all_is_not_an_error() -> void:
	var raster := Raster.load_from("")
	assert_eq(raster.texture, null, "there is no texture")
	assert_eq(raster.error, "", "and nothing went wrong")


func assert_no_error(raster: Raster, name: String) -> bool:
	if raster.texture == null:
		fail("%s did not load: %s" % [name, raster.error])
		return false
	assert_eq(raster.error, "", "%s loaded without complaint" % name)
	return true


func _path(name: String) -> String:
	return ProjectSettings.globalize_path("%s/%s" % [DIR, name])
