extends RenderedCase

# GP-0034: the feature selected in the tree is highlighted on the planet. A
# polygon gets a yellow outline along its rings with no dot on its vertices, a
# line is drawn thicker and yellow, and a multipoint keeps its markers, drawn
# larger. The dots come back in the Vertex tool alone.
#
# The planet wears a flat red raster throughout, since the Earth's detail does
# not come out the same from one frame to the next. Every probe reads a small
# square rather than one pixel: the globe is a tessellated mesh, so a place can
# land a pixel or two off where it is computed to be.

# Zoomed in this far the 0.002 wide outline line is several pixels across.
const POLYGON_ZOOM := 8.0
const LINE_ZOOM := 4.0

# The half size of the square read around the middle of an edge.
const EDGE_REACH := 10

# The outline dot radius and the segment width of planet.gdshader, as chord
# lengths on the unit sphere. test_shader_defaults.gd holds both to the shader.
const DOT_RADIUS := Planet.DEFAULT_DOT_RADIUS
const LINE_WIDTH := 0.012


func test_a_selected_polygon_has_a_yellow_outline_along_its_edges() -> void:
	var feature := await _load_with_raster("craton.middle-earth", "Old Shield")
	if feature == null:
		return
	var ring := _world_ring(feature)
	view().set_zoom(POLYGON_ZOOM)
	var probed := 0
	for i in ring.size():
		var middle := Measure.along(ring[i], ring[(i + 1) % ring.size()], 0.5)
		if _near_grid(middle):
			continue
		await look_at_latlon(middle.x, middle.y)
		var centre: Variant = view().latlon_to_screen(middle.x, middle.y)
		if centre == null:
			continue
		_select(null)
		await frames(2)
		var plain := _count(await capture(), centre, EDGE_REACH)
		_select(feature)
		await frames(2)
		var selected := _count(await capture(), centre, EDGE_REACH)
		assert_true(plain["yellow"] == 0 and plain["blue"] > 0 and plain["red"] > 0,
			"unselected, the edge %d is the fill against the raster: %s" % [i, plain])
		assert_true(selected["yellow"] > 0,
			"selected, the edge %d is traced in yellow: %s" % [i, selected])
		probed += 1
		if probed >= 4:
			break
	await _restore()
	assert_true(probed >= 4, "there were edges away from the grid, found %d" % probed)


# Just outside a convex vertex, along the bisector of the corner, half a dot
# radius off: a dot covers it and the outline does not reach it, since the
# nearest point of either edge is the vertex itself.
func test_a_selected_polygon_has_no_dots_except_in_the_vertex_tool() -> void:
	var feature := await _load_with_raster("craton.middle-earth", "Old Shield")
	if feature == null:
		return
	var ring := _world_ring(feature)
	var clockwise := _signed_area(ring) < 0.0
	view().set_zoom(POLYGON_ZOOM)
	var offset := rad_to_deg(2.0 * asin(DOT_RADIUS * 0.5)) * 0.45
	var probed := 0
	for i in ring.size():
		var at: Variant = _outside_corner(ring, i, clockwise, offset)
		if at == null or _near_grid(at):
			continue
		await look_at_latlon(at.x, at.y)
		var screen: Variant = view().latlon_to_screen(at.x, at.y)
		if screen == null:
			continue
		_select(feature)
		app.set_active_tool(Application.Tool.MOVE)
		await frames(2)
		var moving := _count(await capture(), screen, 1)
		app.set_active_tool(Application.Tool.VERTEX)
		await frames(2)
		var editing := _count(await capture(), screen, 1)
		assert_eq(moving["yellow"], 0,
			"in the Move tool no dot sits on the vertex %d: %s" % [i, moving])
		assert_true(editing["yellow"] >= 7,
			"in the Vertex tool the dot on the vertex %d is back: %s" % [i, editing])
		probed += 1
		if probed >= 3:
			break
	await _restore()
	assert_true(probed >= 3, "there were convex vertices away from the grid, found %d" % probed)


