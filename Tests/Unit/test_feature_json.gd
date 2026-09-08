extends TestCase

# Round-trip of the feature tree through the JSON representation used by
# the .middle-earth file format and the clipboard.


func test_round_trip_keeps_every_field() -> void:
	var original := _build_tree()
	var text := JSON.stringify(original.to_json())
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "the serialized tree must parse back into a dictionary")
	var restored := Feature.from_json(parsed)
	_assert_same_tree(original, restored, "root")


# Every kind whose vertices are drawn. A topology carries sections instead of
# rings and is round tripped in Tests/Unit/test_topology.gd.
func test_every_drawn_geometry_kind_survives_the_round_trip() -> void:
	for kind in Feature.DRAWN_KINDS:
		var original := Feature.create_feature("Shape")
		original.add_ring(PackedVector2Array([
			Vector2(0, 0), Vector2(0, 10), Vector2(10, 10)]), kind)
		var restored := Feature.from_json(JSON.parse_string(JSON.stringify(original.to_json())))
		assert_eq(restored.geometry_kind, kind, "the kind of a %s" % Feature.KIND_NAMES[kind])
		assert_eq(restored.rings, original.rings, "the rings of a %s" % Feature.KIND_NAMES[kind])
		assert_eq(restored.triangles, original.triangles,
			"the triangles of a %s are derived again on load" % Feature.KIND_NAMES[kind])


func test_a_polygon_of_several_rings_survives_the_round_trip() -> void:
	var original := Feature.create_feature("Two Islands")
	original.add_ring(PackedVector2Array([
		Vector2(0, 0), Vector2(0, 10), Vector2(10, 10)]), Feature.GeometryKind.POLYGON)
	original.add_ring(PackedVector2Array([
		Vector2(-30, -30), Vector2(-30, -20), Vector2(-20, -20), Vector2(-20, -30)]),
		Feature.GeometryKind.POLYGON)

	var restored := Feature.from_json(JSON.parse_string(JSON.stringify(original.to_json())))
	assert_eq(restored.rings.size(), 2, "both rings come back")
	assert_eq(restored.rings, original.rings, "with their vertices unchanged")
	assert_eq(restored.triangles.size(), 3 * 3, "one triangle and two, derived on load")


func test_leaf_without_optional_keys_gets_defaults() -> void:
	var leaf := Feature.from_json({"title": "Bare", "type": "Feature"})
	assert_eq(leaf.title, "Bare")
	assert_eq(leaf.is_group, false)
	assert_eq(leaf.enabled, true)
	assert_close(leaf.color, Color(0.82, 0.41, 0.12, 1.0), 1e-6, "default chocolate color")
	assert_eq(leaf.geometry_kind, Feature.GeometryKind.POLYGON)
	assert_eq(leaf.rings.size(), 0)
	assert_eq(leaf.triangles.size(), 0)
	assert_eq(leaf.has_geometry(), false)
	assert_eq(leaf.keyframes.size(), 0, "no keyframes, so it does not move")
	assert_eq(leaf.rotation_at(0.0), Vector3.ZERO)
	assert_eq(leaf.time_range, Vector2i(0, 2000))


func test_the_rule_editor_switches_are_gone() -> void:
	# 0.1.0 carried invert, single, wrap, resize and repeat, which nothing read.
	# A file that still holds them loads without them, see Tests/test_migration.gd.
	var data: Dictionary = _build_tree().children[0].children[0].to_json()
	for key in ["invert", "single", "wrap", "resize", "repeat"]:
		assert_true(not data.has(key), "a saved feature must no longer carry %s" % key)


func test_clone_keeps_pnid_and_duplicate_assigns_new_ones() -> void:
	var original := _build_tree()
	var group: Feature = original.children[0]

	var cloned := original.clone()
	assert_eq(cloned.pnid, original.pnid, "clone keeps the root pnid")
	assert_eq(cloned.children[0].pnid, group.pnid, "clone keeps child pnids")
	assert_eq(cloned.children[0].children[1].pnid, group.children[1].pnid, "clone keeps leaf pnids")
	_assert_same_tree(original, cloned, "clone")

	var copy := original.duplicate()
	assert_true(copy.pnid != original.pnid, "duplicate assigns a new root pnid")
	assert_true(copy.children[0].pnid != group.pnid, "duplicate assigns a new group pnid")
	assert_true(copy.children[0].children[0].pnid != group.children[0].pnid,
		"duplicate assigns a new leaf pnid")
	assert_true(copy.children[0].children[1].pnid != group.children[1].pnid,
		"duplicate assigns a new pnid to every leaf")
	assert_eq(copy.is_root, false, "a duplicate is never the root")
	_assert_same_tree(original, copy, "duplicate")


# The uuid is what a line topology names its sections by, so it has to mean the
# same node after a save and a load, and a different one after a duplicate.


func test_the_uuid_survives_the_round_trip() -> void:
	var original := _build_tree()
	var restored := Feature.from_json(JSON.parse_string(JSON.stringify(original.to_json())))
	_assert_same_uuids(original, restored, "root")
	assert_eq(_uuids(restored).size(), _flatten(restored).size(), "and they stay unique")


