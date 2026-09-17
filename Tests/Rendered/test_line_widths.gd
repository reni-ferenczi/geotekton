extends RenderedCase

# GP-0096: a feature's lines are drawn at a width of its own, Feature.line_scale()
# times geometry_line_width. A hotspot track is thin and has a dot at every
# sample, a circle is half as wide as a line someone drew, and every other line
# keeps the full width.
#
# The planet wears a flat red raster and the features are blue, so a probe says
# whether a line reaches it by its dominant channel.

# The shader's geometry_line_width: the distance from a line's middle to its
# edge, as a chord. test_shader_defaults.gd holds it to the shader.
const LINE_WIDTH := 0.012
const ZOOM := 8.0

# A plate turning about the north pole from 30 Ma to 15 Ma and about another
# axis after that, so the track of a hotspot on it bends at the 15 Ma sample.
# The timeline's Skip is SKIP while the test runs, a sample every 5 My.
const HOTSPOT := Vector2(20.0, 60.0)
const PLATE_KEYS := [[0.0, Vector3(20.0, 20.0, 0.0)], [15.0, Vector3(20.0, 0.0, 0.0)],
	[30.0, Vector3.ZERO]]
const SKIP := 5.0

# A plain line and a circle, both well away from the track and the grid.
const LINE := [Vector2(-38.0, -52.0), Vector2(-22.0, -52.0)]
const CIRCLE_AXIS := Vector2(-35.0, 130.0)
const CIRCLE_RADIUS := 8.0


# 0.6 widths off its middle is inside a plain line and outside a hotspot track,
# whose edge is at 0.35 widths, and outside its halo when it is selected, at
# 0.35 * 1.25 widths. 0.2 widths is inside both.
func test_a_hotspot_track_is_thinner_than_a_plain_line() -> void:
	var parts := await _build()
	var hotspot: Feature = parts[0]
	var line: Feature = parts[1]
	var track := _world(hotspot, Hotspot.samples(hotspot))
	var plain := _world(line, line.rings[0])
	if track.size() < 3:
		fail("the hotspot has a track: %s" % track)
		await _restore()
		return
	var checks := [
		[track, 0.2, "blue", "the track 0.2 widths off its middle"],
		[track, 0.6, "red", "the track 0.6 widths off its middle"],
		[plain, 0.6, "blue", "the plain line 0.6 widths off its middle"],
	]
	for check in checks:
		var ring: PackedVector2Array = check[0]
		await _check_beside(ring[0], ring[1], check[1], check[2], check[3])
	app.features.feature_tree.select_node(hotspot)
	await _check_beside(track[0], track[1], 0.6, "red", "the selected track 0.6 widths off")
	await _restore()


# The dot sits on the outside of the bend, where no segment reaches: 0.5 widths
# from the sample, past the track's 0.35 and inside the dot's solid 0.58 widths.
func test_a_hotspot_sample_on_a_bend_has_a_dot() -> void:
	var parts := await _build()
	var track := _world(parts[0], Hotspot.samples(parts[0]))
	var bend := _sharpest_bend(track)
	if bend < 0:
		fail("the track bends: %s" % track)
		await _restore()
		return
	var sample := Measure._to_unit(track[bend])
	var back := (Measure._to_unit(track[bend - 1]) - sample).normalized()
	var ahead := (Measure._to_unit(track[bend + 1]) - sample).normalized()
	var outwards := -(back + ahead)
	outwards = (outwards - sample * outwards.dot(sample)).normalized()
	var turn := rad_to_deg(back.angle_to(ahead))
	assert_true(turn < 160.0, "the track turns at the sample, by %s degrees" % (180.0 - turn))
	var point := Measure._to_latlon(
		(sample + outwards * LINE_WIDTH * 0.5).normalized())
	await _check_at(point, "blue", "0.5 widths outside the bend")
	# Selected, the dot is laid over the halo rather than under it.
	app.features.feature_tree.select_node(parts[0])
	await _check_at(point, "blue", "0.5 widths outside the bend of the selected track")
	await _restore()


