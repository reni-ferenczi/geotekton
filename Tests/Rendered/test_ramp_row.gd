extends RenderedCase

# The + and − buttons of a ramp row, pressed with the mouse. Each press has the
# row it sits in rebuilt while the viewport is still delivering the click to
# it, which is where a keyboard press and a mouse click part ways. Also the
# layout: a ramp of more colours than fit on one line wraps inside the panel.


func test_a_mouse_click_on_plus_adds_a_colour() -> void:
	await load_sample("mixed_geometry.middle-earth")
	var group := _group("Shapes")
	assert_true(group != null, "the sample must contain the Shapes group")
	if group == null:
		return
	app.features.feature_tree.select_node(group)
	await frames(2)

	await _press("AddRampColor")
	assert_eq(app.properties.ramp_row.colors.size(), 3, "a click on + adds a third colour")
	assert_eq(group.style.ramp_colors.size(), 3, "and the group's style holds it")

	await _press("DropRampColor2")
	assert_eq(app.properties.ramp_row.colors.size(), 2, "a click on − takes it out again")
	assert_eq(group.style.ramp_colors.size(), 2, "and the group's style follows")


func test_plus_clicked_while_a_ramp_picker_is_open() -> void:
	await load_sample("mixed_geometry.middle-earth")
	var group := _group("Shapes")
	if group == null:
		return
	app.features.feature_tree.select_node(group)
	await frames(2)

	var picker := app.properties.ramp_row.find_child("RampColor0", true, false) as ColorPickerButton
	await click(picker.get_global_rect().get_center())
	assert_true(picker.get_popup().visible, "the click opens the ramp colour picker")
	picker.color_changed.emit(Color.RED)
	await frames(2)

	# A click outside the popup closes it and goes no further. The close commits
	# the colour, and the commit has the panel rebuild the row the popup belongs
	# to, which used to free the picker mid close and crash the engine.
	await _press("AddRampColor")
	assert_true(not is_instance_valid(picker), "the commit that follows the close rebuilds the row")
	picker = app.properties.ramp_row.find_child("RampColor0", true, false) as ColorPickerButton
	assert_true(not picker.get_popup().visible, "and the picker of the rebuilt row is closed")
	assert_eq(group.style.ramp_colors[0], Color.RED, "and the picked colour is committed")
	assert_eq(app.properties.ramp_row.colors.size(), 2, "the click that closed the picker adds nothing")

	await _press("AddRampColor")
	assert_eq(app.properties.ramp_row.colors.size(), 3, "the next click on + adds a colour")


func test_a_long_ramp_wraps_inside_the_panel() -> void:
	await load_sample("mixed_geometry.middle-earth")
	var group := _group("Shapes")
	if group == null:
		return
	app.features.feature_tree.select_node(group)
	await frames(2)
	var row: RampRow = app.properties.ramp_row
	var stops: Array[Color] = [Color.BLACK, Color.RED, Color.YELLOW, Color.BLUE,
		Color.MAGENTA, Color.GREEN, Color.CYAN, Color.WHITE]
	row.colors = stops
	await frames(3)

	var right: float = row.get_global_rect().end.x
	var first := row.find_child("RampColor0", true, false) as Control
	var last := row.find_child("RampColor7", true, false) as Control
	var plus := row.find_child("AddRampColor", true, false) as Control
	var names: Array[String] = ["AddRampColor"]
	for i in stops.size():
		names.append("RampColor%d" % i)
	var lowest := 0.0
	for name in names:
		var widget := row.find_child(name, true, false) as Control
		assert_true(widget.get_global_rect().end.x <= right + 0.5,
			"%s stays inside the row, right edge %.0f of %.0f" % [name, widget.get_global_rect().end.x, right])
		lowest = maxf(lowest, widget.get_global_rect().position.y)
	assert_true(lowest > first.get_global_rect().position.y,
		"eight stops do not fit on one line, so the row wraps")
	assert_true(plus.get_global_rect().position.y >= last.get_global_rect().position.y,
		"and + follows the last colour")
	var drop := row.find_child("DropRampColor7", true, false) as Control
	assert_eq(drop.get_global_rect().position.y, last.get_global_rect().position.y,
		"a − stays on the line of its colour")
	var span := row.span_spin
	assert_eq(span.size.y, span.get_combined_minimum_size().y,
		"the span box keeps its own height rather than the row's")
	assert_eq(span.get_global_rect().position.y, first.get_global_rect().position.y,
		"and sits beside the first line")


func _press(button_name: String) -> void:
	var button := app.properties.ramp_row.find_child(button_name, true, false) as Button
	assert_true(button != null, "the row shows a %s button" % button_name)
	if button == null:
		return
	await click(button.get_global_rect().get_center())


func _group(title: String) -> Feature:
	for node in app.features.root.children:
		if node.title == title:
			return node
	return null