func test_a_selected_line_is_drawn_thicker_and_yellow() -> void:
	var feature := await _load_with_raster("mixed_geometry.middle-earth", "Blue Ridge")
	if feature == null:
		return
	# Blue Ridge runs along the meridian at 40 degrees east. At latitude 5 the
	# distance from it to a point further east is sin(dlon) cos(lat), so this
	# point is half a width past where the unselected line ends and well inside
	# the selected one, which is twice as wide.
	var lat := 5.0
	var beside := 40.0 + rad_to_deg(asin(LINE_WIDTH * 1.375 / cos(deg_to_rad(lat))))
	await look_at_latlon(lat, 40.0)
	view().set_zoom(LINE_ZOOM)
	await frames(2)
	var on: Variant = view().latlon_to_screen(lat, 40.0)
	var off: Variant = view().latlon_to_screen(lat, beside)
	assert_true(on != null and off != null, "both probe points are in view")
	if on == null or off == null:
		await _restore()
		return

	_select(null)
	await frames(2)
	var plain := await capture()
	_select(feature)
	await frames(2)
	var selected := await capture()
	app.set_active_tool(Application.Tool.VERTEX)
	await frames(2)
	var editing := await capture()
	await _restore()

	assert_true(_count(plain, on, 1)["blue"] == 9,
		"unselected, the line is its own blue: %s" % _count(plain, on, 1))
	assert_true(_count(plain, off, 1)["red"] == 9,
		"unselected, the raster shows just outside it: %s" % _count(plain, off, 1))
	assert_true(_count(selected, on, 1)["yellow"] == 9,
		"selected, the line is yellow: %s" % _count(selected, on, 1))
	assert_true(_count(selected, off, 1)["yellow"] == 9,
		"selected, it is yellow past the unselected width: %s" % _count(selected, off, 1))
	assert_true(_count(editing, off, 1)["red"] == 9,
		"in the Vertex tool the line is not thickened: %s" % _count(editing, off, 1))


func test_a_selected_multipoint_keeps_its_markers_drawn_larger() -> void:
	var feature := await _load_with_raster(
		"mixed_geometry.middle-earth", "Green Stations", Color.BLUE)
	if feature == null:
		return
	await look_at_latlon(-30.0, -30.0)
	view().set_zoom(LINE_ZOOM)
	await frames(2)
	var marker: Variant = view().latlon_to_screen(-30.0, -30.0)
	if marker == null:
		fail("the marker at (-30, -30) is in view")
		await _restore()
		return
	_select(null)
	await frames(2)
	var plain := _count(await capture(), marker, 25)
	_select(feature)
	app.set_active_tool(Application.Tool.MOVE)
	await frames(2)
	var selected := _count(await capture(), marker, 25)
	app.set_active_tool(Application.Tool.VERTEX)
	await frames(2)
	var editing := _count(await capture(), marker, 25)
	await _restore()

	assert_eq(plain["yellow"], 0, "unselected, the marker carries no yellow: %s" % plain)
	assert_true(editing["yellow"] > 0, "in the Vertex tool the marker has its dot: %s" % editing)
	assert_true(selected["yellow"] > 2 * editing["yellow"],
		"selected, the marker is drawn larger than the Vertex tool's dot: %d against %d"
			% [selected["yellow"], editing["yellow"]])


