extends TestCase

# Document.migrate brings an older file up to the format this version writes.
# 0.2.0 turned the flat triangle list of each leaf into the outline those
# triangles cover and dropped the five rule editor switches; 0.4.0 turned the
# one rotation a leaf carried into the keyframe at time zero. The samples in
# Tests/Data are still written in 0.1.0, so they run through both steps.

const DATA_DIR := "res://Tests/Data"
const OLD_SAMPLES := ["triangle.middle-earth", "two_cratons.middle-earth", "empty.middle-earth"]

# Two triangles sharing an edge, so their outline is one quad, and one triangle
# far away from them, so the feature ends up with two rings.
const TWO_RINGS := [
	[0.0, 0.0], [0.0, 20.0], [20.0, 20.0],
	[0.0, 0.0], [20.0, 20.0], [20.0, 0.0],
	[-40.0, -40.0], [-40.0, -20.0], [-20.0, -20.0],
]


func test_the_samples_keep_the_edges_their_triangles_left_on_the_boundary() -> void:
	for file_name in OLD_SAMPLES:
		var raw := _read("%s/%s" % [DATA_DIR, file_name])
		if raw.is_empty():
			continue
		assert_eq(str(raw.get("version", "")), "0.1.0", "%s is a 0.1.0 file" % file_name)

		var before: Array = []
		_collect_leaves(raw["features"], before)
		var migrated := Document.migrate(raw.duplicate(true))
		assert_eq(str(migrated["version"]), "0.4.0", "%s is migrated to 0.4.0" % file_name)

		var after: Array = []
		_collect_leaves(migrated["features"], after)
		assert_eq(after.size(), before.size(), "%s keeps every leaf" % file_name)

		for i in range(mini(before.size(), after.size())):
			var label := "%s leaf %d" % [file_name, i]
			var triangles: Array = before[i].get("vertices", [])
			assert_eq(after[i].get("geometry_kind", ""), "polygon", "%s is a polygon" % label)
			assert_eq(_boundary_edges(triangles), _ring_edges(after[i]["rings"]),
				"%s recovers the outline of its triangles" % label)

			# The outline covers the same area: triangulating it again gives the
			# same number of triangles the file held.
			var feature := Feature.from_json(after[i])
			assert_eq(feature.triangles.size(), triangles.size(),
				"%s triangulates back to the same triangle count" % label)


func test_a_feature_of_two_separate_polygons_becomes_two_rings() -> void:
	var leaf := _migrate_leaf({"type": "Feature", "title": "Islands", "vertices": TWO_RINGS})
	var rings: Array = leaf["rings"]
	assert_eq(rings.size(), 2, "one ring per polygon")
	var sizes := [rings[0].size(), rings[1].size()]
	sizes.sort()
	assert_eq(sizes, [3, 4], "a triangle and the quad the two shared triangles cover")
	assert_eq(_boundary_edges(TWO_RINGS), _ring_edges(rings),
		"both outlines are the edges used by a single triangle")


func test_the_rule_editor_switches_are_dropped() -> void:
	var leaf := _migrate_leaf({
		"type": "Feature", "title": "Old", "vertices": [],
		"invert": true, "single": true, "wrap": true, "resize": 2, "repeat": true,
	})
	for key in ["invert", "single", "wrap", "resize", "repeat"]:
		assert_true(not leaf.has(key), "the %s switch is dropped" % key)


func test_a_group_is_migrated_through_its_children() -> void:
	var migrated := Document.migrate({"version": "0.1.0", "features": {
		"type": "Group", "title": "Planet", "repeat": true, "children": [
			{"type": "Feature", "title": "Craton", "vertices": TWO_RINGS.slice(0, 3)},
		],
	}})
	var group: Dictionary = migrated["features"]
	assert_true(not group.has("repeat"), "the switch is dropped on a group too")
	assert_eq(group["children"][0]["rings"].size(), 1, "the child is migrated as well")


func test_the_oldest_files_called_the_rotation_a_position() -> void:
	var leaf := _migrate_leaf({
		"type": "Feature", "title": "Old", "vertices": [], "position": [10.0, 20.0, 30.0]})
	assert_eq(_only_keyframe(leaf).get("rotation", []), [10.0, 20.0, 30.0],
		"the position becomes the rotation of the keyframe at time zero")
	assert_true(not leaf.has("position"), "and the old key is gone")


