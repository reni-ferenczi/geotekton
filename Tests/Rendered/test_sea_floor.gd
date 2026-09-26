extends RenderedCase

# GP-0123: the ridge and crusts a split leaves have no row in the feature tree.
# They are still selected, from the globe or by name, edited and deleted, and they
# draw under every feature the tree shows.
#
# A square split west from east at 100 Ma with Ridge and Crust on, the halves
# carried apart by the present so the crusts have bands to click and to cover.


func _split_square() -> void:
	var document: Document = app.document
	document.reset()
	var square := Feature.create_feature("Square")
	square.add_ring(PackedVector2Array([Vector2(-10, -10), Vector2(-10, 10),
		Vector2(10, 10), Vector2(10, -10)]), Feature.GeometryKind.POLYGON)
	document.root.children.append(square)
	document.current_time = 100.0
	document.record()
	assert_eq(document.split_feature_along(square, 0,
		PackedVector2Array([Vector2(-11, 0), Vector2(0, 2), Vector2(11, 0)]), true, true), "")
	for index in [0, 1]:
		var half: Feature = document.root.children[index]
		var west := _middle(half.rings[0]).y < 0.0
		assert_eq(document.set_keyframe(half, 100.0, Vector3.ZERO), "")
		assert_eq(document.set_keyframe(half, 0.0,
			Vector3(20, 0, 0) if west else Vector3(-20, 0, 0)), "")
	for crust in _crusts():
		assert_eq(document.set_crust_step(crust, 25.0), "")
	document.set_time(0.0)
	app.features.reload()
	app._on_craton_hovered(NAN, NAN)
	app.refresh_geometry()
	await frames(2)


func _crusts() -> Array[Feature]:
	var found: Array[Feature] = []
	for node in app.document.root.children:
		if node.is_crust():
			found.append(node)
	return found


func _titled(title: String) -> Feature:
	for node in app.document.root.children:
		if node.title == title:
			return node
	return null


func _middle(ring: PackedVector2Array) -> Vector2:
	return GeometryEdit.sphere_middle(ring)


# The middle of the crust's oldest band, where it stands in the world.
func _band_middle(crust: Feature) -> Vector2:
	var basis := Feature.world_basis(app.document.root, crust, app.document.current_time)
	return Feature.apply_basis(PackedVector2Array([_middle(crust.rings[0])]), basis)[0]


func _screen(at: Vector2) -> Variant:
	await look_at_latlon(at.x, at.y)
	var screen: Variant = view().latlon_to_screen(at.x, at.y)
	assert_true(screen != null, "%s must be visible" % at)
	return screen


func test_the_tree_shows_the_halves_and_not_the_sea_floor() -> void:
	await _split_square()
	var tree: FeatureTree = app.features.feature_tree
	for title in ["Square", "Square 2"]:
		assert_true(tree.items.has(_titled(title).pnid), "%s has a row" % title)
	for title in ["Square ridge", "Square crust", "Square 2 crust"]:
		var node := _titled(title)
		assert_true(node != null, "%s is in the document" % title)
		assert_true(not tree.items.has(node.pnid), "%s has no row" % title)
	assert_eq(tree.sea_floor.size(), 3, "the tree knows the three")


func test_a_crust_is_selected_without_a_row() -> void:
	await _split_square()
	var tree: FeatureTree = app.features.feature_tree
	var crust := _titled("Square crust")
	tree.select_node(crust)
	await frames(2)
	assert_eq(tree.get_selected_node(), crust, "the crust is the selection")
	assert_eq(tree.get_selected(), null, "and no row is selected")
	assert_eq(app.properties.node, crust, "the Properties panel shows it")

	app._update_edit_menu()
	var menu: PopupMenu = app.edit_menu
	for item in [Application.EditItem.CUT, Application.EditItem.COPY,
			Application.EditItem.DUPLICATE]:
		assert_true(menu.is_item_disabled(menu.get_item_index(item)),
			"%s is refused" % Application.EditItem.keys()[item])
	assert_true(not menu.is_item_disabled(menu.get_item_index(Application.EditItem.DELETE)),
		"Delete is offered")

	tree.select_node(_titled("Square 2"))
	await frames(2)
	assert_eq(tree.get_selected_node(), _titled("Square 2"), "a row takes the selection back")


