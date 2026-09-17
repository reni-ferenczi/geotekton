extends TestCase

# Hotspots: a point fixed in the world frame and the track it burns into a plate
# over the hotspot's time range, sampled at the hotspot's own time step or at
# the timeline's Skip when it carries none. See
# Logic/hotspot.gd and Document.set_hotspot().

const SCRATCH := "user://test_hotspot.middle-earth"
const SCRATCH_CONFIG := "user://test_hotspot_config"
const SKIP := 5.0

const ON_EQUATOR := Vector2(0.0, 0.0)
const TURN := 30.0


# A plate turning TURN degrees about the north pole between 30 Ma and the
# present, and a hotspot not placed yet that exists over the same span. The
# timeline's Skip is SKIP, in a config of the test's own, which _done() drops.
func _fixture() -> Array:
	Config.directory_override = ProjectSettings.globalize_path(SCRATCH_CONFIG)
	Config.clear()
	Config.set_skip_increment(SKIP)
	var document := Document.new()
	var plate := Feature.create_feature("Pacific")
	plate.add_ring(PackedVector2Array([Vector2(-10, -40), Vector2(-10, 40), Vector2(10, 0)]),
		Feature.GeometryKind.POLYGON)
	plate.keyframes.assign([Keyframe.create(0.0, Vector3(TURN, 0, 0)),
		Keyframe.create(30.0, Vector3.ZERO)])
	document.root.children.append(plate)
	var hotspot := Feature.create_feature("Hawaii")
	hotspot.time_range = Vector2i(0, 30)
	document.root.children.append(hotspot)
	document.record()
	assert_eq(document.set_feature_type(hotspot, FeatureType.HOTSPOT), "",
		"an empty feature takes the type")
	return [document, plate, hotspot]


func _done() -> void:
	DirAccess.remove_absolute(Config.directory_override + "/config.json")
	Config.directory_override = ""
	Config.forget()


# The ring around the hotspot, whatever the plate does.
func _check_mark(hotspot: Feature, label: String) -> void:
	assert_true(hotspot.rings.size() >= 1, "%s: there is a mark" % label)
	var mark := hotspot.rings[0]
	assert_eq(mark.size(), Hotspot.MARK_SEGMENTS + 1, "%s: the mark is a closed ring" % label)
	for vertex in mark:
		assert_close(Circle.radius_to(hotspot.hotspot, vertex), Hotspot.MARK_DEGREES, 1e-3,
			"%s: the mark sits around the hotspot" % label)


func test_picking_the_type_waits_for_the_place() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var hotspot: Feature = parts[2]
	assert_eq(hotspot.feature_type, FeatureType.HOTSPOT, "the feature is a hotspot")
	assert_eq(hotspot.color, FeatureType.color(FeatureType.HOTSPOT), "in the type's color")
	assert_true(not Hotspot.placed(hotspot), "not placed yet")
	assert_true(not hotspot.has_geometry(), "so it holds nothing")
	assert_eq(document.set_hotspot(hotspot, Feature.NO_HOTSPOT, (parts[1] as Feature).uuid, 0.0), "",
		"a plate can be picked before the place")
	assert_true(not hotspot.has_geometry(), "and still nothing is drawn")
	assert_eq(document.set_hotspot(hotspot, ON_EQUATOR, "", 0.0), "", "placed with no plate")
	assert_eq(hotspot.geometry_kind, Feature.GeometryKind.POLYLINE, "drawn as polylines")
	assert_eq(hotspot.rings.size(), 1, "with no plate only the mark")
	_check_mark(hotspot, "new")
	assert_true(not hotspot.has_own_vertices(), "none of its vertices can be taken hold of")
	_done()


