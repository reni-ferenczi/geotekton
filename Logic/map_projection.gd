class_name MapProjection

# The map projections the flat view draws the planet in.
#
# A projection is a pair of functions between the surface of the planet and the
# plane the map mesh occupies. `forward` takes a latitude and a longitude to a
# point of that plane; `inverse` takes a point of the plane back. Either one
# answers `null` when the point it was given is not on the map at all: the far
# side under an orthographic projection, a latitude Mercator cannot reach, a
# corner of the sheet outside the Mollweide ellipse or the Robinson outline.
#
# The plane is the same for every projection: x runs from -1 to 1 across the
# whole width, and y from -extent to extent, where `extent` is what the
# projection's own aspect ratio asks for. Planet scales the map mesh by it, so
# the mesh is exactly as tall as the projection needs and the shader's UV covers
# the projection and nothing else.
#
# planet.gdshader holds the inverse of each projection again, in GLSL, because
# every fragment of the map needs it. The two must agree: a click and a pixel
# are supposed to be about the same place. Docs/Shader.md#map-projections lists
# them side by side.
#
# Angles are degrees at the surface of this class and radians inside it, and
# points are (latitude, longitude), as everywhere else in the application.

enum Kind {
	RECTANGULAR = 0,
	MERCATOR = 1,
	MOLLWEIDE = 2,
	ROBINSON = 3,
	ORTHOGRAPHIC = 4,
}

# The names the projection selector shows, in the order Kind lists them.
const NAMES := ["Rectangular", "Mercator", "Mollweide", "Robinson", "Orthographic"]

# The latitude Mercator reaches at the top of a square sheet. Beyond it the
# projection runs off to infinity, so both poles are off the map.
const MERCATOR_MAX_LAT := 85.05112877980659

# Robinson is tabulated rather than given by a formula: the length of each
# parallel and its distance from the equator, every five degrees from the
# equator to the pole, interpolated linearly in between. The two scale factors
# are the ones the projection is defined with.
const ROBINSON_STEP := 5.0
const ROBINSON_LENGTH := [
	1.0000, 0.9986, 0.9954, 0.9900, 0.9822, 0.9730, 0.9600, 0.9427, 0.9216,
	0.8962, 0.8679, 0.8350, 0.7986, 0.7597, 0.7186, 0.6732, 0.6213, 0.5722,
	0.5322,
]
const ROBINSON_DISTANCE := [
	0.0000, 0.0620, 0.1240, 0.1860, 0.2480, 0.3100, 0.3720, 0.4340, 0.4958,
	0.5571, 0.6176, 0.6769, 0.7346, 0.7903, 0.8435, 0.8936, 0.9394, 0.9761,
	1.0000,
]
const ROBINSON_X := 0.8487
const ROBINSON_Y := 1.3523
# Half the height of the Robinson sheet: the pole's distance from the equator
# against half the width of the equator itself, which is the 1.97 to 1 the
# projection is known for.
const ROBINSON_EXTENT := ROBINSON_Y / (ROBINSON_X * PI)

# Half the height of the plane each projection needs, with half the width at 1.
# Rectangular and Mollweide are the familiar two to one; Robinson is a little
# taller; Mercator and orthographic are square.
const EXTENTS := [0.5, 1.0, 0.5, ROBINSON_EXTENT, 1.0]

# Below this two quantities the arithmetic divides by have closed to nothing:
# the cosine of the Mollweide auxiliary angle at a pole, and the distance from
# the centre of an orthographic disc.
const EPSILON := 1e-12

# How far past the edge of a sheet a point may lie and still be taken as on it,
# clamped back to the edge. A Vector2 holds 32-bit floats, so a point forward()
# put exactly on the edge can come back a few bits outside it, and without the
# slack a pole would be reported as off the map it was just drawn on.
const EDGE_SLACK := 1e-6


static func name_of(kind: Kind) -> String:
	return NAMES[int(kind)]


# Half the height of the plane this projection draws on, with half the width 1.
static func extent(kind: Kind) -> float:
	return float(EXTENTS[int(kind)])


# Where a point of the planet lands on the plane, or null when the projection
# does not show it. `centre` is (latitude, longitude): its longitude is the
# central meridian of every projection, and its latitude is the centre of the
# visible hemisphere under an orthographic one and unused by the rest.
static func forward(kind: Kind, point: Vector2, centre: Vector2) -> Variant:
	var lat := deg_to_rad(point.x)
	var lon := deg_to_rad(_wrap_longitude(point.y - centre.y))

	match kind:
		Kind.RECTANGULAR:
			return Vector2(lon / PI, lat / PI)

		Kind.MERCATOR:
			if absf(point.x) > MERCATOR_MAX_LAT:
				return null
			return Vector2(lon / PI, log(tan(PI * 0.25 + lat * 0.5)) / PI)

		Kind.MOLLWEIDE:
			var theta := _mollweide_theta(lat)
			return Vector2(lon * cos(theta) / PI, sin(theta) * 0.5)

		Kind.ROBINSON:
			var length := _robinson_at(ROBINSON_LENGTH, absf(point.x))
			var distance := _robinson_at(ROBINSON_DISTANCE, absf(point.x))
			return Vector2(
				lon * length / PI,
				signf(point.x) * distance * ROBINSON_EXTENT)

		Kind.ORTHOGRAPHIC:
			var centre_lat := deg_to_rad(centre.x)
			var cos_lat := cos(lat)
			# The far side of the planet, which this projection does not show.
			if sin(centre_lat) * sin(lat) + cos(centre_lat) * cos_lat * cos(lon) < 0.0:
				return null
			return Vector2(
				cos_lat * sin(lon),
				cos(centre_lat) * sin(lat) - sin(centre_lat) * cos_lat * cos(lon))

	return null