func test_a_crust_is_deleted_to_its_half_and_undo_brings_it_back() -> void:
	await _split_square()
	var tree: FeatureTree = app.features.feature_tree
	var crust := _titled("Square crust")
	var half: Feature = app.document.root.get_node_by_uuid(crust.crust_half)
	tree.select_node(crust)
	await frames(2)
	app._on_edit_menu_id_pressed(Application.EditItem.DELETE)
	await frames(2)
	assert_eq(_titled("Square crust"), null, "the crust is gone")
	assert_eq(tree.get_selected_node(), _titled(half.title), "and its half is selected")
	app.undo()
	await frames(2)
	assert_true(_titled("Square crust") != null, "undo brings it back")
	assert_eq(tree.sea_floor.size(), 3, "still without a row")


func test_clicking_a_band_selects_the_crust() -> void:
	await _split_square()
	var crust := _titled("Square 2 crust")
	var screen: Variant = await _screen(_band_middle(crust))
	if screen == null:
		return
	await click(screen)
	assert_eq(app.features.feature_tree.get_selected_node(), crust, "the band's crust")


# A feature drawn over a band hides it, even with the crust at the top of the
# tree, where any other feature would be drawn over everything.
func test_a_band_under_another_polygon_draws_as_the_polygon() -> void:
	await _split_square()
	var root: Feature = app.document.root
	var crust := _titled("Square crust")
	var at := _band_middle(crust)
	var cover := Feature.create_feature("Cover", Color(1, 0, 0, 1))
	cover.add_ring(PackedVector2Array([at + Vector2(-0.5, -0.5), at + Vector2(-0.5, 0.5),
		at + Vector2(0.5, 0.5), at + Vector2(0.5, -0.5)]), Feature.GeometryKind.POLYGON)
	root.children.erase(crust)
	root.children.push_front(crust)
	root.children.append(cover)
	app.features.reload()
	app.refresh_geometry()
	await frames(2)
	var screen: Variant = await _screen(at)
	if screen == null:
		return
	var color := await probe(screen)
	assert_eq(dominant_channel(color), "red", "the cover, not the band: %s" % color)


### Colors (GP-0127)


# How far a probed pixel may be from the colour it was meant to be, in sRGB.
const COLOR_TOLERANCE := 0.03


# A point inside the k-th band of the crust, where it stands in the world:
# halfway between the first stretch of its older isochron and the same stretch
# of its younger one, away from the flowlines.
func _inside_band(crust: Feature, k: int) -> Vector2:
	var band: PackedVector2Array = crust.rings[k]
	var older := (band[0] + band[1]) * 0.5
	var younger := (band[band.size() - 1] + band[band.size() - 2]) * 0.5
	var basis := Feature.world_basis(app.document.root, crust, app.document.current_time)
	return Feature.apply_basis(PackedVector2Array([(older + younger) * 0.5]), basis)[0]


func _assert_color(at: Vector2, expected: Color, tolerance: float, what: String) -> void:
	var screen: Variant = await _screen(at)
	if screen == null:
		return
	var color := await probe(screen)
	var off := maxf(maxf(absf(color.r - expected.r), absf(color.g - expected.g)),
		absf(color.b - expected.b))
	assert_true(off <= tolerance, "%s at %s reads %s, not %s" % [what, at, color, expected])