# The example the developers were given: 100 My at a 30 My skip.
func test_the_ages_are_the_multiples_of_the_skip() -> void:
	assert_eq(Hotspot.sample_ages(30.0, 100.0, 0.0), PackedFloat64Array([100, 90, 60, 30, 0]),
		"a 100 My range at a 30 My skip")
	assert_eq(Hotspot.sample_ages(50.0, 100.0, 0.0), PackedFloat64Array([100, 50, 0]),
		"an oldest age on the grid is there once")
	assert_eq(Hotspot.sample_ages(30.0, 100.0, 45.0), PackedFloat64Array([100, 90, 60, 45]),
		"the current time closes the list")
	assert_eq(Hotspot.sample_ages(30.0, 100.0, 60.0), PackedFloat64Array([100, 90, 60]),
		"a time on the grid is there once")
	assert_eq(Hotspot.sample_ages(30.0, 100.0, 100.0), PackedFloat64Array([100]),
		"at the oldest age only the time")
	assert_eq(Hotspot.sample_ages(0.0001, 1.0, 0.0).size(), 11,
		"a skip finer than MIN_SKIP samples at MIN_SKIP")


func test_a_100_my_track_at_a_30_my_skip() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var plate: Feature = parts[1]
	var hotspot: Feature = parts[2]
	plate.time_range = Vector2i(0, 100)
	hotspot.time_range = Vector2i(0, 100)
	plate.keyframes.assign([Keyframe.create(0.0, Vector3(100.0, 0, 0)),
		Keyframe.create(100.0, Vector3.ZERO)])
	assert_eq(document.set_hotspot(hotspot, ON_EQUATOR, plate.uuid, 0.0), "", "on the plate")
	var track := Hotspot.track(document.root, hotspot, 0.0, 30.0)
	assert_eq(track.size(), 5, "100, 90, 60, 30 and the present")
	var ages := [100.0, 90.0, 60.0, 30.0, 0.0]
	for index in mini(track.size(), ages.size()):
		assert_close(Circle.radius_to(hotspot.hotspot, track[index]), ages[index], 1e-3,
			"the sample at %s Ma is as far as the plate turned since" % ages[index])
	_done()


# The step on the hotspot wins over whatever skip the caller hands down, and 0
# hands the decision back to the skip.
func test_a_hotspot_samples_at_its_own_step() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var plate: Feature = parts[1]
	var hotspot: Feature = parts[2]
	plate.time_range = Vector2i(0, 100)
	hotspot.time_range = Vector2i(0, 100)
	plate.keyframes.assign([Keyframe.create(0.0, Vector3(100.0, 0, 0)),
		Keyframe.create(100.0, Vector3.ZERO)])
	var versions := document.applied
	assert_eq(document.set_hotspot(hotspot, ON_EQUATOR, plate.uuid, 30.0), "", "given a 30 My step")
	assert_eq(document.applied, versions + 1, "as one undo version")
	assert_eq(hotspot.time_step, 30.0, "the hotspot carries it")
	for skip: float in [1.0, 5.0, 50.0, 1000.0]:
		assert_eq(Hotspot.step_of(hotspot, skip), 30.0, "step_of ignores a skip of %s" % skip)
		assert_eq(Hotspot.track(document.root, hotspot, 0.0, skip).size(), 5,
			"100, 90, 60, 30 and the present at a skip of %s" % skip)
	Hotspot.rebuild_all(document.root, 0.0, 1.0)
	assert_eq(hotspot.rings[1].size(), 5, "and a rebuild at a fine skip draws the same five")

	assert_eq(document.set_hotspot(hotspot, ON_EQUATOR, plate.uuid, 0.0), "", "back to 0")
	assert_eq(Hotspot.step_of(hotspot, 25.0), 25.0, "step_of follows the skip again")
	assert_eq(Hotspot.track(document.root, hotspot, 0.0, 25.0).size(), 5, "100 to 0 at 25 My")
	assert_eq(Hotspot.track(document.root, hotspot, 0.0, 50.0).size(), 3, "and three at 50")
	_done()