func test_clone_keeps_uuids_and_duplicate_gives_new_ones() -> void:
	var original := _build_tree()
	_assert_same_uuids(original, original.clone(), "clone")

	var copy := original.duplicate()
	var before := _uuids(original)
	for node in _flatten(copy):
		assert_true(not before.has(node.uuid),
			"%s must not keep the uuid it was duplicated from" % node.title)
	assert_eq(_uuids(copy).size(), _flatten(copy).size(),
		"and the duplicate's own uuids are unique")


func test_a_node_without_a_uuid_is_given_one() -> void:
	# Every file written before 0.5.0 is such a node, and so is one written by
	# hand. Nothing in those can be naming it, so a fresh id loses nothing.
	var leaf := Feature.from_json({"title": "Bare", "type": "Feature"})
	assert_true(not leaf.uuid.is_empty(), "a leaf that arrives without a uuid gets one")
	var other := Feature.from_json({"title": "Bare", "type": "Feature"})
	assert_true(leaf.uuid != other.uuid, "and two of them do not get the same one")


func _assert_same_uuids(a: Feature, b: Feature, path: String) -> void:
	assert_eq(a.uuid, b.uuid, "%s uuid" % path)
	for i in range(mini(a.children.size(), b.children.size())):
		_assert_same_uuids(a.children[i], b.children[i], "%s/%d" % [path, i])


func _flatten(node: Feature) -> Array[Feature]:
	var nodes: Array[Feature] = [node]
	for child in node.children:
		nodes.append_array(_flatten(child))
	return nodes


func _uuids(node: Feature) -> Dictionary:
	var seen := {}
	for one in _flatten(node):
		seen[one.uuid] = true
	return seen


func _build_tree() -> Feature:
	var root := Feature.create_group("Planet")
	root.is_root = true

	var group := Feature.create_group("Cratons")
	# A group carries motion of its own, which everything under it inherits.
	Keyframe.upsert(group.keyframes, 100.0, Vector3(5, 0, 0))
	root.children.append(group)

	var laurentia := Feature.create_feature("Laurentia", Color(0.25, 0.5, 0.75, 1.0))
	laurentia.add_ring(PackedVector2Array([
		Vector2(-10, -10), Vector2(10, 0), Vector2(-10, 10)]), Feature.GeometryKind.POLYGON)
	laurentia.feature_type = "craton"
	Keyframe.upsert(laurentia.keyframes, 0.0, Vector3(30, -20, 10))
	Keyframe.upsert(laurentia.keyframes, 750.5, Vector3(75, -20, 10))
	laurentia.time_range = Vector2i(540, 1800)
	group.children.append(laurentia)

	var ridge := Feature.create_feature("Ridge", Color(0.9, 0.1, 0.4, 0.5))
	ridge.add_ring(PackedVector2Array([
		Vector2(20, 30), Vector2(40, 30), Vector2(40, 60)]), Feature.GeometryKind.POLYLINE)
	ridge.feature_type = "ridge"
	Keyframe.upsert(ridge.keyframes, 0.0, Vector3(-120, 45, 0))
	ridge.time_range = Vector2i(0, 750)
	ridge.enabled = false
	group.children.append(ridge)

	var stations := Feature.create_feature("Stations", Color(0.1, 0.8, 0.2, 1.0))
	stations.feature_type = "marker"
	stations.add_ring(PackedVector2Array([Vector2(0, 0), Vector2(5, 5)]),
		Feature.GeometryKind.MULTIPOINT)
	group.children.append(stations)

	return root


func _assert_same_tree(a: Feature, b: Feature, path: String) -> void:
	assert_eq(a.title, b.title, "%s title" % path)
	assert_eq(a.enabled, b.enabled, "%s enabled" % path)
	assert_eq(a.is_group, b.is_group, "%s is_group" % path)
	_assert_same_keyframes(a, b, path)
	if a.is_group:
		assert_eq(a.children.size(), b.children.size(), "%s child count" % path)
		for i in range(mini(a.children.size(), b.children.size())):
			_assert_same_tree(a.children[i], b.children[i], "%s/%d" % [path, i])
		return
	assert_eq(a.feature_type, b.feature_type, "%s feature type" % path)
	assert_close(a.color, b.color, 1e-6, "%s color" % path)
	assert_eq(a.geometry_kind, b.geometry_kind, "%s geometry kind" % path)
	assert_eq(a.rings, b.rings, "%s rings" % path)
	assert_eq(a.triangles, b.triangles, "%s triangles" % path)
	assert_eq(a.time_range, b.time_range, "%s time range" % path)


func _assert_same_keyframes(a: Feature, b: Feature, path: String) -> void:
	assert_eq(a.keyframes.size(), b.keyframes.size(), "%s keyframe count" % path)
	for i in range(mini(a.keyframes.size(), b.keyframes.size())):
		assert_eq(a.keyframes[i].time, b.keyframes[i].time, "%s keyframe %d time" % [path, i])
		assert_close(a.keyframes[i].rotation, b.keyframes[i].rotation, 1e-6,
			"%s keyframe %d rotation" % [path, i])
