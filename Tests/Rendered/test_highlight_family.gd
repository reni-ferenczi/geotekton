extends RenderedCase

# GP-0137: with View > Highlight parent and siblings on, selecting a feature
# that follows another traces its parent in magenta and its siblings in lime
# on the planet, and tints their rows the same way. The switch is remembered.

const ITEM := Application.ViewItem.HIGHLIGHT_FAMILY
const ZOOM := 3.0
# How far a pixel may be from a color, per channel, and how far around a probe
# on an edge the colors are counted.
const TOLERANCE := 0.12
const REACH := 4


func test_the_parent_and_a_sibling_are_traced_in_their_colors() -> void:
	await load_sample("two_cratons.geotekt")
	app.set_active_tool(Application.Tool.MOVE)
	var flat := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	flat.fill(Color.BLACK)
	view().planet.set_raster(ImageTexture.create_from_image(flat), 1.0)
	var parent := _find("Red Triangle")
	var selected := _find("Blue Quad")
	var sibling := _find("Green Moved")
	var time: float = app.document.current_time
	assert_eq(app.document.couple(selected, parent, time), "", "Blue Quad follows Red Triangle")
	assert_eq(app.document.couple(sibling, parent, time), "", "and so does Green Moved")
	app.refresh_geometry()
	app.features.feature_tree.select_node(selected)
	view().set_zoom(ZOOM)

	var off := await _count_near(parent, Planet.PARENT_COLOR)
	app._on_view_menu_id_pressed(ITEM)
	var on_parent := await _count_near(parent, Planet.PARENT_COLOR)
	var on_sibling := await _count_near(sibling, Planet.SIBLING_COLOR)
	var tints := [_tint(parent), _tint(sibling), _tint(selected)]
	app._on_view_menu_id_pressed(ITEM)
	var tint_after := _tint(parent)
	view().set_zoom(PlanetView.DEFAULT_ZOOM)
	view().planet.set_raster(null, 0.0)

	assert_eq(off, 0, "switched off, the parent is not magenta")
	assert_true(on_parent > 0, "switched on, the parent's edge is magenta: %d pixels" % on_parent)
	assert_true(on_sibling > 0, "and the sibling's edge lime: %d pixels" % on_sibling)
	assert_eq(tints[0], FeatureTree.PARENT_TINT, "the parent's row is tinted")
	assert_eq(tints[1], FeatureTree.SIBLING_TINT, "the sibling's row too, in its own tint")
	assert_true(tints[2] != FeatureTree.PARENT_TINT and tints[2] != FeatureTree.SIBLING_TINT,
		"the selected row is not")
	assert_true(tint_after != FeatureTree.PARENT_TINT, "switched off, the tint goes")


func test_a_group_or_a_free_feature_highlights_nothing() -> void:
	await load_sample("two_cratons.geotekt")
	app._on_view_menu_id_pressed(ITEM)
	app.features.feature_tree.select_node(_find("Blue Quad"))
	await frames(2)
	assert_eq(app.related_features.size(), 0, "a feature that follows nothing has no parent")
	app.features.feature_tree.select_root()
	await frames(2)
	assert_eq(app.related_features.size(), 0, "and a group has none")
	app._on_view_menu_id_pressed(ITEM)


func test_the_switch_survives_a_restart() -> void:
	var item: int = app.view_menu.get_item_index(ITEM)
	assert_true(not app.highlight_family, "off by default")
	app._on_view_menu_id_pressed(ITEM)
	assert_true(app.view_menu.is_item_checked(item), "the menu item switches it on and is checked")
	app._save_session()
	app.highlight_family = false
	Config.forget()
	app._restore_session()
	assert_true(app.highlight_family, "the switch survives a restart through the config")
	Config.clear()
	app._restore_session()
	assert_true(not app.highlight_family, "a config that says nothing leaves it off")
	await frames(1)


func _find(title: String) -> Feature:
	var stack: Array[Feature] = [app.features.root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if node.title == title:
			return node
		stack.append_array(node.children)
	return null


func _tint(feature: Feature) -> Color:
	return app.features.feature_tree.items[feature.pnid].get_custom_bg_color(0)


# Turn to the middle of each edge of a feature in turn and count the pixels
# near the color around it, over every edge.
func _count_near(feature: Feature, color: Color) -> int:
	var ring := Feature.apply_basis(feature.rings[0],
		Feature.world_basis(app.features.root, feature, app.document.current_time))
	var total := 0
	for i in ring.size():
		var middle := Measure.along(ring[i], ring[(i + 1) % ring.size()], 0.5)
		await look_at_latlon(middle.x, middle.y)
		await frames(2)
		var centre: Variant = view().latlon_to_screen(middle.x, middle.y)
		if centre == null:
			continue
		var image := await capture()
		for dy in range(-REACH, REACH + 1):
			for dx in range(-REACH, REACH + 1):
				var pixel := image.get_pixel(int(centre.x) + dx, int(centre.y) + dy)
				if absf(pixel.r - color.r) < TOLERANCE and absf(pixel.g - color.g) < TOLERANCE \
						and absf(pixel.b - color.b) < TOLERANCE:
					total += 1
	return total
