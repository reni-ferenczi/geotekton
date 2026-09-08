extends TestCase

# What the kinematics panel graphs: where the middle of a feature is over time
# and how fast it turns between its keyframes. Logic/kinematics.gd needs no
# scene, so all of it is checked here rather than through the port.

# A radius that is not the Earth's, so a distance worked out from it cannot
# accidentally agree with one that used the default.
const RADIUS := 1000.0

# Two rotations far enough apart that the turn between them is not a small
# angle, and about two different axes, so a rate worked out from one alone
# would be wrong.
const FIRST := Vector3(0, 0, 0)
const SECOND := Vector3(-30, 10, 0)


### The middle of a feature


func test_the_middle_of_a_triangle_is_the_middle_of_its_vertices() -> void:
	var feature := _feature([Vector2(-10, -10), Vector2(10, 0), Vector2(-10, 10)])
	var middle := Kinematics.centroid(feature)
	assert_close(middle.length(), 1.0, 1e-6, "the middle is a point on the sphere")

	var total := Vector3.ZERO
	for vertex in feature.rings[0]:
		total += Feature._latlon_to_xyz_s(vertex)
	assert_close(middle, total.normalized(), 1e-6, "and it is the mean of the vertices")


func test_a_feature_whose_vertices_cancel_out_still_has_a_middle() -> void:
	# A marker at each pole: the two add up to nothing, and a middle worked out
	# by normalizing that would be a division by zero.
	var feature := _feature([Vector2(90, 0), Vector2(-90, 0)])
	feature.geometry_kind = Feature.GeometryKind.MULTIPOINT
	assert_close(Kinematics.centroid(feature).length(), 1.0, 1e-6,
		"the first vertex stands in for the middle there is not")


func test_only_a_feature_holding_vertices_has_a_path() -> void:
	var root := Feature.create_group("Planet")
	root.is_root = true
	var feature := _feature([Vector2(-10, -10), Vector2(10, 0), Vector2(-10, 10)])
	var empty := Feature.create_feature("Empty")
	var topology := Feature.create_feature("Boundary")
	topology.geometry_kind = Feature.GeometryKind.TOPOLOGY
	topology.sections.append(TopologySection.create(feature.uuid, 0, 0, 2))

	assert_true(Kinematics.can_graph(feature), "a feature with geometry has a path")
	assert_true(not Kinematics.can_graph(root), "a group has no geometry of its own")
	assert_true(not Kinematics.can_graph(empty), "a feature without geometry has nothing to follow")
	assert_true(not Kinematics.can_graph(null), "and neither has nothing at all")
	assert_true(not Kinematics.can_graph(topology),
		"a topology borrows its vertices, so its own rotation does not carry them")


### The path over time


func test_the_path_samples_the_span_from_the_oldest_end_to_the_youngest() -> void:
	var samples := Kinematics.path(_planet(_moving_feature()), _selected, 1000.0, 0.0, 5)
	var times: Array = []
	for sample in samples:
		times.append(sample["time"])
	assert_eq(str(times), str([1000.0, 750.0, 500.0, 250.0, 0.0]),
		"five samples, oldest first, which is left to right on the graph")


func test_every_sample_is_where_the_keyframes_put_the_feature() -> void:
	var feature := _moving_feature()
	var root := _planet(feature)
	var middle := Kinematics.centroid(feature)

	for sample in Kinematics.path(root, feature, 1000.0, 0.0, 37):
		# Worked out from the interpolation itself rather than from the path
		# being tested: the rotation the keyframes give at that time, applied
		# to the middle of the feature.
		var rotation := Keyframe.interpolate(feature.keyframes, float(sample["time"]))
		var wanted := Feature._xyz_to_latlon_s(
			Feature.build_rotation_basis(rotation) * middle)
		assert_close(Vector2(sample["lat"], sample["lon"]), wanted, 1e-4,
			"the sample at %s Ma" % sample["time"])


func test_a_feature_inside_a_moving_group_is_carried_by_it() -> void:
	var feature := _feature([Vector2(-10, -10), Vector2(10, 0), Vector2(-10, 10)])
	var group := Feature.create_group("Plates")
	group.children.append(feature)
	Keyframe.upsert(group.keyframes, 0.0, FIRST)
	Keyframe.upsert(group.keyframes, 500.0, SECOND)
	var root := Feature.create_group("Planet")
	root.is_root = true
	root.children.append(group)

	var samples := Kinematics.path(root, feature, 500.0, 0.0, 3)
	var wanted := Feature._xyz_to_latlon_s(
		Feature.world_basis(root, feature, 500.0) * Kinematics.centroid(feature))
	assert_close(Vector2(samples[0]["lat"], samples[0]["lon"]), wanted, 1e-4,
		"the group's rotation reaches the feature under it")
	assert_true(absf(float(samples[0]["lon"]) - float(samples[2]["lon"])) > 1.0,
		"a feature of its own that never moves still has a path")


func test_a_span_that_is_not_a_span_has_no_path() -> void:
	var feature := _moving_feature()
	var root := _planet(feature)
	assert_eq(Kinematics.path(root, feature, 0.0, 0.0, 10).size(), 0, "the two ends are one")
	assert_eq(Kinematics.path(root, feature, 1000.0, 0.0, 1).size(), 0, "one sample is no line")


### The rate between keyframes