# GP-0075: with View > Highlight children on, selecting a feature traces its
# children in orange, next to its own yellow, and tints their rows.
func test_a_polygon_following_the_selection_is_traced_orange() -> void:
	var parent := await _load_with_raster("two_cratons.middle-earth", "Red Triangle", Color.BLACK)
	var child := _find("Blue Quad")
	if parent == null or child == null:
		return
	assert_eq(app.document.couple(child, parent, app.document.current_time), "")
	app.refresh_geometry()
	view().set_zoom(POLYGON_ZOOM)
	var child_edge := await _edge_probe(child)
	var parent_edge := await _edge_probe(parent)
	if child_edge.is_empty() or parent_edge.is_empty():
		fail("both features have an edge away from the grid")
		await _restore()
		return

	_select(parent)
	var off_child := await _count_at(child_edge)
	_toggle_children()
	var on_child := await _count_at(child_edge)
	var on_parent := await _count_at(parent_edge)
	var tint := _row(child).get_custom_bg_color(0)
	_toggle_children()
	var tint_after := _row(child).get_custom_bg_color(0)
	await _restore()

	assert_true(off_child["orange"] == 0 and off_child["blue"] > 0,
		"switched off, the child's edge is its own blue: %s" % off_child)
	assert_true(on_child["orange"] > 0 and on_child["yellow"] == 0,
		"switched on, the child's edge is orange: %s" % on_child)
	assert_true(on_parent["yellow"] > 0,
		"and the selected parent's edge is yellow: %s" % on_parent)
	assert_eq(tint, FeatureTree.CHILD_TINT, "the child's row is tinted")
	assert_true(tint_after != FeatureTree.CHILD_TINT, "and loses the tint when switched off")


func test_a_line_following_the_selection_is_drawn_orange_at_its_width() -> void:
	var parent := await _load_with_raster("mixed_geometry.middle-earth", "Red Triangle")
	var child := _find("Blue Ridge")
	if parent == null or child == null:
		return
	assert_eq(app.document.couple(child, parent, app.document.current_time), "")
	app.refresh_geometry()
	# Blue Ridge runs along the meridian at 40 degrees east; see
	# test_a_selected_line_is_drawn_thicker_and_yellow for the point beside it.
	var lat := 5.0
	var beside := 40.0 + rad_to_deg(asin(LINE_WIDTH * 1.375 / cos(deg_to_rad(lat))))
	await look_at_latlon(lat, 40.0)
	view().set_zoom(LINE_ZOOM)
	await frames(2)
	var on: Variant = view().latlon_to_screen(lat, 40.0)
	var off: Variant = view().latlon_to_screen(lat, beside)
	if on == null or off == null:
		fail("both probe points are in view")
		await _restore()
		return
	_select(parent)
	_toggle_children()
	await frames(2)
	var image := await capture()
	_toggle_children()
	await _restore()
	assert_eq(_count(image, on, 1)["orange"], 9,
		"the child's line is orange: %s" % _count(image, on, 1))
	assert_eq(_count(image, off, 1)["red"], 9,
		"and no wider than before: %s" % _count(image, off, 1))


# GP-0090: the switch was saved as highlight_riders before it was renamed. A
# config holding only that key starts with the switch on, and the next save
# writes the new key.
func test_a_config_with_the_old_key_keeps_the_highlight_on() -> void:
	var item: int = app.view_menu.get_item_index(Application.ViewItem.HIGHLIGHT_CHILDREN)
	Config.clear()
	Config.set_value("highlight_riders", true)
	Config.forget()
	app._restore_session()
	var checked: bool = app.view_menu.is_item_checked(item)
	var on: bool = app.highlight_children
	app._save_session()
	var saved: Variant = Config.get_value(Application.HIGHLIGHT_CHILDREN_KEY)

	Config.clear()
	app.highlight_children = false
	app._update_view_menu_checks()
	await frames(2)
	assert_true(on and checked, "the old key switches the highlight on and checks the item")
	assert_eq(saved, true, "and the session saves it under the new key")


### Helpers

# Load a sample over a flat raster. Red by default; a green feature needs
# another, since the blend of green into red along its edge reads as yellow.
func _load_with_raster(sample: String, title: String, raster := Color.RED) -> Feature:
	await load_sample(sample)
	app.set_active_tool(Application.Tool.MOVE)
	var flat := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	flat.fill(raster)
	view().planet.set_raster(ImageTexture.create_from_image(flat), 1.0)
	var feature := _find(title)
	assert_true(feature != null, "the sample holds %s" % title)
	return feature


# The View menu's Highlight children switch, flipped the way a click does it.
func _toggle_children() -> void:
	app._on_view_menu_id_pressed(Application.ViewItem.HIGHLIGHT_CHILDREN)


func _row(feature: Feature) -> TreeItem:
	return app.features.feature_tree.items[feature.pnid]