func test_the_one_rotation_of_a_0_3_0_leaf_becomes_the_keyframe_at_time_zero() -> void:
	var leaf := _migrate_0_3_0({
		"type": "Feature", "title": "Craton", "geometry_kind": "polygon",
		"rings": [[[0.0, 0.0], [0.0, 10.0], [10.0, 10.0]]], "rotation": [60.0, 0.0, 0.0],
	})
	assert_true(not leaf.has("rotation"), "the single rotation is gone")
	var keyframe := _only_keyframe(leaf)
	assert_eq(keyframe.get("time", -1.0), 0.0, "the keyframe is at the present")
	assert_eq(keyframe.get("rotation", []), [60.0, 0.0, 0.0], "and holds what the file said")

	# A feature that came in this way behaves as it did before the phase: one
	# keyframe holds its rotation whatever time it is asked about.
	var feature := Feature.from_json(leaf)
	for time in [0.0, 500.0, 2000.0]:
		assert_close(feature.rotation_at(time), Vector3(60, 0, 0), 1e-6,
			"one keyframe holds at %s Ma" % time)


func test_a_group_arrives_without_keyframes() -> void:
	var group := _migrate_0_3_0({
		"type": "Group", "title": "Planet", "children": [
			{"type": "Feature", "title": "Craton", "rings": [], "rotation": [1.0, 2.0, 3.0]},
		],
	})
	assert_eq(group.get("keyframes", []), [], "a group had no rotation to carry over")
	assert_eq(_only_keyframe(group["children"][0]).get("rotation", []), [1.0, 2.0, 3.0],
		"but the leaf under it did")


func test_a_file_already_at_0_4_0_is_left_alone() -> void:
	var data := {"version": "0.4.0", "features": {
		"type": "Feature", "title": "New", "geometry_kind": "polyline",
		"rings": [[[0.0, 0.0], [0.0, 10.0]]],
		"keyframes": [{"time": 0.0, "rotation": [0.0, 0.0, 0.0]}],
	}}
	assert_eq(Document.migrate(data.duplicate(true)), data)


func test_version_ordering() -> void:
	assert_true(Document._is_older_than("0.1.0", "0.2.0"))
	assert_true(Document._is_older_than("0.1", "0.2.0"))
	assert_true(not Document._is_older_than("0.2.0", "0.2.0"))
	assert_true(not Document._is_older_than("0.2", "0.2.0"))
	assert_true(not Document._is_older_than("1.0.0", "0.2.0"))
	assert_true(Document._is_older_than("0.3.0", "0.4.0"))


### Helpers


func _migrate_leaf(leaf: Dictionary) -> Dictionary:
	return Document.migrate({"version": "0.1.0", "features": leaf})["features"]


func _migrate_0_3_0(node: Dictionary) -> Dictionary:
	return Document.migrate({"version": "0.3.0", "features": node})["features"]


# The one keyframe a migrated leaf is expected to carry.
func _only_keyframe(leaf: Dictionary) -> Dictionary:
	var list: Array = leaf.get("keyframes", [])
	if list.size() != 1:
		fail("expected one keyframe, found %d" % list.size())
		return {}
	return list[0]


# The edges a triangle soup uses exactly once, as "a|b" with the two vertices
# in a fixed order, so the set does not depend on the direction of an edge.
func _boundary_edges(vertices: Array) -> Array:
	var counts := {}
	for t in range(vertices.size() / 3):
		for e in range(3):
			var key := _edge(vertices[t * 3 + e], vertices[t * 3 + (e + 1) % 3])
			counts[key] = int(counts.get(key, 0)) + 1
	var edges: Array = []
	for key in counts:
		if int(counts[key]) == 1:
			edges.append(key)
	edges.sort()
	return edges


# The edges of the recovered rings, in the same form.
func _ring_edges(rings: Array) -> Array:
	var edges: Array = []
	for ring in rings:
		for i in range(ring.size()):
			edges.append(_edge(ring[i], ring[(i + 1) % ring.size()]))
	edges.sort()
	return edges


func _edge(a: Array, b: Array) -> String:
	var first := "%.6f,%.6f" % [a[0], a[1]]
	var second := "%.6f,%.6f" % [b[0], b[1]]
	return "%s|%s" % [first, second] if first < second else "%s|%s" % [second, first]


func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail("cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		fail("%s is not a JSON object" % path)
		return {}
	return parsed


func _collect_leaves(node: Variant, leaves: Array) -> void:
	if node is not Dictionary:
		return
	if node.get("is_group", node.get("type") == "Group"):
		for child in node.get("children", []):
			_collect_leaves(child, leaves)
		return
	leaves.append(node)
