extends TestCase

# The five map projections in Logic/map_projection.gd. What is checked is that
# forward and inverse are each other's undoing over a grid that reaches both
# poles and both sides of the dateline, and that a point the projection does
# not draw comes back as outside rather than as some other place.


# Every fifteen degrees, with the poles and both sides of the dateline in it.
const LATITUDES := [
	-90.0, -85.0, -75.0, -60.0, -45.0, -30.0, -15.0, 0.0,
	15.0, 30.0, 45.0, 60.0, 75.0, 85.0, 90.0,
]
const LONGITUDES := [
	-180.0, -179.9, -135.0, -90.0, -45.0, -0.1, 0.0, 0.1,
	45.0, 90.0, 135.0, 179.9, 180.0,
]

# Centres to project about: the default, one off the central meridian, one that
# puts the dateline in the middle, and one away from the equator for the sake of
# the orthographic projection, which is the only one that reads the latitude.
const CENTRES := [
	Vector2(0.0, 0.0),
	Vector2(0.0, 60.0),
	Vector2(0.0, 180.0),
	Vector2(40.0, -75.0),
]

# How far a round trip may land from where it started, in degrees. A Vector2
# holds 32-bit floats, so the point on the plane loses a few digits on the way
# through.
const TOLERANCE := 1e-4

# The smallest cosine the orthographic tolerance is divided by, which caps that
# tolerance at a tenth of a degree on the rim itself. See _tolerance_for().
const LIMB_FLOOR := 1e-3

const KINDS := [
	MapProjection.Kind.RECTANGULAR,
	MapProjection.Kind.MERCATOR,
	MapProjection.Kind.MOLLWEIDE,
	MapProjection.Kind.ROBINSON,
	MapProjection.Kind.ORTHOGRAPHIC,
]


func test_forward_then_inverse_gives_the_point_back() -> void:
	for kind in KINDS:
		for centre in CENTRES:
			for lat in LATITUDES:
				for lon in LONGITUDES:
					_check_round_trip(kind, Vector2(lat, lon), centre)


# A point on the plane that the projection does not cover has to be reported as
# outside. The corners of the sheet are outside the Mollweide ellipse and the
# Robinson outline, and the corners of the orthographic square are outside its
# disc; the rectangular sheet has no such place, so it is not asked.
func test_a_point_off_the_projection_is_reported_as_outside() -> void:
	var corners := {
		MapProjection.Kind.MOLLWEIDE: [Vector2(0.99, 0.45), Vector2(-0.99, -0.45)],
		MapProjection.Kind.ROBINSON: [Vector2(0.99, 0.45), Vector2(-0.99, -0.45)],
		MapProjection.Kind.ORTHOGRAPHIC: [Vector2(0.8, 0.8), Vector2(-0.9, 0.9)],
	}
	for kind in corners:
		for plane in corners[kind]:
			assert_eq(MapProjection.inverse(kind, plane, Vector2.ZERO), null,
				"%s at %s is off the map" % [MapProjection.name_of(kind), plane])


# Every projection but the orthographic one draws the whole planet, so the point
# under the middle of its sheet is on the equator at the central meridian. Under
# an orthographic one it is the centre itself, latitude and all.
func test_the_middle_of_the_sheet_is_the_centre() -> void:
	for kind in KINDS:
		for centre in CENTRES:
			var middle = MapProjection.inverse(kind, Vector2.ZERO, centre)
			var expected_lat: float = \
				centre.x if kind == MapProjection.Kind.ORTHOGRAPHIC else 0.0
			assert_close(middle.x, expected_lat, TOLERANCE,
				"the latitude under the middle of the %s sheet" % MapProjection.name_of(kind))
			assert_close(_longitude_difference(middle.y, centre.y), 0.0, TOLERANCE,
				"the longitude under the middle of the %s sheet" % MapProjection.name_of(kind))


