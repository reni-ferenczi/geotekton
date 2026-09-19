extends RenderedCase

# GP-0064: the Time menu, the tree toolbar's Info button and the view toolbar's
# zoom reset button are gone. Page Up and Page Down still move the time
# wherever the focus is, except inside a text field.

const SKIP := 10.0


func test_the_removed_controls_are_gone() -> void:
	assert_true(app.find_child("ZoomReset", true, false) == null,
		"the view toolbar has no zoom reset button")
	assert_true(app.find_child("CameraReset", true, false) != null,
		"and still has the camera reset button")
	assert_true(app.features.get_node("PanelContainer/Buttons").find_child("Info", true, false)
		== null, "the tree toolbar has no Info button")
	var titles: Array = []
	for index in app.menu_bar.get_menu_count():
		titles.append(app.menu_bar.get_menu_title(index))
	assert_eq(titles, ["File", "Edit", "View", "Help"], "the menu bar has four menus")


func test_page_keys_skip_with_the_planet_focused() -> void:
	var middle: float = await _start()
	await look_at_latlon(0.0, 0.0)
	var screen: Variant = view().latlon_to_screen(0.0, 0.0)
	assert_true(screen != null, "the middle of the planet is in view")
	if screen == null:
		return
	await click(screen as Vector2)
	assert_true(not app._typing(), "a click on the planet leaves no text field focused")

	await _key(KEY_PAGEDOWN)
	assert_eq(_time(), middle - SKIP, "Page Down skips towards the younger end")
	await _key(KEY_PAGEUP)
	assert_eq(_time(), middle, "and Page Up comes back")

	# A focused Tree scrolls on Page Up by itself, which the key must not reach.
	app.features.feature_tree.grab_focus()
	await _key(KEY_PAGEUP)
	assert_eq(_time(), middle + SKIP, "Page Up skips with the feature tree focused too")
	app.get_viewport().gui_release_focus()


func test_page_keys_leave_the_time_alone_in_the_console() -> void:
	var middle: float = await _start()
	var shown: bool = app.console.visible
	app.console.visible = true
	await frames(1)
	app.console.input.grab_focus()
	await _key(KEY_PAGEUP)
	await _key(KEY_PAGEDOWN)
	await _key(KEY_PAGEDOWN, true)
	assert_eq(_time(), middle, "the time keys do nothing while the console's input is focused")
	app.get_viewport().gui_release_focus()
	app.console.visible = shown
	await frames(1)


# Load the motion sample, set the skip and put the time in the middle of the
# animation, so a skip either way stays inside it.
func _start() -> float:
	await load_sample("motion.geotekt")
	app.timeline.skip_spin.value = SKIP
	var middle := roundf((app.timeline.oldest() + app.timeline.youngest()) / 2.0)
	app.document.set_time(middle)
	await frames(2)
	return middle


func _time() -> float:
	return app.document.current_time


func _key(keycode: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		Input.parse_input_event(event)
	await frames(2)