# Two hotspots in one document, each sampled at the step it carries.
func test_two_hotspots_hold_their_own_counts() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var plate: Feature = parts[1]
	var slow: Feature = parts[2]
	var fast := Feature.create_feature("Iceland")
	fast.time_range = Vector2i(0, 30)
	document.root.children.append(fast)
	assert_eq(document.set_feature_type(fast, FeatureType.HOTSPOT), "", "a second hotspot")
	assert_eq(document.set_hotspot(slow, ON_EQUATOR, plate.uuid, 10.0), "", "one at 10 My")
	assert_eq(document.set_hotspot(fast, ON_EQUATOR, plate.uuid, 5.0), "", "the other at 5")
	Hotspot.rebuild_all(document.root, 0.0, 1.0)
	assert_eq([Hotspot.samples(slow).size(), Hotspot.samples(fast).size()], [4, 7],
		"one rebuild leaves each with the samples its own step asks for")
	_done()


# 0 to MAX_STEP, and nothing outside it.
func test_a_step_outside_the_range_is_refused() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var plate: Feature = parts[1]
	var hotspot: Feature = parts[2]
	document.set_hotspot(hotspot, ON_EQUATOR, plate.uuid, 5.0)
	var versions := document.applied
	for bad: float in [-1.0, Hotspot.MAX_STEP + 1.0]:
		assert_true(not document.set_hotspot(hotspot, ON_EQUATOR, plate.uuid, bad).is_empty(),
			"a step of %s is refused" % bad)
	assert_eq(document.applied, versions, "nothing was recorded")
	assert_eq(hotspot.time_step, 5.0, "and the step it had is still there")
	assert_true(not document.set_crust_step(hotspot, 5.0).is_empty(),
		"a hotspot is no crust, so set_crust_step refuses it")
	_done()


func test_the_track_runs_along_the_equator_at_the_present() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var plate: Feature = parts[1]
	var hotspot: Feature = parts[2]
	var versions := document.applied
	assert_eq(document.set_hotspot(hotspot, ON_EQUATOR, plate.uuid, 0.0), "", "the plate is set")
	assert_eq(document.applied, versions + 1, "as one undo version")

	assert_eq(hotspot.rings.size(), 2, "the mark and the track")
	_check_mark(hotspot, "with a plate")
	var track := hotspot.rings[1]
	assert_eq(track.size(), 7, "30 My at a skip of 5, the present included")
	for vertex in track:
		assert_close(vertex.x, 0.0, 1e-3, "every sample is on the equator")
	assert_close(Circle.radius_to(hotspot.hotspot, track[0]), TURN, 1e-3,
		"the oldest sample is as far from the hotspot as the plate turned")
	assert_close(track[track.size() - 1], hotspot.hotspot, 1e-3,
		"the youngest is on the hotspot")
	for index in range(1, track.size()):
		assert_close(Circle.radius_to(track[index - 1], track[index]), SKIP, 1e-3,
			"samples are a skip apart")
	_done()


# Every sample of the track gets a small dot of its own, after the segments.
func test_every_sample_is_drawn_with_a_dot() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var hotspot: Feature = parts[2]
	document.set_hotspot(hotspot, ON_EQUATOR, (parts[1] as Feature).uuid, 0.0)
	var geometry := Planet.collect_geometry(document.root, 0.0)
	var samples: Array = geometry.primitives.filter(func(primitive: Dictionary) -> bool:
		return primitive["kind"] == Planet.Primitive.SAMPLE)
	assert_eq(samples.size(), 7, "one dot per sample")
	for i in mini(samples.size(), 7):
		assert_eq(samples[i]["feature"], hotspot, "dot %d belongs to the hotspot" % i)
		assert_close(samples[i]["verts"][0], hotspot.rings[1][i], 1e-9,
			"dot %d sits on its sample" % i)
	var index: int = geometry.index_of[hotspot]
	assert_eq(Planet._primitive_count(hotspot), geometry.ends[index] - geometry.starts[index],
		"the count made before building covers the dots")
	_done()


