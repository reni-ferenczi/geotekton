extends TestCase

# Document.migrate brings an older file up to the format this version writes.
# 0.2.0 turned the flat triangle list of each leaf into the outline those
# triangles cover and dropped the five rule editor switches; 0.4.0 turned the
# one rotation a leaf carried into the keyframe at time zero; 0.8.0 folded the
# keyframes of groups into the leaves under them; 0.9.0 cut eight feature types
# down to five; 0.10.0 moved the draw style onto the root group. The samples in
# Tests/Data are still written in 0.1.0, so they run through every step.

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
		assert_eq(str(migrated["version"]), "0.11.0", "%s is migrated to 0.11.0" % file_name)

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


func test_a_leaf_at_0_4_0_under_no_moving_group_is_left_alone() -> void:
	var data := {"version": "0.4.0", "features": {
		"type": "Feature", "title": "New", "geometry_kind": "polyline",
		"rings": [[[0.0, 0.0], [0.0, 10.0]]],
		"keyframes": [{"time": 0.0, "rotation": [0.0, 0.0, 0.0]}],
	}}
	var migrated := Document.migrate(data.duplicate(true))
	var expected: Dictionary = data["features"].duplicate(true)
	expected["feature_type"] = FeatureType.NONE
	assert_eq(migrated["features"], expected, "the leaf is as it was, its type left to its geometry")
	assert_eq(migrated["version"], "0.11.0", "at the current version")


### 0.7.0 to 0.8.0: groups stop carrying motion


func test_a_moving_group_is_folded_into_its_leaves() -> void:
	# The group turns 30 degrees about the poles and the terrane 20 of its own,
	# both by 100 Ma, which up to 0.7.0 put the terrane at 50 degrees then.
	var migrated := Document.migrate({"version": "0.7.0", "features": {
		"type": "Group", "title": "Planet", "children": [{
			"type": "Group", "title": "Craton",
			"keyframes": [
				{"time": 0.0, "rotation": [0.0, 0.0, 0.0]},
				{"time": 100.0, "rotation": [30.0, 0.0, 0.0]}],
			"children": [{
				"type": "Feature", "title": "Terrane", "rings": [],
				"keyframes": [
					{"time": 0.0, "rotation": [0.0, 0.0, 0.0]},
					{"time": 100.0, "rotation": [20.0, 0.0, 0.0]}],
			}],
		}],
	}})
	var craton: Dictionary = migrated["features"]["children"][0]
	assert_true(not craton.has("keyframes"), "the group's keyframes are gone")
	var terrane: Dictionary = craton["children"][0]
	var times: Array = []
	for keyframe in terrane["keyframes"]:
		times.append(keyframe["time"])
	assert_eq(times, [0.0, 100.0], "the terrane keeps its keyframe times")
	assert_close(Vector3(terrane["keyframes"][1]["rotation"][0], 0.0, 0.0), Vector3(50, 0, 0), 1e-6,
		"and holds where the group had put it at 100 Ma: %s" % [terrane["keyframes"][1]])


func test_a_still_leaf_takes_its_moving_group_s_keyframes() -> void:
	var migrated := Document.migrate({"version": "0.7.0", "features": {
		"type": "Group", "title": "Planet",
		"keyframes": [{"time": 200.0, "rotation": [0.0, 45.0, 0.0]}],
		"children": [{"type": "Feature", "title": "Rider", "rings": [], "keyframes": []}],
	}})
	var rider: Dictionary = migrated["features"]["children"][0]
	assert_eq(rider["keyframes"].size(), 1, "one keyframe, from the root's one")
	assert_close(rider["keyframes"][0]["time"], 200.0, 1e-9)
	var rotation: Array = rider["keyframes"][0]["rotation"]
	assert_close(Vector3(rotation[0], rotation[1], rotation[2]), Vector3(0, 45, 0), 1e-6,
		"and it is the root's rotation")
	assert_true(not migrated["features"].has("keyframes"), "the root has none any more")