# Each band is drawn in the palette's color at its age, spread over the oldest
# crust in the document: 100 My here, at the dark end of Blue or the violet
# end of Rainbow.
func test_a_crust_draws_band_by_band_in_blue_and_in_rainbow() -> void:
	await _split_square()
	var crust := _titled("Square crust")
	assert_eq(Array(crust.band_ages), [100.0, 75.0, 50.0, 25.0], "four bands")
	for palette in ["blue", "rainbow"]:
		app.document.view.crust_palette = palette
		app.refresh_geometry()
		await frames(2)
		for k in 4:
			var expected := Palette.built_in(palette).color_at(10.0 * crust.band_ages[k])
			await _assert_color(_inside_band(crust, k), expected, COLOR_TOLERANCE,
				"band %d in %s" % [k, palette])
	app.document.view.crust_palette = ViewSettings.DEFAULT_CRUST_PALETTE


func test_a_changed_ridge_color_draws_the_ridge_in_it() -> void:
	await _split_square()
	var ridge := _titled("Square ridge")
	var yellow := Color(1.0, 1.0, 0.0)
	app.document.view.ridge_color = yellow
	app.refresh_geometry()
	await frames(2)
	var on := (ridge.rings[0][0] + ridge.rings[0][1]) * 0.5
	await _assert_color(on, yellow, 0.1, "the ridge")
	app.document.view.ridge_color = FeatureType.color(FeatureType.LINE)


### A triple junction (GP-0124)


# The eastern half cut at 50 Ma across its land and out across its crust to the
# ridge, one piece then turning away from the other: at 25 Ma the sea floor
# between the two pieces is crust, drawn, with the planet showing nowhere.
func test_a_triple_junction_draws_crust_between_the_pieces() -> void:
	await _split_square()
	var document: Document = app.document
	var east: Feature = null
	for title in ["Square", "Square 2"]:
		if _middle(_titled(title).rings[0]).y > 0.0:
			east = _titled(title)
	document.set_time(50.0)
	var basis := Feature.world_basis(document.root, east, 50.0)
	var land := Feature.apply_basis(east.rings[0], basis)
	var ridge := Ridge.ring_at(document.root, _titled("Square ridge"), 50.0)
	var coast := -INF
	var west := INF
	var far := INF
	for v in land:
		coast = maxf(coast, v.y)
		west = minf(west, v.y)
	for v in ridge:
		far = minf(far, v.y)
	var path := PackedVector2Array([Vector2(-4, coast + 2.0), Vector2(-4, west - 1.0),
		Vector2(2, (far + west) * 0.5), Vector2(5, far - 3.0)])
	assert_eq(document.split_feature_along(east, 0,
		Feature.apply_basis(path, basis.transposed()), true, true), "", "the cut is made")
	var moving := _titled(east.title + " 2") if _titled(east.title + " 2") != null else east
	assert_eq(document.set_keyframe(moving, 50.0, moving.rotation_at(50.0)), "")
	assert_eq(document.set_keyframe(moving, 0.0, moving.rotation_at(50.0) + Vector3(0, 0, 6)), "")
	for crust in _crusts():
		assert_eq(document.set_crust_step(crust, 25.0), "")
	document.set_time(25.0)
	app.features.reload()
	app.refresh_geometry()
	await frames(2)

	var young: Feature = null
	for node in document.root.children:
		if node.midway and node.time_range.y == 50:
			young = node
	assert_true(young != null, "the new ridge is there")
	var sides := [PackedVector2Array(), PackedVector2Array()]
	for entry: Dictionary in Topology.resolve(document.root, young, 25.0):
		sides[entry["side"]].append_array(entry["vertices"])
	var count: int = sides[0].size()
	for i in [1, count / 2, count - 2]:
		var at := Feature._xyz_to_latlon_s(Feature._latlon_to_xyz_s(sides[0][i]).slerp(
			Feature._latlon_to_xyz_s(sides[1][i]), 0.3))
		var screen: Variant = await _screen(at)
		if screen == null:
			continue
		var color := await probe(screen)
		var planet := ViewSettings.DEFAULT_PLANET_COLOR
		var off := maxf(maxf(absf(color.r - planet.r), absf(color.g - planet.g)),
			absf(color.b - planet.b))
		assert_true(off > COLOR_TOLERANCE, "sea floor is drawn at %s: %s" % [at, color])