# A 2000 My range at a 5 My skip is 401 samples, each a segment and a dot.
func test_a_long_track_fits_the_geometry_texture() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var plate: Feature = parts[1]
	var hotspot: Feature = parts[2]
	plate.time_range = Vector2i(0, 2000)
	plate.keyframes.assign([Keyframe.create(0.0, Vector3(TURN, 0, 0)),
		Keyframe.create(2000.0, Vector3.ZERO)])
	hotspot.time_range = Vector2i(0, 2000)
	document.set_hotspot(hotspot, ON_EQUATOR, plate.uuid, 0.0)
	assert_eq(Hotspot.samples(hotspot).size(), 401, "401 samples")
	var geometry := Planet.collect_geometry(document.root, 0.0)
	assert_eq(geometry.dropped, 0, "nothing is left out")
	var index: int = geometry.index_of[hotspot]
	assert_eq(geometry.ends[index] - geometry.starts[index],
		Hotspot.MARK_SEGMENTS + 400 + 401, "the mark, the track and the dots")
	assert_true(geometry.primitives.size() <= Planet.MAX_PRIMITIVES, "within MAX_PRIMITIVES")
	_done()


func test_a_hotspot_draws_thin_lines_a_circle_thinner_ones_and_the_rest_full() -> void:
	var parts := _fixture()
	assert_close((parts[2] as Feature).line_scale(), 0.35, 1e-12, "a hotspot")
	assert_close((parts[1] as Feature).line_scale(), 1.0, 1e-12, "a polygon")
	var circle := Feature.create_feature("Ring")
	circle.feature_type = FeatureType.CIRCLE
	assert_close(circle.line_scale(), 0.5, 1e-12, "a circle")
	assert_close(Feature.create_group().line_scale(), 1.0, 1e-12, "a group")
	_done()


func test_at_the_oldest_age_there_is_no_track() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var hotspot: Feature = parts[2]
	document.set_hotspot(hotspot, ON_EQUATOR, (parts[1] as Feature).uuid, 0.0)
	assert_eq(Hotspot.track(document.root, hotspot, 30.0, SKIP).size(), 1, "one sample at 30 Ma")
	Hotspot.rebuild(document.root, hotspot, 30.0, SKIP)
	assert_eq(hotspot.rings.size(), 1, "so no track ring, only the mark")
	_check_mark(hotspot, "at 30 Ma")
	Hotspot.rebuild_all(document.root, 10.0, SKIP)
	assert_eq(hotspot.rings[1].size(), 5, "at 10 Ma the track has 5 samples")
	Hotspot.rebuild_all(document.root, 10.0, 10.0)
	assert_eq(hotspot.rings[1].size(), 3, "and 3 at a skip of 10")
	_done()


func test_with_no_plate_only_the_mark() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var hotspot: Feature = parts[2]
	assert_eq(document.set_hotspot(hotspot, Vector2(19.4, -155.3), "", 0.0), "", "no plate")
	assert_eq(hotspot.rings.size(), 1, "only the mark")
	_check_mark(hotspot, "no plate")
	assert_eq(Hotspot.track(document.root, hotspot, 0.0, SKIP).size(), 0, "and no track")
	assert_true(Hotspot.holds_any(document.root), "the tree holds a hotspot")
	document.root.children.pop_back()
	assert_true(not Hotspot.holds_any(document.root), "and does not once it is taken out")
	_done()


