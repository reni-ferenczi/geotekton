extends RenderedCase

# The parts of the Vertex tool that need the real window: snapping, which works
# in pixels and so needs a camera to project through, and the two preferences
# that change how large the outline overlay is drawn.
#
# What a click and a drag do is scripted through the automation port instead,
# in run_vertex_session of Tests/session.py, so that the events are the ones a
# pointer really sends.

# Two triangles well apart, so their vertices are far enough apart on screen
# that a snap has to be asked for rather than happening by accident.
#
# Plain constants rather than a static var holding a PackedVector2Array: a
# static variable in a rendered test leaks objects and resources on the way out,
# long after every test has passed, and crashed the engine outright before
# Godot 4.7.2. See Docs/Testing.md and GP-0025.
const FIRST := [Vector2(-8, -8), Vector2(8, -8), Vector2(0, 8)]
const SECOND := [Vector2(-8, 30), Vector2(8, 30), Vector2(0, 46)]


func test_a_vertex_snaps_onto_one_of_another_feature() -> void:
	var mover := await _two_features()
	if mover == null:
		return

	# Take hold of the first vertex of the mover, then ask where a point a few
	# pixels from the other feature's first vertex would snap to.
	var target: Vector2 = _world(_other(mover).rings[0][0], _other(mover))
	var screen: Variant = app.planet_view.latlon_to_screen(target.x, target.y)
	assert_true(screen != null, "the target vertex is on the visible hemisphere")
	if screen == null:
		return

	_hold_first_vertex(mover)
	var near: Variant = app._snap_target(mover, screen + Vector2(6.0, 0.0))
	assert_true(near != null, "a point six pixels away snaps")
	if near != null:
		assert_close(near, target, 1e-3, "onto the other feature's vertex")

	var far: Variant = app._snap_target(mover, screen + Vector2(60.0, 0.0))
	assert_eq(far, null, "and a point sixty pixels away snaps to nothing")
	_let_go()


func test_snapping_tells_two_candidates_apart() -> void:
	var mover := await _two_features()
	if mover == null:
		return
	var other := _other(mover)
	var first: Vector2 = _world(other.rings[0][0], other)
	var second: Vector2 = _world(other.rings[0][1], other)
	var a: Variant = app.planet_view.latlon_to_screen(first.x, first.y)
	var b: Variant = app.planet_view.latlon_to_screen(second.x, second.y)
	assert_true(a != null and b != null, "both target vertices are visible")
	if a == null or b == null:
		return
	assert_true((a as Vector2).distance_to(b as Vector2) > 4.0 * Application.SNAP_PIXELS,
		"the two are far enough apart that only one can be in reach at a time")

	_hold_first_vertex(mover)
	var near_first: Variant = app._snap_target(mover, (a as Vector2) + Vector2(4.0, 0.0))
	assert_true(near_first != null, "a point four pixels from the first snaps")
	if near_first != null:
		assert_close(near_first, first, 1e-3, "onto that one")

	var near_second: Variant = app._snap_target(mover, (b as Vector2) + Vector2(0.0, 4.0))
	assert_true(near_second != null, "and a point four pixels from the second snaps")
	if near_second != null:
		assert_close(near_second, second, 1e-3, "onto that one instead")

	var between: Variant = app._snap_target(mover, (a as Vector2).lerp(b as Vector2, 0.5))
	assert_eq(between, null, "while halfway between them is in reach of neither")
	_let_go()


func test_the_vertex_being_dragged_is_not_a_candidate() -> void:
	var mover := await _two_features()
	if mover == null:
		return
	var held: Vector2 = _world(mover.rings[0][0], mover)
	var screen: Variant = app.planet_view.latlon_to_screen(held.x, held.y)
	assert_true(screen != null, "the held vertex is visible")
	if screen == null:
		return

	_hold_first_vertex(mover)
	var picked: Variant = app._snap_target(mover, screen)
	# Its own second and third vertices are far away, and itself is left out, so
	# nothing is near enough. A vertex that could snap to itself would never move.
	assert_eq(picked, null, "a vertex does not snap to where it already is")
	_let_go()


func test_the_vertex_marker_preference_changes_what_is_drawn() -> void:
	var reach := await _outline_reach(true)
	if reach.is_empty():
		return
	assert_true(reach[1] > reach[0],
		"a larger vertex marker reaches further: %d pixels at four times the size, %d at one"
			% [reach[1], reach[0]])


func test_the_line_width_preference_changes_what_is_drawn() -> void:
	var reach := await _outline_reach(false)
	if reach.is_empty():
		return
	assert_true(reach[1] > reach[0],
		"a wider outline line reaches further: %d pixels at four times the size, %d at one"
			% [reach[1], reach[0]])


### Helpers

