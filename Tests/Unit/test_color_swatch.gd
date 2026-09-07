extends TestCase

# Helpers.render_cell builds the 32x32 colour swatch shown on the colour button of
# every tree row. The image format has to be an uncompressed one: Image.fill refuses
# a compressed format, which left the swatch blank and printed an error per feature.


func test_the_swatch_is_filled_with_the_requested_colour() -> void:
	var image := Helpers.render_cell(Color.RED).image
	assert_eq(image.get_format(), Image.FORMAT_RGBA8, "fill only works on an uncompressed format")
	assert_eq(image.get_pixel(0, 0), Color.RED)
	assert_eq(image.get_pixel(31, 31), Color.RED, "the whole swatch is filled, not just a corner")


func test_each_colour_gets_its_own_swatch() -> void:
	var red := Helpers.render_cell(Color.RED)
	var blue := Helpers.render_cell(Color.BLUE)
	assert_eq(red.image.get_pixel(0, 0), Color.RED)
	assert_eq(blue.image.get_pixel(0, 0), Color.BLUE)
	assert_true(Helpers.render_cell(Color.RED) == red, "a repeated colour comes from the cache")
