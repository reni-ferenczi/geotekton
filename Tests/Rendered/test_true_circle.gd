extends RenderedCase

# GP-0100: a circle is drawn as the curve it is, not as the chords between the
# vertices of its ring. A coarse circle leaves each chord well inside the curve
# halfway between two vertices, so a probe there tells the two apart: the curve
# is the circle's color and the middle of the chord is the planet. The circle
# crosses the date line and reaches 80 degrees north, which the map
# projections must draw with no special case.
#
# The planet wears a flat red raster and the circle is blue, so a probe says
# what it found by the dominant channel.

# Six segments of 30 degrees leave the chord 3.4 degrees inside the curve.
const AXIS := Vector2(50.0, 175.0)
const RADIUS := 30.0
const SEGMENTS := 6
const ZOOM := 8.0
const PREVIEW_ZOOM := 24.0
const HALO_ZOOM := 40.0

# The shader's geometry_line_width, and what a circle draws at against it
# (Feature.CIRCLE_LINE_SCALE) and how much wider the halo is
# (SELECTED_LINE_SCALE). test_shader_defaults.gd and test_shader_constants.gd
# hold them to the shader.
const LINE_WIDTH := 0.012
const HALO_SCALE := 1.25

const PROJECTIONS := [MapProjection.Kind.MOLLWEIDE, MapProjection.Kind.RECTANGULAR]


func test_the_curve_is_drawn_between_the_vertices_on_the_globe_and_the_maps() -> void:
	var circle := await _build()
	var probes := _probes(circle)
	for kind in [null] + PROJECTIONS:
		var view_name := "the globe"
		if kind != null:
			view().planet.show_map = true
			view().planet.projection = kind
			view_name = MapProjection.name_of(kind)
		for middle in probes:
			await _check_at(middle[0], "blue", "%s: the curve between two vertices" % view_name)
			await _check_at(middle[1], "red", "%s: the middle of the chord" % view_name)
	await _restore()


# Selected, the circle keeps its color over a white halo a quarter wider than
# itself. The halo is solid only just outside the line, 5 % of a width past its
# edge, which is several pixels at HALO_ZOOM; that is white where it was red.
func test_a_selected_circle_has_a_halo_along_the_curve() -> void:
	var circle := await _build()
	var width := LINE_WIDTH * circle.line_scale()
	var probes := _probes(circle)
	var beside := _off_curve(probes[0][0], width * 1.05)
	view().set_zoom(HALO_ZOOM)
	await _check_at(beside, "red", "unselected, just outside the curve")
	app.features.feature_tree.select_node(circle)
	await _check_at(beside, "", "selected, the halo just outside the curve")
	await _check_at(probes[0][0], "blue", "selected, the curve itself")
	for kind in PROJECTIONS:
		view().planet.show_map = true
		view().planet.projection = kind
		await _check_at(beside, "", "selected, the halo on %s" % MapProjection.name_of(kind))
	await _restore()


# The Draw tool previews the circle through the outline overlay with the same
# test, so the white preview lies on the curve and not on the chord.
func test_the_drawing_preview_is_the_curve() -> void:
	var circle := await _build()
	var probes := _probes(circle)
	var empty := Feature.create_feature("Empty")
	app.features.root.children.append(empty)
	assert_eq(app.document.set_feature_type(empty, FeatureType.CIRCLE), "", "a circle to draw")
	app.features.reload()
	app.refresh_geometry()
	app.features.feature_tree.select_node(empty)
	app.set_active_tool(Application.Tool.DRAW)
	# As coarse as the circle, so a preview of chords would miss the curve.
	var segments: float = app.segments_spin.value
	app.segments_spin.value = SEGMENTS
	app._place_point(AXIS)
	app._place_point(circle.rings[0][0])
	view().set_zoom(PREVIEW_ZOOM)
	# The circle feature under the preview is hidden, so only the overlay is seen.
	circle.enabled = false
	app.refresh_geometry()
	app._refresh_outline()
	await _check_at(probes[0][0], "", "the preview on the curve")
	await _check_at(probes[0][1], "red", "no preview on the chord")
	app.set_active_tool(Application.Tool.MOVE)
	app.segments_spin.value = segments
	circle.enabled = true
	await _restore()