# How far the outline overlay reaches, in pixels, at the usual size and at four
# times it. With marker true it is measured outwards from a vertex, otherwise
# sideways from the middle of an edge; either way the direction points away from
# the shape, where nothing else of the outline is in the way.
#
# Returns [at one, at four], or an empty array when the setup could not be made.
func _outline_reach(marker: bool) -> Array[int]:
	var empty: Array[int] = []
	await load_sample("triangle.geotekt")
	var feature := _find("Red Triangle")
	assert_true(feature != null, "the sample holds the Red Triangle")
	if feature == null:
		return empty
	app.features.feature_tree.select_node(feature)
	# The dots on the vertices are drawn in the Vertex tool alone; see GP-0034.
	app.set_active_tool(Application.Tool.VERTEX)
	await frames(2)

	var ring: PackedVector2Array = feature.rings[0]
	var middle := Vector2(0.0, 0.0)
	for vertex in ring:
		middle += vertex
	middle /= float(ring.size())

	var at := _world(ring[0], feature) if marker else _world((ring[0] + ring[1]) * 0.5, feature)
	await look_at_latlon(at.x, at.y)
	var from: Variant = app.planet_view.latlon_to_screen(at.x, at.y)
	var inside: Variant = app.planet_view.latlon_to_screen(
		_world(middle, feature).x, _world(middle, feature).y)
	assert_true(from != null and inside != null, "the probe point and the middle are visible")
	if from == null or inside == null:
		return empty

	var outwards := (inside as Vector2).direction_to(from as Vector2)
	var measured: Array[int] = []
	for scale in [1.0, Config.MAX_SCALE]:
		if marker:
			Config.set_vertex_marker_scale(scale)
		else:
			Config.set_line_width_scale(scale)
		app._apply_outline_scale()
		await frames(2)
		measured.append(_outline_reach_in(await capture(), from as Vector2, outwards))
	Config.set_vertex_marker_scale(1.0)
	Config.set_line_width_scale(1.0)
	app._apply_outline_scale()
	app.set_active_tool(Application.Tool.MOVE)
	await frames(2)
	return measured


# The furthest whole pixel along a direction that is still drawn in the outline
# colour, starting from a point that is on the outline itself. One captured
# frame is read sixty times rather than sixty frames captured once each.
func _outline_reach_in(image: Image, from: Vector2, direction: Vector2) -> int:
	var reach := 0
	for step in range(1, 60):
		var at := from + direction * float(step)
		if at.x < 0.0 or at.y < 0.0 or at.x >= image.get_width() or at.y >= image.get_height():
			break
		if not _is_outline(image.get_pixel(int(at.x), int(at.y))):
			break
		reach = step
	return reach



# Pretend the tool has taken hold of the feature's first vertex, which is what
# a press on it does, without going through the pointer.
func _hold_first_vertex(feature: Feature) -> void:
	app.selected_vertex = Vector2i(0, 0)
	app.vertex_drag = Vector2i(0, 0)
	app.vertex_drag_feature = feature
	app.vertex_drag_was = feature.rings[0][0]


# Let the held vertex go, so the tool starts the next test with nothing in hand.
func _let_go() -> void:
	app.vertex_drag = Application.NO_VERTEX
	app.vertex_drag_feature = null
	app.selected_vertex = Application.NO_VERTEX


# Two features side by side, with the second selected and the Vertex tool on it.
# Returns the selected one, or null when the setup could not be made.
func _two_features() -> Feature:
	await load_sample("empty.middle-earth")
	app.planet_view.planet.lat = 0.0
	app.planet_view.planet.lon = 20.0
	await frames(2)

	var root: Feature = app.features.root
	for ring in [FIRST, SECOND]:
		var feature := Feature.create_feature("Blob %d" % (root.children.size() + 1))
		feature.add_ring(PackedVector2Array(ring), Feature.GeometryKind.POLYGON)
		root.children.append(feature)
	app.document.record()
	app.features.reload()
	app.refresh_geometry()
	await frames(2)

	var mover: Feature = root.children[1]
	app.features.feature_tree.select_node(mover)
	app.set_active_tool(Application.Tool.VERTEX)
	await frames(2)
	assert_true(app.active_tool == Application.Tool.VERTEX, "the Vertex tool is on")
	return mover if app.active_tool == Application.Tool.VERTEX else null


func _other(mover: Feature) -> Feature:
	for child in app.features.root.children:
		if child != mover:
			return child
	return null


# Where a stored vertex of a feature sits on the globe at the current time.
func _world(vertex: Vector2, feature: Feature) -> Vector2:
	var m := Feature.world_basis(app.features.root, feature, app.document.current_time)
	return Feature.apply_basis(PackedVector2Array([vertex]), m)[0]


func _find(title: String) -> Feature:
	var stack: Array[Feature] = [app.features.root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if node.title == title:
			return node
		stack.append_array(node.children)
	return null


# The outline overlay is white: opaque on the vertex markers, and laid over the
# polygon's edges at 60 percent in linear light, which lifts every channel to
# 0.8 or more. No part of the Earth texture near the triangle comes that close
# to white.
func _is_outline(color: Color) -> bool:
	return minf(color.r, minf(color.g, color.b)) > 0.75
