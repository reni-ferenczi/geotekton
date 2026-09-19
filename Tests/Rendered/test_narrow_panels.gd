extends RenderedCase

# GP-0073: both side panels can be dragged down to their floors, 200 px for the
# feature tree and 220 px for the Properties panel, and everything in them still
# lies inside them. The widths and the rectangles are read off the widgets.

const LEFT_FLOOR := 200
const RIGHT_FLOOR := 220
# How far a panel may end up from the offset it was given.
const SLACK := 3.0


func test_both_panels_go_down_to_their_floors() -> void:
	await load_sample("mixed_geometry.geotekt")
	var original_left: int = app.left_splitter.split_offset
	var original_right: int = app.right_splitter.split_offset
	app.left_splitter.split_offset = LEFT_FLOOR
	app.right_splitter.split_offset = -RIGHT_FLOOR
	await frames(3)

	assert_close(app.features.size.x, LEFT_FLOOR, SLACK,
		"the feature tree panel is %d px wide" % app.features.size.x)
	assert_close(app.properties.size.x, RIGHT_FLOOR, SLACK,
		"the properties panel is %d px wide" % app.properties.size.x)
	_check_toolbar()
	_check_middle_column()

	var group: Feature = app.document.root.children[0]
	var polygon: Feature = group.children[0]
	assert_eq(polygon.geometry_kind, Feature.GeometryKind.POLYGON, "the sample's first leaf is a polygon")
	for node in [polygon, group]:
		app.features.feature_tree.select_node(node)
		await frames(3)
		var what := "with %s selected" % node.title
		assert_close(app.properties.size.x, RIGHT_FLOOR, SLACK,
			"%s the properties panel keeps its width, %d px" % [what, app.properties.size.x])
		_check_inside(app.properties, app.properties.get_node("Margin"), what)

	app.left_splitter.split_offset = original_left
	app.right_splitter.split_offset = original_right
	await frames(2)


# Every button of the tree toolbar is inside the panel, over two lines or more.
func _check_toolbar() -> void:
	var panel := app.features.get_global_rect() as Rect2
	var lines := {}
	for button in app.features.get_node("PanelContainer/Buttons").get_children():
		if not button is Button:
			continue
		var rect: Rect2 = button.get_global_rect()
		assert_true(panel.encloses(rect),
			"the %s button %s lies inside the panel %s" % [button.name, rect, panel])
		lines[rect.position.y] = true
	assert_true(lines.size() >= 2, "the toolbar wraps onto %d lines" % lines.size())


# The middle column gets at least what it asks for, so its view toolbar fits.
func _check_middle_column() -> void:
	var center: Control = app.get_node("LeftSplitter/RightSplitter/Center")
	var tools: Control = center.get_node("ViewPanel/ViewTools")
	assert_eq(app.get_window().size.x, 1800, "the window is the 1800 px the ticket names")
	assert_true(center.size.x >= center.get_combined_minimum_size().x,
		"the middle column, %d px, is as wide as it asks" % center.size.x)
	assert_true(center.get_global_rect().encloses(tools.get_global_rect()),
		"the view toolbar row %s lies inside the middle column %s"
			% [tools.get_global_rect(), center.get_global_rect()])


# Every visible control under `root` lies inside the panel.
func _check_inside(panel: Control, root: Control, what: String) -> void:
	var bounds := panel.get_global_rect()
	for child in root.find_children("*", "Control", true, false):
		var control := child as Control
		if not control.is_visible_in_tree() or control.size == Vector2.ZERO:
			continue
		var rect := control.get_global_rect()
		assert_true(bounds.encloses(rect),
			"%s %s %s lies inside the panel %s" % [what, control.name, rect, bounds])
