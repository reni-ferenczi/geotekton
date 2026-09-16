extends TestCase

# Great circle distances, and the points along an arc that inserting a vertex on
# an edge needs.

# One part in ten thousand, the tolerance the phase asks the published values to
# be met within.
const RELATIVE := 1e-4


### Distances against values that are published rather than derived here


func test_a_quarter_of_the_meridian() -> void:
	# From the equator to the pole. On a sphere of Earth's mean radius this is
	# 10007.5 km, and the metre was defined as a ten millionth of it.
	var got := Measure.distance(Vector2(0, 0), Vector2(90, 0))
	_assert_relative(got, 10007.543, "the equator to the pole")


func test_half_of_the_great_circle() -> void:
	# Two antipodal points on the equator. Earth's mean great circle is
	# published as 40030 km around, so half of it is 20015 km.
	var got := Measure.distance(Vector2(0, 0), Vector2(0, 180))
	_assert_relative(got, 20015.087, "two antipodal points")


func test_one_degree_of_latitude() -> void:
	# 111.195 km per degree on a sphere of Earth's mean radius. The nautical
	# mile is not checked against it: 1852 m is a minute of arc on the
	# ellipsoid, which is a different figure and no test of this code.
	var got := Measure.distance(Vector2(10, 25), Vector2(11, 25))
	_assert_relative(got, 111.195, "one degree along a meridian")


func test_a_degree_of_longitude_shrinks_with_the_latitude() -> void:
	# cos(60 degrees) is a half exactly, so a degree of longitude at 60 north is
	# half what it is on the equator.
	var equator := Measure.distance(Vector2(0, 0), Vector2(0, 1))
	var north := Measure.distance(Vector2(60, 0), Vector2(60, 1))
	assert_close(north / equator, 0.5, 1e-4, "half as far at 60 degrees north")


func test_the_same_point_is_no_distance_away() -> void:
	assert_close(Measure.distance(Vector2(12, -34), Vector2(12, -34)), 0.0, 1e-9)


func test_a_short_distance_keeps_its_digits() -> void:
	# A thousandth of a degree, where acos of the dot product would have thrown
	# most of the precision away.
	var got := Measure.distance(Vector2(0, 0), Vector2(0.001, 0))
	_assert_relative(got, 111.19492664 * 0.001, "a thousandth of a degree")


func test_another_radius_scales_every_distance() -> void:
	var earth := Measure.distance(Vector2(0, 0), Vector2(0, 90))
	var half := Measure.distance(Vector2(0, 0), Vector2(0, 90), Measure.EARTH_RADIUS_KM * 0.5)
	assert_close(half * 2.0, earth, 1e-6, "half the radius is half the distance")


### Along a path


func test_a_path_is_the_sum_of_its_segments() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(0, 10), Vector2(5, 10), Vector2(20, 40)])
	var sum := 0.0
	for i in range(points.size() - 1):
		sum += Measure.distance(points[i], points[i + 1])
	assert_close(Measure.path_length(points), sum, 1e-6, "the whole equals the parts")


func test_a_closed_path_adds_the_arc_back_to_the_start() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(0, 10), Vector2(10, 10)])
	var open_length := Measure.path_length(points)
	var closed := Measure.path_length(points, Measure.EARTH_RADIUS_KM, true)
	assert_close(closed - open_length, Measure.distance(points[2], points[0]), 1e-6,
		"the closing arc is the difference")


func test_a_path_of_fewer_than_two_points_has_no_length() -> void:
	assert_close(Measure.path_length(PackedVector2Array()), 0.0, 1e-9)
	assert_close(Measure.path_length(PackedVector2Array([Vector2(3, 4)])), 0.0, 1e-9)


