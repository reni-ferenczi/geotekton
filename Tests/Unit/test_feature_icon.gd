extends TestCase

# The built in glyphs a feature's tree row can carry. What matters here is that
# every id in the catalog has a picture behind it and that the picture has
# something drawn on it: an SVG that failed to rasterize comes back fully
# transparent, which no screenshot would give away.

# The thinnest of them, the river, covers 22 of the 256 pixels. The floor is
# there to catch a glyph that came out blank, not to measure the drawing.
const MIN_DRAWN_PIXELS := 15


func test_every_id_in_the_catalog_has_a_glyph() -> void:
	for id in FeatureIcon.CATALOG:
		var texture := FeatureIcon.texture(id)
		assert_true(texture != null, "%s has a texture" % id)
		if texture == null:
			continue
		assert_eq(texture.get_size(), Vector2(16, 16), "%s is 16 pixels square" % id)

		var image := texture.get_image()
		var drawn := 0
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.5:
					drawn += 1
					assert_close(Color(pixel, 1.0), Color.WHITE, 0.05,
						"%s is drawn in white, so the tree can tint it" % id)
		assert_true(drawn >= MIN_DRAWN_PIXELS,
			"%s has something drawn on it: %d pixels" % [id, drawn])


func test_an_id_nobody_knows_has_no_glyph() -> void:
	assert_true(FeatureIcon.texture(FeatureIcon.NONE) == null, "no icon, no picture")
	assert_true(FeatureIcon.texture("sombrero") == null,
		"and neither has one this version does not know, which a hand written file can carry")


func test_every_glyph_is_named() -> void:
	for id in FeatureIcon.CATALOG:
		assert_true(not FeatureIcon.label(id).is_empty(), "%s is named in the selector" % id)
	assert_eq(FeatureIcon.label("sombrero"), "", "and an id nobody knows is not")
