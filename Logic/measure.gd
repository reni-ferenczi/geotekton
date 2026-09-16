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
static func _central_angle(a: Vector2, b: Vector2) -> float:
	var lat_a := deg_to_rad(a.x)
	var lat_b := deg_to_rad(b.x)
	var half_lat := sin((lat_b - lat_a) * 0.5)
	var half_lon := sin(deg_to_rad(b.y - a.y) * 0.5)
	var h := half_lat * half_lat + cos(lat_a) * cos(lat_b) * half_lon * half_lon
	return 2.0 * asin(sqrt(minf(1.0, h)))


# The great circle distance between two points, in the units the radius is in.
static func distance(a: Vector2, b: Vector2, radius: float = EARTH_RADIUS_KM) -> float:
	return _central_angle(a, b) * radius


# The distance along a run of vertices, following the great circle arc between
# each consecutive pair. A closed run adds the arc from the last back to the
# first, which is what the outline of a polygon draws.
static func path_length(points: PackedVector2Array, radius: float = EARTH_RADIUS_KM,
		closed: bool = false) -> float:
	if points.size() < 2:
		return 0.0
	var total := 0.0
	for i in range(points.size() - 1):
		total += _central_angle(points[i], points[i + 1])
	if closed:
		total += _central_angle(points[points.size() - 1], points[0])
	return total * radius


# The distance along every part of a feature's geometry. A polygon is measured
# around its outline, a polyline along it, and a multipoint has no length at all
# because its vertices are separate markers rather than a path.
static func geometry_length(feature: Feature, radius: float = EARTH_RADIUS_KM) -> float:
	if feature == null or feature.drawn_as() == Feature.GeometryKind.MULTIPOINT:
		return 0.0
	var closed := feature.drawn_as() == Feature.GeometryKind.POLYGON
	var total := 0.0
	for ring in feature.rings:
		total += path_length(ring, radius, closed)
	return total


# The area a ring encloses on a sphere of the given radius, in the square of the
# radius's units.
#
# A fan of spherical triangles from the first vertex, each one's signed excess
# added up, so a ring around a pole or across the date line needs nothing
# special. A closed ring has two sides and the smaller one is taken, which also
# makes the drawing direction irrelevant.
#
# The unit vectors are worked out in floats rather than in a Vector3, whose
# single precision would add up over the hundreds of thin triangles a circle
# makes.
static func ring_area(ring: PackedVector2Array, radius: float = EARTH_RADIUS_KM) -> float:
	if ring.size() < 3:
		return 0.0
	var a := _unit64(ring[0])
	var b := _unit64(ring[1])
	var excess := 0.0
	for i in range(2, ring.size()):
		var c := _unit64(ring[i])
		var triple := a[0] * (b[1] * c[2] - b[2] * c[1]) \
			+ a[1] * (b[2] * c[0] - b[0] * c[2]) \
			+ a[2] * (b[0] * c[1] - b[1] * c[0])
		excess += 2.0 * atan2(triple, 1.0 + _dot64(a, b) + _dot64(b, c) + _dot64(c, a))
		b = c
	var steradians := absf(excess)
	return minf(steradians, 4.0 * PI - steradians) * radius * radius


# The area of a feature's polygon, its parts added up. Anything not drawn as a
# polygon encloses nothing.
static func geometry_area(feature: Feature, radius: float = EARTH_RADIUS_KM) -> float:
	if feature == null or feature.drawn_as() != Feature.GeometryKind.POLYGON:
		return 0.0
	var total := 0.0
	for ring in feature.rings:
		total += ring_area(ring, radius)
	return total


# The surface of the whole planet.
static func planet_area(radius: float = EARTH_RADIUS_KM) -> float:
	return 4.0 * PI * radius * radius


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
	var whole := _central_angle(a, b)
	if whole < 1e-9:
		return 0.0
	return clampf(_central_angle(a, p) / whole, 0.0, 1.0)


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


# An area the way the panels show it: a decimal on a small area, whole square
# kilometers up to a million, and millions beyond that. The thousands are set
# apart by a narrow space a line does not break at.
static func format_area(km2: float) -> String:
	if km2 < 1000.0:
		return "%.1f km²" % km2
	if km2 < 1.0e6:
		var digits := "%.0f" % km2
		var cut := digits.length() - 3
		return "%s\u202f%s km²" % [digits.left(cut), digits.substr(cut)]
	return "%.2f million km²" % (km2 / 1.0e6)


# How much of the planet an area is, for the Properties panel: one decimal, and
# nothing at all when it would round to nothing. The line does not break before
# the percent sign.
static func format_share(km2: float, radius: float) -> String:
	var percent := km2 / planet_area(radius) * 100.0
	return "" if percent < 0.05 else "%.1f\u00a0%% of the planet" % percent


static func _unit64(v: Vector2) -> PackedFloat64Array:
	var lat := deg_to_rad(v.x)
	var lon := deg_to_rad(v.y)
	return PackedFloat64Array([cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)])


static func _dot64(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func _to_unit(v: Vector2) -> Vector3:
	var lat := deg_to_rad(v.x)
	var lon := deg_to_rad(v.y)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon))


static func _to_latlon(p: Vector3) -> Vector2:
	return Vector2(rad_to_deg(asin(clampf(p.y, -1.0, 1.0))), rad_to_deg(atan2(p.z, p.x)))
