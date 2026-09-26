extends RenderedCase

# A status bar message longer than the window, which a split that cuts many
# features writes, is trimmed with an ellipsis rather than widening the layout
# past the window and pushing the menu and the feature tree off its left edge.


func test_a_long_message_does_not_widen_the_window() -> void:
	await load_sample("mixed_geometry.geotekt")
	var window: Rect2 = app.get_viewport().get_visible_rect()
	var names := PackedStringArray()
	for i in 60:
		names.append("Supercontinent %d crust" % i)
	app._report("Split into %s" % ", ".join(names))
	await frames(3)
	assert_true(app.status_measure.get_combined_minimum_size().x < window.size.x,
		"the message asks for no more than the window")
	for control: Control in [app.get_node("StatusBar"), app.features]:
		var rect := control.get_global_rect()
		assert_true(rect.position.x >= 0.0 and rect.end.x <= window.end.x + 0.5,
			"%s stays inside the window: %s in %s" % [control.name, rect, window])
	app._report("")
	await frames(2)
