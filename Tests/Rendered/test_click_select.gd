extends RenderedCase

# Clicking a craton in the window selects it in the feature tree.
# The click goes through Input, the physics picking of the SubViewport and
# Application._on_craton_clicked, which selects with call_deferred.


func test_clicking_a_craton_selects_it() -> void:
	await load_sample("two_cratons.middle-earth")
	await _click_latlon(30.0, 45.0)
	assert_eq(_selected_title(), "Blue Quad")
	await _click_latlon(-3.0, -60.0)
	assert_eq(_selected_title(), "Green Moved")
	await _click_latlon(-3.0, 0.0)
	assert_eq(_selected_title(), "Red Triangle")
	var selected: Feature = app.features.feature_tree.get_selected_node()
	if selected != null:
		assert_eq(selected.rings.size(), 1, "the red triangle is one ring")
		assert_eq(selected.vertex_count(), 3, "the red triangle has three vertices")


func test_clicking_the_bare_globe_keeps_the_selection() -> void:
	await load_sample("two_cratons.middle-earth")
	await _click_latlon(-3.0, 0.0)
	assert_eq(_selected_title(), "Red Triangle")
	# (5, 40) is on the globe but on no craton, the selection only changes on a hit.
	await _click_latlon(5.0, 40.0)
	assert_eq(_selected_title(), "Red Triangle", "a miss leaves the selection alone")


func _click_latlon(lat: float, lon: float) -> void:
	await look_at_latlon(lat, lon)
	var screen: Variant = view().latlon_to_screen(lat, lon)
	assert_true(screen != null, "lat/lon (%s, %s) must be visible" % [lat, lon])
	if screen == null:
		return
	await click(screen)


func _selected_title() -> String:
	var selected: Feature = app.features.feature_tree.get_selected_node()
	return "" if selected == null else selected.title