### Helpers


func _build() -> Feature:
	await load_sample("empty.geotekt")
	var flat := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	flat.fill(Color.RED)
	view().planet.set_raster(ImageTexture.create_from_image(flat), 1.0)
	var document: Document = app.document
	var circle := Feature.create_feature("Circle")
	app.features.root.children.append(circle)
	assert_eq(document.set_feature_type(circle, FeatureType.CIRCLE), "", "a circle")
	assert_eq(document.set_circle(circle, AXIS, RADIUS, SEGMENTS, false), "", "a coarse one")
	document.set_color(circle, Color.BLUE)
	app.features.reload()
	app.refresh_geometry()
	app.features.feature_tree.select_root()
	app._on_craton_hovered(NAN, NAN)
	view().set_zoom(ZOOM)
	await frames(2)
	return circle


# For the chords that do not touch a grid line, the point of the curve halfway
# between the two vertices and the middle of the chord, both as (lat, lon).
func _probes(circle: Feature) -> Array:
	var axis := Measure._to_unit(AXIS)
	var ring := circle.rings[0]
	var result := []
	for i in range(ring.size() - 1):
		var chord := (Measure._to_unit(ring[i]) + Measure._to_unit(ring[i + 1])).normalized()
		var out := (chord - axis * axis.dot(chord)).normalized()
		var curve := axis * cos(deg_to_rad(RADIUS)) + out * sin(deg_to_rad(RADIUS))
		var pair := [Measure._to_latlon(curve), Measure._to_latlon(chord)]
		if not (_near_grid(pair[0]) or _near_grid(pair[1])):
			result.append(pair)
	assert_true(result.size() >= 4, "there are chords away from the grid: %d" % result.size())
	return result


# The grid is drawn every fifteen degrees, and at the pole every meridian meets.
func _near_grid(point: Vector2) -> bool:
	var near := func(value: float) -> bool:
		return absf(value - roundf(value / 15.0) * 15.0) < 1.0
	return near.call(point.x) or near.call(point.y) or absf(point.x) > 85.0


# The point a chord `distance` away from a point of the curve, away from the axis.
func _off_curve(point: Vector2, distance: float) -> Vector2:
	var axis := Measure._to_unit(AXIS)
	var p := Measure._to_unit(point)
	var out := (p - axis * axis.dot(p)).normalized()
	var turned := p.rotated(axis.cross(p).normalized(), asin(distance))
	assert_true(turned.dot(out) > p.dot(out), "the probe moves away from the axis")
	return Measure._to_latlon(turned)


# Turn to a point and hold the dominant channel of the 3 by 3 square around it
# to what is wanted: the globe is a tessellated mesh, so a place can land a
# pixel off where it is computed to be.
func _check_at(point: Vector2, wanted: String, what: String) -> void:
	await look_at_latlon(point.x, point.y)
	var at: Variant = view().latlon_to_screen(point.x, point.y)
	if at == null:
		fail("%s is in view" % what)
		return
	var image := await capture()
	var centre: Vector2 = at
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var color := image.get_pixel(int(centre.x) + dx, int(centre.y) + dy)
			var found := dominant_channel(color)
			if found != wanted:
				fail("%s at %s: the pixel %s off is %s (%s), not %s"
					% [what, point, Vector2(dx, dy), found, color, wanted if wanted else "none"])
				return


func _restore() -> void:
	view().planet.show_map = false
	view().planet.projection = MapProjection.Kind.RECTANGULAR
	app.features.feature_tree.select_root()
	view().set_zoom(PlanetView.DEFAULT_ZOOM)
	view().planet.set_raster(null, 0.0)
	view().planet.lat = 0.0
	view().planet.lon = 0.0
	await frames(2)