func test_the_length_of_each_kind_of_geometry() -> void:
	var ring := PackedVector2Array([Vector2(0, 0), Vector2(0, 10), Vector2(10, 10)])

	var polygon := Feature.create_feature("Polygon")
	polygon.add_ring(ring, Feature.GeometryKind.POLYGON)
	assert_close(Measure.geometry_length(polygon),
		Measure.path_length(ring, Measure.EARTH_RADIUS_KM, true), 1e-6,
		"a polygon is measured around its outline")

	var polyline := Feature.create_feature("Polyline")
	polyline.add_ring(ring, Feature.GeometryKind.POLYLINE)
	assert_close(Measure.geometry_length(polyline), Measure.path_length(ring), 1e-6,
		"a polyline along it")

	var multipoint := Feature.create_feature("Multipoint")
	multipoint.add_ring(ring, Feature.GeometryKind.MULTIPOINT)
	assert_close(Measure.geometry_length(multipoint), 0.0, 1e-9,
		"separate markers are not a path")


func test_several_parts_are_added_up() -> void:
	var first := PackedVector2Array([Vector2(0, 0), Vector2(0, 10)])
	var second := PackedVector2Array([Vector2(30, 0), Vector2(30, 20)])
	var feature := Feature.create_feature("Two lines")
	feature.add_ring(first, Feature.GeometryKind.POLYLINE)
	feature.add_ring(second, Feature.GeometryKind.POLYLINE)
	assert_close(Measure.geometry_length(feature),
		Measure.path_length(first) + Measure.path_length(second), 1e-6)


### Areas


func test_an_octant_is_an_eighth_of_the_planet() -> void:
	var octant := PackedVector2Array([Vector2(0, 0), Vector2(0, 90), Vector2(90, 0)])
	var got := Measure.ring_area(octant)
	var wanted := Measure.planet_area() / 8.0
	assert_true(absf(got - wanted) <= wanted * 1e-6, "%s is not %s" % [got, wanted])


func test_a_circle_has_the_area_of_its_cap() -> void:
	var ring := Circle.vertices(Vector2(30, 40), 10.0, 360)
	var r := Measure.EARTH_RADIUS_KM
	var cap := TAU * r * r * (1.0 - cos(deg_to_rad(10.0)))
	var got := Measure.ring_area(ring)
	assert_true(absf(got - cap) <= cap * 1e-3, "%s is not the cap's %s" % [got, cap])
	var reversed := ring.duplicate()
	reversed.reverse()
	assert_close(Measure.ring_area(reversed), got, got * 1e-9, "the winding does not matter")


func test_a_ring_around_the_pole_encloses_the_cap() -> void:
	var ring := PackedVector2Array()
	for lon in range(-180, 180):
		ring.append(Vector2(-82, lon))
	var r := Measure.EARTH_RADIUS_KM
	var cap := TAU * r * r * (1.0 - cos(deg_to_rad(8.0)))
	var got := Measure.ring_area(ring)
	assert_true(absf(got - cap) <= cap * 1e-3, "%s is not the cap's %s" % [got, cap])


func test_a_ring_across_the_date_line() -> void:
	var across := PackedVector2Array([Vector2(0, 170), Vector2(0, -170), Vector2(10, -170), Vector2(10, 170)])
	var here := PackedVector2Array([Vector2(0, -10), Vector2(0, 10), Vector2(10, 10), Vector2(10, -10)])
	assert_close(Measure.ring_area(across), Measure.ring_area(here), 1.0,
		"the same square on the other side of the planet")


func test_the_area_of_each_kind_of_geometry() -> void:
	var first := PackedVector2Array([Vector2(0, 0), Vector2(0, 10), Vector2(10, 10)])
	var second := PackedVector2Array([Vector2(-30, 50), Vector2(-30, 60), Vector2(-20, 60)])
	var polygon := Feature.create_feature("Polygon")
	polygon.add_ring(first, Feature.GeometryKind.POLYGON)
	polygon.add_ring(second, Feature.GeometryKind.POLYGON)
	assert_close(Measure.geometry_area(polygon),
		Measure.ring_area(first) + Measure.ring_area(second), 1e-3, "two parts add")

	var polyline := Feature.create_feature("Polyline")
	polyline.add_ring(first, Feature.GeometryKind.POLYLINE)
	assert_eq(Measure.geometry_area(polyline), 0.0, "a line encloses nothing")
	assert_eq(Measure.geometry_area(null), 0.0, "and neither does nothing")


