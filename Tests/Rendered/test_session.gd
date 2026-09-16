extends RenderedCase

# The window geometry, the splitter offsets and the panel visibility are what a
# session is made of. Saving and restoring them is what a person would check by
# closing the application and opening it again; here the same round trip is run
# against a real window and a scratch config file.
#
# The tests hosted this way are isolated, so Config already points at a scratch
# folder and nothing here can reach the settings of whoever is at the keyboard.

const MOVED_SIZE := Vector2i(1200, 700)
const MOVED_POSITION := Vector2i(140, 90)


# A SplitContainer clamps its offset to what the child needs, so an offset in
# the scene below a panel's floor would be asking for a width the window never
# shows. The two are checked against each other here so they cannot part
# company. test_narrow_panels.gd drags both panels down to their floors.
func test_each_panel_is_the_width_its_splitter_asks_for() -> void:
	await load_sample("two_cratons.middle-earth")
	assert_eq(app.left_splitter.split_offset, app.features.size.x,
		"the feature tree panel is as wide as its offset asks")
	assert_eq(app.right_splitter.split_offset, -int(app.properties.size.x),
		"and the properties panel is too, measured from the right")


func test_the_window_and_the_panels_come_back() -> void:
	assert_true(app.isolated, "a hosted application does not touch the real settings")

	var window: Window = app.get_window()
	var original_size: Vector2i = window.size
	var original_position: Vector2i = window.position
	var original_left: int = app.left_splitter.split_offset
	var original_right: int = app.right_splitter.split_offset

	window.size = MOVED_SIZE
	window.position = MOVED_POSITION
	app.left_splitter.split_offset = 401
	app.right_splitter.split_offset = -277
	app.timeline.visible = false
	app.status_bar.visible = false
	await frames(2)

	app._save_session()

	# Come back to something else, so a restore that does nothing cannot pass.
	window.size = original_size
	window.position = original_position
	app.left_splitter.split_offset = 100
	app.right_splitter.split_offset = -100
	app.timeline.visible = true
	app.status_bar.visible = true
	await frames(2)

	Config.forget()
	app._restore_session()
	await frames(2)

	assert_eq(window.size, MOVED_SIZE, "the window size comes back")
	assert_eq(window.position, MOVED_POSITION, "the window position comes back")
	assert_eq(app.left_splitter.split_offset, 401, "the left splitter comes back")
	assert_eq(app.right_splitter.split_offset, -277, "the right splitter comes back")
	assert_true(not app.timeline.visible, "the hidden timeline stays hidden")
	assert_true(not app.status_bar.visible, "the hidden status bar stays hidden")
	assert_true(app.features.visible, "the panels left alone are still shown")
	assert_true(app.properties.visible, "the panels left alone are still shown")

	# Leave the window as the other rendered tests expect to find it.
	Config.clear()
	window.size = original_size
	window.position = original_position
	app.left_splitter.split_offset = original_left
	app.right_splitter.split_offset = original_right
	app.timeline.visible = true
	app.status_bar.visible = true
	app._update_view_menu_checks()
	await frames(2)


func test_full_screen_can_be_entered_and_left() -> void:
	var window: Window = app.get_window()
	assert_true(not app.is_full_screen(), "the window starts out windowed")
	assert_true(not app.leave_full_screen.get_parent().visible, "and without the leave button")

	app._toggle_full_screen()
	await frames(2)
	assert_true(app.is_full_screen(), "F11 enters full screen")
	assert_true(app.leave_full_screen.get_parent().visible, "the leave button is offered")

	app.leave_full_screen.pressed.emit()
	await frames(2)
	assert_true(not app.is_full_screen(), "the button leaves full screen")
	assert_true(not app.leave_full_screen.get_parent().visible, "and takes itself away")
	assert_eq(window.mode, Window.MODE_WINDOWED, "the window is windowed again")
	await frames(2)


func test_the_cursor_position_reaches_the_status_bar() -> void:
	view().cursor_moved.emit(10.0, 20.0)
	await frames(1)
	assert_eq(app.status_coordinates.text, "10.00° N   20.00° E")

	view().cursor_moved.emit(-10.0, -20.0)
	await frames(1)
	assert_eq(app.status_coordinates.text, "10.00° S   20.00° W")

	view().cursor_moved.emit(NAN, NAN)
	await frames(1)
	assert_eq(app.status_coordinates.text, "off the planet")