func test_a_leaf_under_a_still_group_is_left_alone() -> void:
	var leaf := {"type": "Feature", "title": "Alone", "rings": [],
		"keyframes": [{"time": 0.0, "rotation": [1.0, 2.0, 3.0]}]}
	var migrated := Document.migrate({"version": "0.7.0", "features": {
		"type": "Group", "title": "Planet", "keyframes": [], "children": [leaf.duplicate(true)],
	}})
	assert_eq(migrated["features"]["children"][0], leaf.merged({"feature_type": FeatureType.NONE}),
		"nothing above it moved, so it is as it was, its type left to its geometry")


### 0.8.0 to 0.9.0: five feature types


# The old type, the kind the feature holds, and the type it opens as.
const OLD_TYPES := [
	["craton", "polygon", "polygon"],
	["terrane", "polygon", "polygon"],
	["coastline", "polygon", "polygon"],
	["coastline", "polyline", "line"],
	["ridge", "polyline", "line"],
	["marker", "multipoint", "points"],
	["small_circle", "polygon", "circle"],
	["small_circle", "polyline", "circle"],
	["unclassified", "polygon", "polygon"],
	["unclassified", "polyline", "line"],
	["unclassified", "multipoint", "points"],
	["volcano", "polygon", "polygon"],
]


func test_a_0_7_0_file_opens_each_old_type_as_one_of_the_five() -> void:
	var children: Array = []
	for entry in OLD_TYPES:
		children.append({"type": "Feature", "title": "%s as %s" % [entry[0], entry[1]],
			"uuid": "uuid-%d" % children.size(), "feature_type": entry[0],
			"geometry_kind": entry[1], "rings": [[[0.0, 0.0], [0.0, 10.0], [10.0, 0.0]]]})
	children.append({"type": "Feature", "title": "Boundary", "feature_type": "topology",
		"geometry_kind": "topology",
		"sections": [{"feature": "uuid-4", "part": 0, "from": 0, "to": 2, "reversed": false}]})
	children.append({"type": "Feature", "title": "Empty", "feature_type": "craton", "rings": []})

	var migrated := Document.migrate({"version": "0.7.0",
		"features": {"type": "Group", "title": "Planet", "children": children},
		"view": {"hidden_classes": ["small_circles", "points"]}})
	assert_eq(migrated["version"], "0.11.0", "at the current version")
	var root := Feature.from_json(migrated["features"])
	for i in OLD_TYPES.size():
		assert_eq(root.children[i].feature_type, OLD_TYPES[i][2], root.children[i].title)
	assert_eq(root.children[-2].feature_type, "topology", "a topology stays one")
	assert_eq(root.children[-1].feature_type, FeatureType.NONE, "a feature holding nothing has no type")
	assert_eq(Array(ViewSettings.from_json(migrated["view"]).hidden_classes), ["circles", "points"],
		"and the circles are still switched off")


# Every sample opens with the type its geometry gives, whichever format it is in
# and whatever type it names; none of them holds a circle.
func test_every_sample_opens_with_one_of_the_five() -> void:
	var names := DirAccess.get_files_at(DATA_DIR)
	var opened := 0
	for file_name in names:
		if not file_name.ends_with(".middle-earth"):
			continue
		var document := Document.new()
		var error := document.load_from_file("%s/%s" % [DATA_DIR, file_name])
		assert_eq(error, "", "%s opens" % file_name)
		opened += 1
		var stack: Array[Feature] = [document.root]
		while not stack.is_empty():
			var node: Feature = stack.pop_back()
			stack.append_array(node.children)
			if node.is_group:
				continue
			assert_eq(node.feature_type, FeatureType.resolve(FeatureType.NONE, node.kind_name()),
				"%s in %s" % [node.title, file_name])
			assert_true(FeatureType.CATALOG.has(node.feature_type), "which is in the catalog")
	assert_true(opened >= 7, "every sample was opened: %d" % opened)


