extends TestCase

# What the planet does with a document holding more geometry than it can draw.
# A GPlates import is where one comes from: a global coastline set is tens of
# thousands of triangles and the geometry texture is one texel per primitive
# wide. See Docs/Shader.md and Docs/Import.md.


# A root holding `count` markers, spread over as many features as asked for.
func _tree_of_markers(features: int, per_feature: int) -> Feature:
	var root := Feature.create_group("Planet")
	root.is_root = true
	for i in features:
		var feature := Feature.create_feature("Markers %d" % i, Color.GREEN)
		feature.feature_type = "points"
		var ring := PackedVector2Array()
		for j in per_feature:
			ring.append(Vector2(float(j % 89) - 44.0, float((i * 7 + j) % 359) - 179.0))
		feature.add_ring(ring, Feature.GeometryKind.MULTIPOINT)
		root.children.append(feature)
	return root


func test_a_document_that_fits_is_drawn_whole() -> void:
	var geometry := Planet.collect_geometry(_tree_of_markers(4, 100))
	assert_eq(geometry.primitives.size(), 400, "every marker is drawn")
	assert_eq(geometry.dropped, 0, "nothing was left out")
	assert_eq(geometry.features.size(), 4)


func test_a_document_too_large_to_draw_stops_at_the_limit() -> void:
	# Three times over a limit of 16,384, the old one, in features that do not
	# divide into it, so a count that came out right only because the sizes
	# lined up would show. The real limit is tens of millions of primitives,
	# more than a test builds.
	Planet.primitive_limit = 16384
	var root := _tree_of_markers(24, 2000)
	var geometry := Planet.collect_geometry(root)
	Planet.primitive_limit = Planet.MAX_PRIMITIVES
	assert_true(geometry.primitives.size() <= 16384,
		"no more primitives than the limit: %d" % geometry.primitives.size())
	assert_true(geometry.dropped > 0, "the features that did not fit are counted")
	assert_eq(geometry.features.size() + geometry.dropped, 24,
		"every feature was either drawn or counted as dropped")
	assert_eq(root.child_count(), 24, "and the tree itself still holds all of them")


# GP-0030: the data textures wrap at TEXTURE_WRAP, so a document past the
# 16,384 primitives a single row of texels could hold is drawn whole.
func test_a_document_past_one_row_of_texels_is_drawn_whole() -> void:
	var geometry := Planet.collect_geometry(_tree_of_markers(24, 2000))
	assert_eq(geometry.primitives.size(), 48000, "every marker is drawn")
	assert_eq(geometry.dropped, 0, "nothing was left out")
	assert_eq(Planet._at(48000 - 1, 1, 2),
		Vector2i((48000 - 1) % Planet.TEXTURE_WRAP, (48000 - 1) / Planet.TEXTURE_WRAP * 2 + 1),
		"the last primitive's second row is where the shader reads it")
	var image := Planet._wrapped_image(48000, 2)
	assert_eq(image.get_size(), Vector2i(Planet.TEXTURE_WRAP, 12 * 2),
		"twelve wrapped rows of two texels hold it")


func test_a_feature_is_left_out_whole_rather_than_cut_in_half() -> void:
	var geometry := Planet.collect_geometry(_tree_of_markers(24, 2000))
	for index in geometry.features.size():
		assert_eq(geometry.ends[index] - geometry.starts[index], 2000,
			"feature %d kept all of its markers" % index)