func test_bad_values_are_refused() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var plate: Feature = parts[1]
	var hotspot: Feature = parts[2]
	var group := Feature.create_group("Group")
	document.root.children.append(group)
	var empty := Feature.create_feature("Empty")
	document.root.children.append(empty)
	var versions := document.applied
	for bad: Array in [[Vector2(91, 0), plate.uuid], [Vector2(0, 181), plate.uuid],
			[ON_EQUATOR, hotspot.uuid], [ON_EQUATOR, group.uuid],
			[ON_EQUATOR, empty.uuid], [ON_EQUATOR, "no-such-uuid"]]:
		assert_true(not document.set_hotspot(hotspot, bad[0], bad[1], 0.0).is_empty(),
			"%s is refused" % [bad])
	assert_eq(document.applied, versions, "nothing was recorded")
	assert_true(not document.set_hotspot(plate, ON_EQUATOR, "", 0.0).is_empty(),
		"a feature of another type has no hotspot to set")
	assert_true(not document.set_feature_type(plate, FeatureType.HOTSPOT).is_empty(),
		"and one holding a shape cannot become a hotspot")
	var moving := Feature.create_feature("Moving")
	moving.keyframes.assign([Keyframe.create(0.0, Vector3(10, 0, 0))])
	document.root.children.append(moving)
	assert_true(not document.set_feature_type(moving, FeatureType.HOTSPOT).is_empty(),
		"nor one that moves")
	var shape := {"kind": Feature.GeometryKind.POLYLINE,
		"rings": [PackedVector2Array([Vector2(0, 0), Vector2(0, 10)])]}
	assert_true(not document.paste_shape(hotspot, shape).is_empty(), "a paste is refused")
	_done()


func test_the_file_round_trips_the_place_and_the_plate() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var plate: Feature = parts[1]
	var hotspot: Feature = parts[2]
	document.set_hotspot(hotspot, Vector2(19.4, -155.3), plate.uuid, 0.0)
	assert_eq(document.save_to_file(SCRATCH), "", "the document is written")

	var file := FileAccess.open(SCRATCH, FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	assert_eq(raw["version"], "0.25.0", "at the current version")
	var leaf: Dictionary = raw["features"]["children"][1]
	assert_close(Vector2(leaf["hotspot"][0], leaf["hotspot"][1]), Vector2(19.4, -155.3), 1e-4,
		"the place is written")
	assert_eq(leaf["plate"], plate.uuid, "so is the plate")
	assert_true(not leaf.has("track_step"), "and no track step")
	assert_eq((leaf["rings"] as Array).size(), 2, "the two rings are written for other readers")
	var plain: Dictionary = raw["features"]["children"][0]
	for key in ["hotspot", "plate", "track_step"]:
		assert_true(not plain.has(key), "a polygon writes no %s" % key)

	var reloaded := Document.new()
	assert_eq(reloaded.load_from_file(SCRATCH), "", "the file loads back")
	var back: Feature = reloaded.root.children[1]
	assert_eq(back.feature_type, FeatureType.HOTSPOT, "as a hotspot")
	assert_close(back.hotspot, Vector2(19.4, -155.3), 1e-4, "at the same place")
	assert_eq(back.plate_uuid, plate.uuid, "on the same plate")
	var clone := back.clone()
	assert_eq([clone.hotspot, clone.plate_uuid, clone.time_step],
		[back.hotspot, back.plate_uuid, back.time_step], "a clone keeps the values")

	# The parameters win over the rings the file holds.
	back.rings.assign([PackedVector2Array([Vector2(0, 0), Vector2(0, 10)])])
	Hotspot.rebuild_all(reloaded.root, 0.0, SKIP)
	assert_eq(back.rings[1].size(), 7, "the track is rebuilt from them")
	for index in back.rings[1].size():
		assert_close(back.rings[1][index], hotspot.rings[1][index], 1e-4,
			"vertex %d of the track comes back" % index)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	_done()


# A hotspot not placed yet writes no place and reads back as not placed.
func test_a_hotspot_not_placed_round_trips() -> void:
	var parts := _fixture()
	var document: Document = parts[0]
	var hotspot: Feature = parts[2]
	var data: Dictionary = hotspot.to_json()
	assert_true(not data.has("hotspot"), "no place is written")
	assert_eq(data["plate"], "", "the plate is")
	var back := Feature.from_json(data)
	assert_true(back.is_hotspot() and not Hotspot.placed(back), "it comes back not placed")
	Hotspot.rebuild_all(document.root, 0.0, SKIP)
	assert_true(not hotspot.has_geometry(), "and a rebuild draws nothing")
	_done()
