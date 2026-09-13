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
	# Three times over the limit, in features that do not divide into it, so a
	# count that came out right only because the sizes lined up would show.
	var root := _tree_of_markers(24, 2000)
	var geometry := Planet.collect_geometry(root)
	assert_true(geometry.primitives.size() <= Planet.MAX_PRIMITIVES,
		"no more primitives than the geometry texture can be made for: %d"
			% geometry.primitives.size())
	assert_true(geometry.dropped > 0, "the features that did not fit are counted")
	assert_eq(geometry.features.size() + geometry.dropped, 24,
		"every feature was either drawn or counted as dropped")
	assert_eq(root.child_count(), 24, "and the tree itself still holds all of them")


func test_a_feature_is_left_out_whole_rather_than_cut_in_half() -> void:
	var geometry := Planet.collect_geometry(_tree_of_markers(24, 2000))
	for index in geometry.features.size():
		assert_eq(geometry.ends[index] - geometry.starts[index], 2000,
			"feature %d kept all of its markers" % index)
