extends RenderedCase

# A double click sends the press twice, the second one flagged double_click,
# and the Draw tool used to put the vertex down for each of them. The repeated
# vertex is a corner the fill could not reach, so the polygon of
# FillBugRepro.geotekt stopped short of its last point. The second press is
# dropped before any tool sees it. The events go to the Application's handler
# directly: the double click flag is set by the window system, which an
# injected click never reaches.

const AT := Vector2(10.0, 20.0)


func test_a_double_click_puts_one_vertex_down() -> void:
	await load_sample("empty.geotekt")
	var feature := Feature.create_feature("Drawn")
	app.features.root.children.append(feature)
	app.features.reload()
	app.features.feature_tree.select_node(feature)
	app.set_active_tool(Application.Tool.DRAW)
	Config.set_snap_to_vertices(false)

	app._on_planet_input(AT.x, AT.y, _press(false))
	assert_eq(app.outline_vertices.size(), 1, "the first press places the vertex")
	app._on_planet_input(AT.x, AT.y, _press(true))
	assert_eq(app.outline_vertices.size(), 1, "the second press of the double click places nothing")
	app._on_planet_input(AT.x + 5.0, AT.y, _press(false))
	assert_eq(app.outline_vertices.size(), 2, "and the next click goes on as before")

	app.set_active_tool(Application.Tool.MOVE)
	app.features.feature_tree.select_root()
	await frames(2)


func test_a_double_click_measures_one_point() -> void:
	await load_sample("empty.geotekt")
	app.set_active_tool(Application.Tool.MEASURE)

	app._on_planet_input(AT.x, AT.y, _press(false))
	app._on_planet_input(AT.x, AT.y, _press(true))
	assert_eq(app.measure_points.size(), 1, "the double click is one point of the path")

	app.set_active_tool(Application.Tool.MOVE)
	await frames(2)


# A left press on the globe, the second of a double click when told so.
func _press(double: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	event.double_click = double
	return event