# A circle's edge is at half a width, so 0.8 widths off its middle is the
# raster and 0.3 widths is the circle.
func test_a_circle_is_half_as_wide_as_a_line() -> void:
	var parts := await _build()
	var circle: Feature = parts[2]
	var ring := _world(circle, circle.rings[0])
	await _check_beside(ring[0], ring[1], 0.3, "blue", "the circle 0.3 widths off its middle")
	await _check_beside(ring[0], ring[1], 0.8, "red", "the circle 0.8 widths off its middle")
	await _restore()


### Helpers


# The hotspot, the plain line and the circle, at the present, over a red raster.
func _build() -> Array:
	await load_sample("empty.middle-earth")
	var flat := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	flat.fill(Color.RED)
	view().planet.set_raster(ImageTexture.create_from_image(flat), 1.0)
	var document: Document = app.document
	var root: Feature = app.features.root

	var plate := Feature.create_feature("Plate")
	plate.add_ring(PackedVector2Array([Vector2(-70, -10), Vector2(-70, 10), Vector2(-60, 0)]),
		Feature.GeometryKind.POLYGON)
	for key in PLATE_KEYS:
		plate.keyframes.append(Keyframe.create(key[0], key[1]))
	var hotspot := Feature.create_feature("Hotspot")
	hotspot.time_range = Vector2i(0, 30)
	var line := Feature.create_feature("Line")
	line.add_ring(PackedVector2Array(LINE), Feature.GeometryKind.POLYLINE)
	var circle := Feature.create_feature("Circle")
	root.children.append_array([plate, hotspot, line, circle])
	document.set_time(0.0)
	app.timeline.skip_spin.value = SKIP
	assert_eq(document.set_feature_type(hotspot, FeatureType.HOTSPOT), "", "a hotspot")
	assert_eq(document.set_hotspot(hotspot, HOTSPOT, plate.uuid, 0.0), "", "on the plate")
	assert_eq(document.set_feature_type(circle, FeatureType.CIRCLE), "", "a circle")
	assert_eq(document.set_circle(circle, CIRCLE_AXIS, CIRCLE_RADIUS, 64, false), "",
		"with its center and radius")
	for feature: Feature in [hotspot, line, circle]:
		document.set_color(feature, Color.BLUE)
	app.features.reload()
	app.refresh_geometry()
	app.features.feature_tree.select_root()
	app._on_craton_hovered(NAN, NAN)
	view().set_zoom(ZOOM)
	await frames(2)
	return [hotspot, line, circle]


func _world(feature: Feature, ring: PackedVector2Array) -> PackedVector2Array:
	return Feature.apply_basis(ring,
		Feature.world_basis(app.features.root, feature, app.document.current_time))


# The index of the inner sample where the track turns most, or -1.
func _sharpest_bend(track: PackedVector2Array) -> int:
	var best := -1
	var smallest := 180.0
	for i in range(1, track.size() - 1):
		var sample := Measure._to_unit(track[i])
		var back := Measure._to_unit(track[i - 1]) - sample
		var ahead := Measure._to_unit(track[i + 1]) - sample
		var angle := rad_to_deg(back.angle_to(ahead))
		if angle < smallest:
			smallest = angle
			best = i
	return best


# Probe the point `widths` line widths to one side of the middle of the arc
# from a to b.
func _check_beside(a: Vector2, b: Vector2, widths: float, wanted: String, what: String) -> void:
	var from := Measure._to_unit(a)
	var to := Measure._to_unit(b)
	var middle := (from + to).normalized()
	var normal := from.cross(to).normalized()
	var angle := asin(LINE_WIDTH * widths)
	var point := Measure._to_latlon(middle * cos(angle) + normal * sin(angle))
	await _check_at(point, wanted, what)


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
				fail("%s: the pixel %s off is %s (%s), not %s"
					% [what, Vector2(dx, dy), found, color, wanted])
				return


func _restore() -> void:
	app.timeline.skip_spin.value = Config.DEFAULT_SKIP
	app.features.feature_tree.select_root()
	view().set_zoom(PlanetView.DEFAULT_ZOOM)
	view().planet.set_raster(null, 0.0)
	await frames(2)