### 0.9.0 to 0.10.0: the draw style becomes the root group's


# The three styling keys of a 0.7.0 view block land on the root group, and a
# document opened from it draws with them.
func test_a_0_7_0_draw_style_becomes_the_style_of_the_root_group() -> void:
	var migrated := Document.migrate({"version": "0.7.0",
		"features": {"type": "Group", "title": "Planet", "children": []},
		"view": {"draw_style": "single", "single_color": [0.1, 0.6, 0.9, 0.75],
			"palette": "steps", "ambient": 0.25}})
	for key in GroupStyle.VIEW_KEYS:
		assert_true(not migrated["view"].has(key), "%s has left the view block" % key)
	assert_eq(migrated["view"]["ambient"], 0.25, "and the rest of the block stays")
	var root := Feature.from_json(migrated["features"])
	assert_eq(root.style.mode, Styling.BY_SINGLE, "the root carries the style")
	assert_eq(root.style.color, Color(0.1, 0.6, 0.9, 0.75), "the single colour, alpha and all")
	assert_eq(root.style.palette, "steps", "the palette")
	assert_eq(root.style.opacity, 1.0, "at full opacity, so it draws the same")


# A block that named no style leaves the root on the default, and so does a
# style that no version knew, which is what the view block did with one.
func test_a_block_without_a_style_leaves_the_root_on_its_own_colours() -> void:
	var path := ProjectSettings.globalize_path("user://test_migration_0_9_0.middle-earth")
	for view in [{}, {"draw_style": "by_plate_id"}]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"application": "middle-earth", "version": "0.9.0",
			"features": {"type": "Group", "is_group": true, "title": "Planet", "children": []},
			"view": view}))
		file.close()
		var document := Document.new()
		assert_eq(document.load_from_file(path), "", "a 0.9.0 file opens")
		assert_eq(document.root.style.mode, Styling.BY_FEATURE, "on own colours from %s" % [view])
	DirAccess.remove_absolute(path)


# 0.9.0 already has the five types, so the step before is not run on it again:
# mapped twice, every type would be lost.
func test_a_0_9_0_file_keeps_its_types() -> void:
	var migrated := Document.migrate({"version": "0.9.0", "features": {
		"type": "Group", "title": "Planet", "children": [
			{"type": "Feature", "title": "Ring", "feature_type": "circle", "rings": []}]}})
	assert_eq(migrated["features"]["children"][0]["feature_type"], "circle", "the circle stays one")
	assert_eq(migrated["version"], "0.11.0", "at the current version")


### 0.10.0 to 0.11.0: the age ramp joins the group style


# A 0.10.0 style has no ramp and reads with the default one, without a step.
func test_a_0_10_0_style_reads_with_the_default_ramp() -> void:
	var style := {"mode": "age", "color": [0.9, 0.9, 0.9, 1.0], "opacity": 0.5, "palette": "steps"}
	var migrated := Document.migrate({"version": "0.10.0",
		"features": {"type": "Group", "is_group": true, "title": "Planet", "style": style.duplicate(),
			"children": []}})
	assert_eq(migrated["features"]["style"], style, "the style is left as it was")
	assert_eq(migrated["version"], "0.11.0", "at the current version")
	var root := Feature.from_json(migrated["features"])
	assert_eq(root.style.palette, "steps", "the palette it named")
	assert_eq(root.style.ramp_from, GroupStyle.DEFAULT_RAMP_FROM, "and the default ramp")
	assert_eq(root.style.ramp_to, GroupStyle.DEFAULT_RAMP_TO, "to its default end")
	assert_eq(root.style.ramp_span, GroupStyle.DEFAULT_RAMP_SPAN, "over its default span")


func test_version_ordering() -> void:
	assert_true(Document._is_older_than("0.9.0", "0.10.0"), "the minor number is a number")
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