# A point on an edge of a feature away from the grid, as the place to turn the
# globe to, or an empty array. The samples put many edges on grid lines, so a
# few places along each edge are tried.
func _edge_probe(feature: Feature) -> Array:
	var ring := _world_ring(feature)
	for i in ring.size():
		for along in [0.5, 0.3, 0.7]:
			var point := Measure.along(ring[i], ring[(i + 1) % ring.size()], along)
			if not _near_grid(point):
				return [point]
	return []


# Turn to a probe from _edge_probe() and count the colors around it.
func _count_at(edge: Array) -> Dictionary:
	var middle: Vector2 = edge[0]
	await look_at_latlon(middle.x, middle.y)
	await frames(2)
	var centre: Variant = view().latlon_to_screen(middle.x, middle.y)
	if centre == null:
		return {"yellow": 0, "orange": 0, "red": 0, "green": 0, "blue": 0}
	return _count(await capture(), centre, EDGE_REACH)


func _restore() -> void:
	app.set_active_tool(Application.Tool.MOVE)
	view().set_zoom(PlanetView.DEFAULT_ZOOM)
	view().planet.set_raster(null, 0.0)
	await frames(2)


# Select a feature, or the root group for null, which highlights nothing.
func _select(feature: Feature) -> void:
	if feature == null:
		app.features.feature_tree.select_root()
	else:
		app.features.feature_tree.select_node(feature)


func _world_ring(feature: Feature) -> PackedVector2Array:
	return Feature.apply_basis(feature.rings[0],
		Feature.world_basis(app.features.root, feature, app.document.current_time))


# Twice the area of a ring in the (longitude, latitude) plane, positive when it
# runs anticlockwise there.
func _signed_area(ring: PackedVector2Array) -> float:
	var area := 0.0
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		area += a.y * b.x - b.y * a.x
	return area


# A point a small angle outside a convex vertex, along the bisector of its
# corner, or null for a concave vertex or one with a short edge beside it.
func _outside_corner(ring: PackedVector2Array, i: int, clockwise: bool, offset: float) -> Variant:
	var v := ring[i]
	var to_prev := ring[(i - 1 + ring.size()) % ring.size()] - v
	var to_next := ring[(i + 1) % ring.size()] - v
	if to_prev.length() < 2.0 or to_next.length() < 2.0:
		return null
	# The vectors are (lat, lon) and point away from the vertex, so this comes
	# out positive at a convex vertex of a ring running anticlockwise in the
	# (longitude, latitude) plane, and negative at one of a clockwise ring.
	var turn := to_prev.x * to_next.y - to_prev.y * to_next.x
	if (turn > 0.0) == clockwise:
		return null
	var outwards := -(to_prev.normalized() + to_next.normalized())
	if outwards.length() < 0.2:
		return null
	return v + outwards.normalized() * offset


# The grid runs along every fifteenth degree of latitude and longitude.
func _near_grid(point: Vector2) -> bool:
	for value in [point.x, point.y]:
		if absf(value - roundf(value / 15.0) * 15.0) < 1.5:
			return true
	return false


# How many pixels of a square around a point are yellow, how many are the child
# orange, and how many each channel dominates.
func _count(image: Image, centre: Vector2, reach: int) -> Dictionary:
	var counts := {"yellow": 0, "orange": 0, "red": 0, "green": 0, "blue": 0}
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var color := image.get_pixel(int(centre.x) + dx, int(centre.y) + dy)
			if color.r > 0.5 and color.g > 0.5 and color.b < color.r * 0.5:
				counts["yellow"] += 1
				continue
			if color.r > 0.6 and color.g > color.r * 0.3 and color.g < color.r * 0.7 					and color.b < color.r * 0.25:
				counts["orange"] += 1
				continue
			var channel := dominant_channel(color)
			if counts.has(channel):
				counts[channel] += 1
	return counts


func _find(title: String) -> Feature:
	var stack: Array[Feature] = [app.features.root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if node.title == title:
			return node
		stack.append_array(node.children)
	return null
