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


func test_leaf_without_optional_keys_gets_defaults() -> void:
	var leaf := Feature.from_json({"title": "Bare", "type": "Feature"})
	assert_eq(leaf.title, "Bare")
	assert_eq(leaf.is_group, false)
	assert_eq(leaf.enabled, true)
	assert_eq(leaf.repeat, false)
	assert_close(leaf.color, Color(0.82, 0.41, 0.12, 1.0), 1e-6, "default chocolate color")
	assert_eq(leaf.invert, false)
	assert_eq(leaf.single, false)
	assert_eq(leaf.wrap_, false)
	assert_eq(leaf.resize, 0)
	assert_eq(leaf.vertices.size(), 0)
	assert_eq(leaf.rotation_angles, Vector3.ZERO)
	assert_eq(leaf.time_range, Vector2i(0, 2000))


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


func _build_tree() -> Feature:
	var root := Feature.create_group("Planet")
	root.is_root = true

	var group := Feature.create_group("Cratons")
	root.children.append(group)

	var laurentia := Feature.create_feature("Laurentia", Color(0.25, 0.5, 0.75, 1.0))
	laurentia.vertices = [Vector2(-10, -10), Vector2(10, 0), Vector2(-10, 10)]
	laurentia.rotation_angles = Vector3(30, -20, 10)
	laurentia.time_range = Vector2i(540, 1800)
	group.children.append(laurentia)

	var baltica := Feature.create_feature("Baltica", Color(0.9, 0.1, 0.4, 0.5))
	baltica.vertices = [Vector2(20, 30), Vector2(40, 30), Vector2(40, 60)]
	baltica.rotation_angles = Vector3(-120, 45, 0)
	baltica.time_range = Vector2i(0, 750)
	baltica.enabled = false
	baltica.repeat = true
	baltica.invert = true
	baltica.single = true
	baltica.wrap_ = true
	baltica.resize = 3
	group.children.append(baltica)

	return root


func _assert_same_tree(a: Feature, b: Feature, path: String) -> void:
	assert_eq(a.title, b.title, "%s title" % path)
	assert_eq(a.enabled, b.enabled, "%s enabled" % path)
	assert_eq(a.repeat, b.repeat, "%s repeat" % path)
	assert_eq(a.is_group, b.is_group, "%s is_group" % path)
	if a.is_group:
		assert_eq(a.children.size(), b.children.size(), "%s child count" % path)
		for i in range(mini(a.children.size(), b.children.size())):
			_assert_same_tree(a.children[i], b.children[i], "%s/%d" % [path, i])
		return
	assert_close(a.color, b.color, 1e-6, "%s color" % path)
	assert_eq(a.invert, b.invert, "%s invert" % path)
	assert_eq(a.single, b.single, "%s single" % path)
	assert_eq(a.wrap_, b.wrap_, "%s wrap" % path)
	assert_eq(a.resize, b.resize, "%s resize" % path)
	assert_eq(a.vertices, b.vertices, "%s vertices" % path)
	assert_close(a.rotation_angles, b.rotation_angles, 1e-6, "%s rotation" % path)
	assert_eq(a.time_range, b.time_range, "%s time range" % path)