func test_the_planet_area() -> void:
	assert_eq(Measure.format_area(Measure.planet_area(6371.0)), "510.06 million km²")


func test_an_area_is_written_the_way_the_panels_show_it() -> void:
	assert_eq(Measure.format_area(0.0), "0.0 km²")
	assert_eq(Measure.format_area(123.44), "123.4 km²")
	assert_eq(Measure.format_area(1234.4), "1 234 km²")
	assert_eq(Measure.format_area(999999.0), "999 999 km²")
	assert_eq(Measure.format_area(1234567.0), "1.23 million km²")


func test_the_share_of_the_planet() -> void:
	var planet := Measure.planet_area(1000.0)
	assert_eq(Measure.format_share(planet * 0.002, 1000.0), "0.2 % of the planet")
	assert_eq(Measure.format_share(planet * 0.0004, 1000.0), "", "too little to write")


### Along an arc


func test_the_ends_of_an_arc_come_back_exactly() -> void:
	var a := Vector2(12.5, -30.25)
	var b := Vector2(-4.0, 88.0)
	assert_eq(Measure.along(a, b, 0.0), a, "nothing along is the start")
	assert_eq(Measure.along(a, b, 1.0), b, "all the way along is the end")
	assert_eq(Measure.along(a, b, -0.5), a, "and before the start is still the start")


# The tolerances here are 1e-5 relative rather than the 1e-4 the published
# values are held to, and they are limited by the vertex rather than by the
# arithmetic: a Vector2 is two 32-bit floats, which carry about seven digits, so
# a point 3700 km out lands to within a few centimetres of where it belongs.
func test_the_midpoint_of_an_arc_is_equally_far_from_both_ends() -> void:
	var a := Vector2(0, 0)
	var b := Vector2(40, 60)
	var whole := Measure.distance(a, b)
	var middle := Measure.along(a, b, 0.5)
	assert_close(Measure.distance(a, middle), Measure.distance(middle, b), whole * 1e-5,
		"the two halves are the same length")
	assert_close(Measure.distance(a, middle) * 2.0, whole, whole * 1e-5,
		"and together they are the whole")


func test_a_point_on_the_equator_stays_on_it() -> void:
	var middle := Measure.along(Vector2(0, -20), Vector2(0, 40), 0.5)
	assert_close(middle.x, 0.0, 1e-9, "the equator is a great circle, so the arc follows it")
	assert_close(middle.y, 10.0, 1e-6, "halfway between the two longitudes")


func test_a_quarter_of_the_way_is_a_quarter_of_the_angle() -> void:
	var a := Vector2(0, 0)
	var b := Vector2(0, 80)
	assert_close(Measure.along(a, b, 0.25).y, 20.0, 1e-6)


func test_the_fraction_along_finds_a_point_on_the_arc() -> void:
	var a := Vector2(0, 0)
	var b := Vector2(30, 50)
	var p := Measure.along(a, b, 0.3)
	assert_close(Measure.fraction_along(a, b, p), 0.3, 1e-6, "and back again")
	assert_close(Measure.fraction_along(a, b, a), 0.0, 1e-9, "the start is nothing along")
	assert_close(Measure.fraction_along(a, b, b), 1.0, 1e-6, "the end is all of it")


func test_the_fraction_stays_on_the_arc() -> void:
	# A point past b, which has no fraction of its own on the arc a to b.
	var a := Vector2(0, 0)
	var b := Vector2(0, 20)
	assert_close(Measure.fraction_along(a, b, Vector2(0, 50)), 1.0, 1e-9,
		"beyond the end is the end")


### Formatting


func test_a_distance_is_written_the_way_the_status_bar_shows_it() -> void:
	assert_eq(Measure.format_km(0.4), "400 m")
	assert_eq(Measure.format_km(12.345), "12.35 km")
	assert_eq(Measure.format_km(1234.5), "1234.5 km")
	assert_eq(Measure.format_km(20015.087), "20015 km")


func _assert_relative(got: float, wanted: float, message: String) -> void:
	assert_true(absf(got - wanted) <= absf(wanted) * RELATIVE,
		"%s: %s is not %s within one part in ten thousand" % [message, got, wanted])
