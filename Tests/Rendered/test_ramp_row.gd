extends RenderedCase

# The + and − buttons of a ramp row, pressed with the mouse. Each press frees
# the row it sits in while the viewport is still delivering the click to it,
# which is where a keyboard press and a mouse click part ways.


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


func test_a_mouse_click_on_plus_in_the_view_dialog_adds_a_colour() -> void:
	await load_sample("mixed_geometry.middle-earth")
	app.show_view_settings()
	await frames(3)
	var row := app.view_fields["ramp_colors"] as RampRow
	var before := row.colors.size()

	await _press("AddRampColor", row, app.view_dialog)
	assert_eq(row.colors.size(), before + 1, "a click on + in the dialog adds a colour")
	assert_eq(app.document.root.style.ramp_colors.size(), before + 1, "and the root's style holds it")

	await _press("DropRampColor%d" % before, row, app.view_dialog)
	assert_eq(row.colors.size(), before, "a click on − in the dialog takes it out again")
	app.view_dialog.hide()
	await frames(2)


func _press(button_name: String, row: RampRow = app.properties.ramp_row, window: Window = null) -> void:
	var button := row.find_child(button_name, true, false) as Button
	assert_true(button != null, "the row shows a %s button" % button_name)
	if button == null:
		return
	var center := button.get_global_rect().get_center()
	if window != null:
		center += Vector2(window.position)
	await click(center)


func _group(title: String) -> Feature:
	for node in app.features.root.children:
		if node.title == title:
			return node
	return null
