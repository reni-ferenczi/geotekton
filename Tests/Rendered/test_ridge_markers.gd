extends RenderedCase

# GP-0132: View > Ridge markers, on by default, is remembered in the settings
# file like the other View switches.


func test_the_ridge_markers_switch_survives_a_restart() -> void:
	var item: int = app.view_menu.get_item_index(Application.ViewItem.RIDGE_MARKERS)
	assert_true(app.timeline.show_ridges, "the dots are on by default")
	assert_true(app.view_menu.is_item_checked(item), "and the menu item says so")

	app._on_view_menu_id_pressed(Application.ViewItem.RIDGE_MARKERS)
	assert_true(not app.timeline.show_ridges, "the menu item switches them off")
	assert_true(not app.view_menu.is_item_checked(item), "and is unchecked")

	# The restart: what the session saves on quitting, read back the way a new
	# start reads it, into a timeline switched the other way.
	app._save_session()
	app.timeline.show_ridges = true
	Config.forget()
	app._restore_session()
	assert_true(not app.timeline.show_ridges, "the switch survives a restart through the config")

	Config.clear()
	app._restore_session()
	assert_true(app.timeline.show_ridges, "a config that says nothing leaves them on")
	await frames(1)