# Which point of the planet a point of the plane shows, or null when it falls
# outside what the projection draws. The counterpart of forward(), with the same
# `centre`.
static func inverse(kind: Kind, plane: Vector2, centre: Vector2) -> Variant:
	match kind:
		Kind.RECTANGULAR:
			if absf(plane.y) > 0.5 + EDGE_SLACK or absf(plane.x) > 1.0 + EDGE_SLACK:
				return null
			return _from_radians(plane.y * PI, plane.x * PI, centre)

		Kind.MERCATOR:
			if absf(plane.y) > 1.0 + EDGE_SLACK or absf(plane.x) > 1.0 + EDGE_SLACK:
				return null
			return _from_radians(2.0 * atan(exp(plane.y * PI)) - PI * 0.5, plane.x * PI, centre)

		Kind.MOLLWEIDE:
			var sin_theta := plane.y * 2.0
			if absf(sin_theta) > 1.0 + EDGE_SLACK:
				return null
			var theta := asin(clampf(sin_theta, -1.0, 1.0))
			var cos_theta := cos(theta)
			var lat := asin(clampf((2.0 * theta + sin(2.0 * theta)) / PI, -1.0, 1.0))
			# The two poles are single points of the ellipse: every meridian
			# reaches them, so the central one answers for all of them.
			if cos_theta < EPSILON:
				return _from_radians(lat, 0.0, centre)
			var lon: float = plane.x * PI / cos_theta
			if absf(lon) > PI + EDGE_SLACK:
				return null
			return _from_radians(lat, clampf(lon, -PI, PI), centre)

		Kind.ROBINSON:
			var distance := plane.y / ROBINSON_EXTENT
			if absf(distance) > 1.0 + EDGE_SLACK:
				return null
			var lat_deg := signf(plane.y) * _robinson_latitude(minf(absf(distance), 1.0))
			var length := _robinson_at(ROBINSON_LENGTH, absf(lat_deg))
			var lon_r: float = plane.x * PI / length
			if absf(lon_r) > PI + EDGE_SLACK:
				return null
			return _from_radians(deg_to_rad(lat_deg), clampf(lon_r, -PI, PI), centre)

		Kind.ORTHOGRAPHIC:
			var radius := plane.length()
			if radius > 1.0 + EDGE_SLACK:
				return null
			var centre_lat := deg_to_rad(centre.x)
			if radius < EPSILON:
				return _from_radians(centre_lat, 0.0, centre)
			var angle := asin(minf(radius, 1.0))
			var sin_c := sin(angle)
			var cos_c := cos(angle)
			var lat := asin(clampf(
				cos_c * sin(centre_lat) + plane.y * sin_c * cos(centre_lat) / radius,
				-1.0, 1.0))
			var lon := atan2(
				plane.x * sin_c,
				radius * cos_c * cos(centre_lat) - plane.y * sin_c * sin(centre_lat))
			return _from_radians(lat, lon, centre)

	return null


static func _from_radians(lat: float, lon: float, centre: Vector2) -> Vector2:
	return Vector2(rad_to_deg(lat), _wrap_longitude(rad_to_deg(lon) + centre.y))


static func _wrap_longitude(lon: float) -> float:
	return fposmod(lon + 180.0, 360.0) - 180.0


# The Mollweide auxiliary angle: the one solving 2t + sin 2t = PI sin(lat).
# Newton's method from the latitude itself, which converges in a few steps
# everywhere but the poles, where the derivative vanishes and the answer is
# already known.
static func _mollweide_theta(lat: float) -> float:
	var target := PI * sin(lat)
	if absf(absf(lat) - PI * 0.5) < 1e-9:
		return signf(lat) * PI * 0.5
	var theta := lat
	for _i in range(12):
		var denominator := 2.0 + 2.0 * cos(2.0 * theta)
		if absf(denominator) < EPSILON:
			break
		var step := (2.0 * theta + sin(2.0 * theta) - target) / denominator
		theta -= step
		if absf(step) < 1e-12:
			break
	return theta


# One of the two Robinson tables at a latitude in degrees, interpolated between
# the five degree entries it is given at.
static func _robinson_at(table: Array, lat_deg: float) -> float:
	var position := clampf(lat_deg, 0.0, 90.0) / ROBINSON_STEP
	var low := int(position)
	if low >= table.size() - 1:
		return float(table[table.size() - 1])
	return lerpf(float(table[low]), float(table[low + 1]), position - float(low))


# The latitude in degrees whose Robinson distance from the equator is the given
# one, which is the same table read the other way round. The distances rise with
# the latitude, so a walk finds the pair to interpolate between.
static func _robinson_latitude(distance: float) -> float:
	for i in range(ROBINSON_DISTANCE.size() - 1):
		var low: float = ROBINSON_DISTANCE[i]
		var high: float = ROBINSON_DISTANCE[i + 1]
		if distance <= high:
			var span := high - low
			var part := 0.0 if span < EPSILON else (distance - low) / span
			return (float(i) + part) * ROBINSON_STEP
	return 90.0
