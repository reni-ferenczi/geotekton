class_name Circle

# A circle drawn on the surface of the planet: every point of it the same
# angular distance from one centre. A great circle is the case where that
# distance is 90 degrees; a smaller one is the path a point follows while a
# plate turns about a fixed pole.
#
# Nothing here touches a Feature or a Document. The Circle tool works out the
# circle here, previews it, and hands the vertices to the feature; see
# Docs/Editing.md#the-circle-tool.
#
# Angles are degrees and points are (latitude, longitude), as everywhere else in
# the application.

# How finely a circle may be cut up when it becomes a polygon or a polyline.
# Three is the fewest a polygon can be drawn with at all; the upper end is well
# past what anyone can see on a globe and keeps a typo out of the vertex list.
const MIN_SEGMENTS := 3
const MAX_SEGMENTS := 720
const DEFAULT_SEGMENTS := 36

# Below this the arithmetic no longer says which circle is meant: two of the
# three points have come together, or the radius has closed to nothing.
const EPSILON := 1e-9


# The circle around a centre, cut into the given number of segments.
#
# A closed run holds one vertex per segment and the shape closes from the last
# back to the first, which is what a polygon does. An open one repeats the first
# vertex at the end, so a polyline of the same segment count draws the whole
# circle rather than stopping one segment short.
#
# The first vertex sits due north of the centre and the rest follow eastwards,
# which winds a polygon counter-clockwise as seen from outside the sphere. That
# is the winding Feature.faces_outwards, Planet.hit_test and the geometry shader
# all require.
static func vertices(centre: Vector2, radius_deg: float, segments: int,
		closed: bool = true) -> PackedVector2Array:
	var count := clampi(segments, MIN_SEGMENTS, MAX_SEGMENTS)
	var axis := _to_unit(centre)
	var north := _north_at(axis)
	var east := axis.cross(north)
	var radius := deg_to_rad(radius_deg)
	var along := sin(radius)
	var up := cos(radius) * axis

	var result := PackedVector2Array()
	for i in range(count + (0 if closed else 1)):
		var turn := TAU * float(i) / float(count)
		result.append(_to_latlon(up + along * (cos(turn) * north + sin(turn) * east)))
	return result


# The circle through three points, as [centre, angular radius in degrees], or an
# empty array when the three do not settle one.
#
# Three points on a sphere lie on one plane, and a plane cuts the sphere in a
# circle; the centre is where the plane's normal meets the surface and the
# radius is the angle from there to any of the three. The normal is taken from
# the two edges of the triangle they make, so it disappears exactly when two of
# the points have come together, which is the one case with no answer. Three
# points of one great circle are not that case: the plane then passes through
# the middle of the planet and the answer is a radius of 90 degrees.
#
# How well the centre is settled depends on how large the circle is. A vertex is
# a pair of 32-bit floats, as every packed Godot type is, and the normal comes
# out of differences between three of them: the smaller the circle, the more of
# those digits the subtraction takes away. A circle of a degree across lands its
# centre to about a thousandth of a degree, and a larger one to much less.
static func through(a: Vector2, b: Vector2, c: Vector2) -> Array:
	var pa := _to_unit(a)
	var pb := _to_unit(b)
	var pc := _to_unit(c)
	var normal := (pb - pa).cross(pc - pa)
	if normal.length_squared() < EPSILON:
		return []

	normal = normal.normalized()
	# Either end of the normal is a centre of the same circle; the near one is
	# the centre with a radius under 90 degrees, which is the one meant.
	if normal.dot(pa) < 0.0:
		normal = -normal
	var centre := _to_latlon(normal)
	return [centre, radius_to(centre, a)]


# The angular radius of the circle around a centre that passes through a point:
# the great circle distance between the two, read on a planet of radius one.
static func radius_to(centre: Vector2, rim: Vector2) -> float:
	return rad_to_deg(Measure.distance(centre, rim, 1.0))


# A radius written the way the status bar shows it.
static func format_radius(radius_deg: float) -> String:
	return "%.2f°" % radius_deg


# The direction of the north pole seen from a point on the surface, as a unit
# vector in the plane of the horizon there. At a pole every direction is south
# or north, so the prime meridian stands in and the circle simply starts
# somewhere fixed rather than nowhere.
static func _north_at(axis: Vector3) -> Vector3:
	var north := Vector3.UP - axis * Vector3.UP.dot(axis)
	if north.length_squared() < EPSILON:
		north = Vector3.RIGHT - axis * Vector3.RIGHT.dot(axis)
	return north.normalized()


static func _to_unit(v: Vector2) -> Vector3:
	var lat := deg_to_rad(v.x)
	var lon := deg_to_rad(v.y)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon))


static func _to_latlon(p: Vector3) -> Vector2:
	var unit := p.normalized()
	return Vector2(rad_to_deg(asin(clampf(unit.y, -1.0, 1.0))), rad_to_deg(atan2(unit.z, unit.x)))