func test_the_rate_is_the_angle_over_the_time_between_two_keyframes() -> void:
	var feature := _moving_feature()
	var segments := Kinematics.segments(_planet(feature), feature, RADIUS)
	assert_eq(segments.size(), 1, "two keyframes make one span")
	if segments.is_empty():
		return

	var turn := Quaternion(Feature.build_rotation_basis(FIRST)).angle_to(
		Quaternion(Feature.build_rotation_basis(SECOND)))
	assert_close(float(segments[0]["degrees_per_my"]), rad_to_deg(turn) / 1000.0, 1e-9,
		"the angle between the two keyframes over the time between them")
	assert_close(float(segments[0]["km_per_my"]), turn / 1000.0 * RADIUS, 1e-9,
		"and the distance that angle covers on a planet of this radius")
	assert_eq(str([segments[0]["from"], segments[0]["to"]]), str([0.0, 1000.0]),
		"the span runs from the younger keyframe to the older one")


func test_a_feature_that_has_been_moved_once_does_not_move_at_all() -> void:
	var feature := _feature([Vector2(-10, -10), Vector2(10, 0), Vector2(-10, 10)])
	Keyframe.upsert(feature.keyframes, 500.0, SECOND)
	var segments := Kinematics.segments(_planet(feature), feature, RADIUS)
	assert_eq(segments.size(), 0, "one keyframe is no span")

	var rate := Kinematics.rate_at(segments, 500.0)
	assert_close(float(rate["degrees_per_my"]), 0.0, 1e-9, "so it turns at nothing")
	assert_close(float(rate["km_per_my"]), 0.0, 1e-9, "and covers nothing")
	assert_close(Kinematics.peak_rate(segments), 0.0, 1e-9, "and there is no peak to scale by")


func test_the_rate_is_read_off_the_span_the_time_falls_in() -> void:
	var feature := _moving_feature()
	Keyframe.upsert(feature.keyframes, 2000.0, Vector3(-100, -20, 0))
	var segments := Kinematics.segments(_planet(feature), feature, RADIUS)
	assert_eq(segments.size(), 2, "three keyframes make two spans")
	if segments.size() < 2:
		return

	assert_close(float(Kinematics.rate_at(segments, 400.0)["degrees_per_my"]),
		float(segments[0]["degrees_per_my"]), 1e-9, "inside the younger span")
	assert_close(float(Kinematics.rate_at(segments, 1500.0)["degrees_per_my"]),
		float(segments[1]["degrees_per_my"]), 1e-9, "inside the older one")
	assert_close(float(Kinematics.rate_at(segments, 1000.0)["degrees_per_my"]),
		float(segments[0]["degrees_per_my"]), 1e-9,
		"a time where two spans meet belongs to the younger of them")
	assert_close(float(Kinematics.rate_at(segments, 2500.0)["degrees_per_my"]), 0.0, 1e-9,
		"older than every keyframe the feature stands still")
	assert_close(Kinematics.peak_rate(segments),
		maxf(float(segments[0]["degrees_per_my"]), float(segments[1]["degrees_per_my"])),
		1e-9, "the peak is the faster of the two")


func test_the_times_a_node_turns_at_include_the_ones_it_inherits() -> void:
	var feature := _moving_feature()
	var group := Feature.create_group("Plates")
	group.children.append(feature)
	Keyframe.upsert(group.keyframes, 250.0, FIRST)
	Keyframe.upsert(group.keyframes, 750.0, SECOND)
	var root := Feature.create_group("Planet")
	root.is_root = true
	root.children.append(group)

	assert_eq(str(Kinematics.motion_times(root, feature)),
		str(PackedFloat64Array([0.0, 250.0, 750.0, 1000.0])),
		"its own keyframes and the group's, sorted, youngest first")
	assert_eq(Kinematics.segments(root, feature, RADIUS).size(), 3,
		"which is one span more than either list makes on its own")


### The sample file


func test_the_motion_sample_moves_faster_the_further_back_it_goes() -> void:
	var document := Document.new()
	var error := document.load_from_file("res://Tests/Data/motion.middle-earth")
	assert_eq(error, "", "the sample loads")
	var feature := document.root.get_node_by_uuid("5e0c9a71-2f48-4d13-8b6a-7c0e42f1d95b")
	assert_true(feature != null, "and holds the feature the graphs are drawn for")
	if feature == null:
		return

	var segments := Kinematics.segments(document.root, feature, Measure.EARTH_RADIUS_KM)
	assert_eq(segments.size(), 2, "three keyframes, two spans")
	if segments.size() < 2:
		return
	assert_true(float(segments[1]["degrees_per_my"]) > float(segments[0]["degrees_per_my"]) * 1.5,
		"the older span is clearly the faster of the two, so the two bars differ")


### Helpers


# The last feature _planet() was given, so a test can pass it on without
# holding it in a variable of its own.
var _selected: Feature = null


func _feature(vertices: Array[Vector2]) -> Feature:
	var feature := Feature.create_feature("Craton")
	var ring := PackedVector2Array(vertices)
	feature.add_ring(ring, Feature.GeometryKind.POLYGON)
	return feature


# A triangle that turns from one rotation to the other over a thousand million
# years.
func _moving_feature() -> Feature:
	var feature := _feature([Vector2(-10, -10), Vector2(10, 0), Vector2(-10, 10)])
	Keyframe.upsert(feature.keyframes, 0.0, FIRST)
	Keyframe.upsert(feature.keyframes, 1000.0, SECOND)
	return feature


# A root group holding one feature, which is the smallest tree a rotation can be
# resolved through.
func _planet(feature: Feature) -> Feature:
	var root := Feature.create_group("Planet")
	root.is_root = true
	root.children.append(feature)
	_selected = feature
	return root
