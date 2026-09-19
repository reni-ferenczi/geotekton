extends RenderedCase

# GP-0072: the kinematics panel graphs the rate only, and View > Kinematics:
# latitude and longitude adds the two place rows. The panel is as tall as its
# rows ask, so the height it takes off the planet is read here in pixels.

const PLACE_ITEM := Application.ViewItem.KINEMATICS_PLACE


# The height the graph rows and the time axis need for a number of rows.
func rows_height(rows: int) -> int:
	return rows * (KinematicsPanel.ROW_HEIGHT + KinematicsPanel.ROW_GAP) \
		+ KinematicsPanel.AXIS_HEIGHT


func check_rows(panel: KinematicsPanel, rows: int, what: String) -> void:
	assert_eq(panel.row_count(), rows, "%s: rows drawn" % what)
	assert_eq(panel.custom_minimum_size.y, float(rows_height(rows) + 42),
		"%s: the minimum height the ticket names" % what)
	assert_eq(panel.size.y, panel.get_combined_minimum_size().y,
		"%s: the panel takes no more height than it needs" % what)
	# The graphs get exactly their rows unless the readout wraps and leaves
	# them less than the panel's own minimum asks for.
	assert_true(panel.graphs.size.y >= rows_height(rows)
		and panel.graphs.size.y < rows_height(rows) + KinematicsPanel.ROW_HEIGHT,
		"%s: the graphs are %d rows high, %d px" % [what, rows, panel.graphs.size.y])


func test_the_rate_only_by_default_and_the_place_rows_on_request() -> void:
	var panel: KinematicsPanel = app.kinematics
	await load_sample("motion.geotekt")
	app._on_view_menu_id_pressed(Application.ViewItem.KINEMATICS)
	app.features.feature_tree.select_node(app.document.root.children[0].children[0])
	await frames(3)
	assert_true(panel.visible, "the panel is up")
	assert_true(not panel.show_place, "latitude and longitude start switched off")
	assert_true(not app.view_menu.is_item_checked(app.view_menu.get_item_index(PLACE_ITEM)),
		"and the menu item says so")
	check_rows(panel, 1, "by default")
	var short := panel.size.y

	app._on_view_menu_id_pressed(PLACE_ITEM)
	await frames(3)
	assert_true(panel.show_place, "the menu item switches them on")
	assert_true(app.view_menu.is_item_checked(app.view_menu.get_item_index(PLACE_ITEM)),
		"and is checked")
	check_rows(panel, 3, "switched on")
	assert_eq(panel.size.y - short,
		float(2 * (KinematicsPanel.ROW_HEIGHT + KinematicsPanel.ROW_GAP)),
		"the two place rows make the panel exactly two rows taller")

	# The restart: what the session saves on quitting, read back the way a new
	# start reads it, into a panel switched the other way.
	app._save_session()
	panel.show_place = false
	Config.forget()
	app._restore_session()
	await frames(3)
	assert_true(panel.show_place, "the switch survives a restart through the config")
	check_rows(panel, 3, "after the restart")

	# A config that says nothing leaves it off, and hides the panel with it.
	Config.clear()
	app._restore_session()
	assert_true(not panel.visible, "an empty config hides the panel")
	panel.visible = true
	await frames(3)
	assert_true(not panel.show_place, "an empty config switches the rows off")
	check_rows(panel, 1, "from an empty config")

	# Leave the window as the other rendered tests expect to find it.
	Config.clear()
	panel.visible = false
	app._update_view_menu_checks()
	await frames(2)
