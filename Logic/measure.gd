class_name Measure

# Distances along the surface of the planet, for the Measure tool and for
# anything that wants the length of a piece of geometry.
#
# Every vertex in the application is a latitude and a longitude in degrees on a
# unit sphere, so a distance is an angle until a radius is put to it. The radius
# is a preference rather than part of a document: it says which planet the
# numbers are read against, not anything about the features. See
# Config.get_planet_radius().

# The radius distances default to, in kilometres: Earth's mean radius, the
# value the IUGG publishes. A quarter of the meridian on a sphere this size is
# 10007.5 km, which is where the metre came from.
const EARTH_RADIUS_KM := 6371.0

# The narrowest and widest radius the preference accepts, in kilometres. Wide
# enough for anything from a small moon to a gas giant, and away from zero so a
# distance is never reported as nothing.
const MIN_RADIUS_KM := 1.0
const MAX_RADIUS_KM := 1.0e7


# The angle between two latitude and longitude points, in radians.
#
# The haversine form, not acos of the dot product: the dot product of two nearly
# equal unit vectors is 1 to within the rounding of the arithmetic, and acos
# then throws away most of the digits. Short distances are what a measurement
# usually is.
static func central_angle(a: Vector2, b: Vector2) -> float:
	var lat_a := deg_to_rad(a.x)
	var lat_b := deg_to_rad(b.x)
	var half_lat := sin((lat_b - lat_a) * 0.5)
	var half_lon := sin(deg_to_rad(b.y - a.y) * 0.5)
	var h := half_lat * half_lat + cos(lat_a) * cos(lat_b) * half_lon * half_lon
	return 2.0 * asin(sqrt(minf(1.0, h)))


# The great circle distance between two points, in the units the radius is in.
static func distance(a: Vector2, b: Vector2, radius: float = EARTH_RADIUS_KM) -> float:
	return central_angle(a, b) * radius


# The distance along a run of vertices, following the great circle arc between
# each consecutive pair. A closed run adds the arc from the last back to the
# first, which is what the outline of a polygon draws.
static func path_length(points: PackedVector2Array, radius: float = EARTH_RADIUS_KM,
		closed: bool = false) -> float:
	if points.size() < 2:
		return 0.0
	var total := 0.0
	for i in range(points.size() - 1):
		total += central_angle(points[i], points[i + 1])
	if closed:
		total += central_angle(points[points.size() - 1], points[0])
	return total * radius


# The distance along every part of a feature's geometry. A polygon is measured
# around its outline, a polyline along it, and a multipoint has no length at all
# because its vertices are separate markers rather than a path.
static func geometry_length(feature: Feature, radius: float = EARTH_RADIUS_KM) -> float:
	if feature == null or feature.geometry_kind == Feature.GeometryKind.MULTIPOINT:
		return 0.0
	var closed := feature.geometry_kind == Feature.GeometryKind.POLYGON
	var total := 0.0
	for ring in feature.rings:
		total += path_length(ring, radius, closed)
	return total


# The point a fraction of the way along the great circle arc from a to b. The
# ends themselves at 0 and 1, so the two are exact rather than nearly right.
#
# Antipodal ends have no shortest arc between them; the midpoint is then not
# defined and a is returned rather than an arbitrary direction.
static func along(a: Vector2, b: Vector2, t: float) -> Vector2:
	if t <= 0.0:
		return a
	if t >= 1.0:
		return b
	var from := _to_unit(a)
	var to := _to_unit(b)
	var angle := acos(clampf(from.dot(to), -1.0, 1.0))
	if angle < 1e-9 or angle > PI - 1e-9:
		return a
	var sin_angle := sin(angle)
	var point := (from * sin((1.0 - t) * angle) + to * sin(t * angle)) / sin_angle
	return _to_latlon(point.normalized())


# How far along the arc from a to b the point nearest to p sits, from 0 at a to
# 1 at b. Clamped to the arc, so a point beyond either end gives that end.
static func fraction_along(a: Vector2, b: Vector2, p: Vector2) -> float:
	var whole := central_angle(a, b)
	if whole < 1e-9:
		return 0.0
	return clampf(central_angle(a, p) / whole, 0.0, 1.0)


# A distance written the way the status bar shows it: metres under a kilometre,
# and fewer decimals the larger it gets, since a thousand kilometres is not
# known to the metre.
static func format_km(km: float) -> String:
	if km < 1.0:
		return "%.0f m" % (km * 1000.0)
	if km < 100.0:
		return "%.2f km" % km
	if km < 10000.0:
		return "%.1f km" % km
	return "%.0f km" % km


static func _to_unit(v: Vector2) -> Vector3:
	var lat := deg_to_rad(v.x)
	var lon := deg_to_rad(v.y)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon))


static func _to_latlon(p: Vector3) -> Vector2:
	return Vector2(rad_to_deg(asin(clampf(p.y, -1.0, 1.0))), rad_to_deg(atan2(p.z, p.x)))
