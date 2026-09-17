extends RenderedCase

# GP-0076 and GP-0096: the Pole tool marks its pole with a cross whose arms are
# half as wide as a feature line and reach three degrees each way.
#
# The planet wears a flat red raster, since the Earth's detail does not come out
# the same from one frame to the next, and each probe reads a 3 by 3 square: the
# globe is a tessellated mesh, so a place can land a pixel off where it is
# computed to be.

# Clear of the grid, which runs along every fifteenth degree, and of the probes
# four degrees out.
const POLE := Vector2(20.0, 40.0)
# Zoomed in this far a quarter of a degree is several pixels across.
const ZOOM := 4.0
# How far off an arm's line the probes sit, in degrees. The arm is
# geometry_line_width * BOLD_SCALE, 0.006 chord or about 0.34 degrees, from its
# line to its edge and fully opaque over the inner 0.28 degrees; the outline
# line it replaced faded out by 0.12 degrees. WIDE is past the edge, where an
# arm as wide as a feature line would still be white.
const OFF := 0.1
const WIDE := 0.5


func test_a_placed_pole_is_marked_by_a_bold_cross() -> void:
	await load_sample("empty.middle-earth")
	var flat := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	flat.fill(Color.RED)
	view().planet.set_raster(ImageTexture.create_from_image(flat), 1.0)
	Config.set_snap_to_vertices(false)
	app.set_active_tool(Application.Tool.POLE)
	await look_at_latlon(POLE.x, POLE.y)
	view().set_zoom(ZOOM)
	await frames(2)

	var at: Variant = view().latlon_to_screen(POLE.x, POLE.y)
	assert_true(at != null, "the pole's place is in view")
	if at == null:
		await _restore()
		return
	var before := await capture()
	await click(at)
	var pole: Vector2 = app.pole_at
	assert_true(pole != Application.NO_POLE, "a click places the pole")
	if pole == Application.NO_POLE:
		await _restore()
		return
	assert_close(pole, POLE, 0.1, "where it was clicked")
	await frames(2)
	var after := await capture()

	var half := Application.POLE_CROSS
	var arms := {
		"the north to south arm": [pole + Vector2(-half, 0.0), pole + Vector2(half, 0.0)],
		"the west to east arm": [pole + Vector2(0.0, -half), pole + Vector2(0.0, half)],
	}
	for arm: String in arms:
		var ends: Array = arms[arm]
		for along in [1.0, 2.5]:
			var near: Variant = _screen(ends[0], ends[1], along, OFF)
			assert_true(near != null, "%s: the probe %s degrees along is in view" % [arm, along])
			if near == null:
				continue
			assert_eq(_white(before, near), 0,
				"%s: %s degrees along is the raster before the pole is placed" % [arm, along])
			assert_eq(_white(after, near), 9,
				"%s: %s degrees along and %s off its line is white" % [arm, along, OFF])
			var wide: Variant = _screen(ends[0], ends[1], along, WIDE)
			if wide != null:
				assert_eq(_white(after, wide), 0,
					"%s: %s degrees along and %s off its line is past its edge" % [arm, along, WIDE])
		var far: Variant = _screen(ends[0], ends[1], 4.0, OFF)
		assert_true(far != null, "%s: the probe 4 degrees along is in view" % arm)
		if far != null:
			assert_eq(_white(after, far), 0, "%s: 4 degrees along is past its end" % arm)
	await _restore()


### Helpers


# Where the point `along` degrees from the middle of the arc from a to b, and
# `off` degrees to one side of it, is drawn in the window, or null.
func _screen(a: Vector2, b: Vector2, along: float, off: float) -> Variant:
	var from := Measure._to_unit(a)
	var to := Measure._to_unit(b)
	var middle := (from + to).normalized()
	var normal := from.cross(to).normalized()
	var forward := normal.cross(middle)
	var on := middle * cos(deg_to_rad(along)) + forward * sin(deg_to_rad(along))
	var beside := on * cos(deg_to_rad(off)) + normal * sin(deg_to_rad(off))
	var point := Measure._to_latlon(beside)
	return view().latlon_to_screen(point.x, point.y)


# How many pixels of the 3 by 3 square around a point are white.
func _white(image: Image, centre: Vector2) -> int:
	var count := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var color := image.get_pixel(int(centre.x) + dx, int(centre.y) + dy)
			if color.r > 0.85 and color.g > 0.85 and color.b > 0.85:
				count += 1
	return count


func _restore() -> void:
	Config.set_snap_to_vertices(true)
	app.set_active_tool(Application.Tool.MOVE)
	view().set_zoom(PlanetView.DEFAULT_ZOOM)
	view().planet.set_raster(null, 0.0)
	await frames(2)