# The far side of an orthographic projection is not drawn, and the near side is.
func test_orthographic_hides_the_far_side() -> void:
	var centre := Vector2(0.0, 0.0)
	for lon in [95.0, 150.0, 180.0, -150.0, -95.0]:
		assert_eq(
			MapProjection.forward(MapProjection.Kind.ORTHOGRAPHIC, Vector2(0.0, lon), centre),
			null, "longitude %s is behind the planet" % lon)
	for lon in [-85.0, -45.0, 0.0, 45.0, 85.0]:
		assert_true(
			MapProjection.forward(
				MapProjection.Kind.ORTHOGRAPHIC, Vector2(0.0, lon), centre) != null,
			"longitude %s is in front of the planet" % lon)


# Mercator cannot reach a pole at all: it runs off the sheet a few degrees short
# of one, and the projection says so rather than drawing it at the edge.
func test_mercator_stops_short_of_the_poles() -> void:
	for lat in [-90.0, -89.0, -86.0, 86.0, 89.0, 90.0]:
		assert_eq(
			MapProjection.forward(
				MapProjection.Kind.MERCATOR, Vector2(lat, 0.0), Vector2.ZERO),
			null, "latitude %s is off the Mercator sheet" % lat)
	for lat in [-85.0, 0.0, 85.0]:
		assert_true(
			MapProjection.forward(
				MapProjection.Kind.MERCATOR, Vector2(lat, 0.0), Vector2.ZERO) != null,
			"latitude %s is on the Mercator sheet" % lat)


# The sheet each projection draws on is as wide as the equator and as tall as
# the projection's own aspect ratio asks for, which is what Planet scales the
# map mesh by.
func test_the_sheet_holds_what_the_projection_draws() -> void:
	for kind in KINDS:
		var extent := MapProjection.extent(kind)
		for lat in LATITUDES:
			for lon in LONGITUDES:
				var plane = MapProjection.forward(kind, Vector2(lat, lon), Vector2.ZERO)
				if plane == null:
					continue
				assert_true(absf(plane.x) <= 1.0 + 1e-6 and absf(plane.y) <= extent + 1e-6,
					"%s puts (%s, %s) at %s, outside its %s sheet" % [
						MapProjection.name_of(kind), lat, lon, plane, extent])


func _check_round_trip(kind: MapProjection.Kind, point: Vector2, centre: Vector2) -> void:
	var where := "%s at (%s, %s) about %s" % [
		MapProjection.name_of(kind), point.x, point.y, centre]
	var plane = MapProjection.forward(kind, point, centre)
	if plane == null:
		return
	var back = MapProjection.inverse(kind, plane, centre)
	if back == null:
		fail("%s projects to %s, which comes back as off the map" % [where, plane])
		return
	var tolerance := _tolerance_for(kind, point, centre)
	assert_close(back.x, point.x, tolerance, "the latitude of %s" % where)
	# A pole is one point of the planet, and every meridian runs to it, so which
	# longitude comes back there says nothing.
	if absf(point.x) < 90.0 - 1e-9:
		assert_close(_longitude_difference(back.y, point.y), 0.0, tolerance,
			"the longitude of %s, which came back as %s" % [where, back.y])


# How far a round trip may land from where it started at one point.
#
# Orthographic squeezes a whole hemisphere into its disc, and the radius of a
# point there is the sine of its angular distance from the centre. The inverse
# takes the arc sine back, so it magnifies a step across the plane by one over
# the cosine of that distance, without limit at the rim. Every other projection
# is well behaved everywhere it draws.
func _tolerance_for(kind: MapProjection.Kind, point: Vector2, centre: Vector2) -> float:
	if kind != MapProjection.Kind.ORTHOGRAPHIC:
		return TOLERANCE
	return TOLERANCE / maxf(absf(_cosine_from_centre(point, centre)), LIMB_FLOOR)


# The cosine of the angular distance from the centre to a point, which is zero
# on the rim of an orthographic disc and one at its middle.
func _cosine_from_centre(point: Vector2, centre: Vector2) -> float:
	var lat := deg_to_rad(point.x)
	var centre_lat := deg_to_rad(centre.x)
	var delta := deg_to_rad(point.y - centre.y)
	return sin(centre_lat) * sin(lat) + cos(centre_lat) * cos(lat) * cos(delta)


# How far apart two longitudes are, the short way round, so that -180 and 180
# count as the same meridian.
func _longitude_difference(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)
