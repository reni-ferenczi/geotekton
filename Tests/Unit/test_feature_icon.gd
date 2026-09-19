extends TestCase

# The built in glyphs a feature's tree row can carry. What matters here is that
# every id in the catalog has a picture behind it, at the size of the rule icon,
# and that the picture has something on it: a file that failed to load or a
# shrink that went wrong comes back blank, which no screenshot would give away.

# The floor is there to catch a glyph that came out blank, not to measure the
# drawing.
const MIN_DRAWN_PIXELS := 60


func test_every_id_in_the_catalog_has_a_glyph() -> void:
	for id in FeatureIcon.CATALOG:
		var texture := FeatureIcon.texture(id)
		assert_true(texture != null, "%s has a texture" % id)
		if texture == null:
			continue
		assert_eq(texture.get_size(), Vector2(FeatureIcon.SIZE, FeatureIcon.SIZE),
			"%s is %d pixels square, the size of the rule icon" % [id, FeatureIcon.SIZE])
		assert_eq(texture.resource_name, id, "%s is named after its id, for the automation port" % id)

		var image := texture.get_image()
		var drawn := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.5:
					drawn += 1
		assert_true(drawn >= MIN_DRAWN_PIXELS,
			"%s has something drawn on it: %d pixels" % [id, drawn])


func test_an_id_nobody_knows_has_no_glyph() -> void:
	assert_true(FeatureIcon.texture(FeatureIcon.NONE) == null, "no icon, no picture")
	assert_true(FeatureIcon.texture("sombrero") == null,
		"and neither has one this version does not know, which a hand written file can carry")


func test_every_glyph_has_a_file_and_every_file_a_glyph() -> void:
	for id in FeatureIcon.CATALOG:
		assert_true(FeatureIcon.FILES.has(id), "%s has a picture named" % id)
	for id in FeatureIcon.FILES:
		assert_true(FeatureIcon.CATALOG.has(id), "%s is offered in the selector" % id)


func test_every_glyph_is_named() -> void:
	for id in FeatureIcon.CATALOG:
		assert_true(not FeatureIcon.label(id).is_empty(), "%s is named in the selector" % id)
	assert_eq(FeatureIcon.label("sombrero"), "", "and an id nobody knows is not")
