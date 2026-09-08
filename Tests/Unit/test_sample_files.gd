extends TestCase

# The sample files in Tests/Data are the fixtures for the rendered tests.
# Loading them here proves that both file formats are readable and that every
# feature is drawn where the shader's tests find it at the documented probe
# point. Keep this table and Tests/Data/README.md in sync.

const DATA_DIR := "res://Tests/Data"

# file name -> { version: the format the file is written in,
#                titles: every title in the tree, in depth-first order,
#                hits: probe point (latitude, longitude) -> expected feature title or "" }
const EXPECTED := {
	"triangle.middle-earth": {
		"version": "0.1.0",
		"titles": ["Planet", "Cratons", "Red Triangle"],
		"hits": [
			[Vector2(-3, 0), "Red Triangle"],
			[Vector2(5, 40), ""],
		],
	},
	"two_cratons.middle-earth": {
		"version": "0.1.0",
		"titles": ["Planet", "Cratons", "Red Triangle", "Blue Quad", "Green Moved"],
		"hits": [
			[Vector2(-3, 0), "Red Triangle"],
			[Vector2(30, 45), "Blue Quad"],
			[Vector2(-3, -60), "Green Moved"],
			[Vector2(5, 40), ""],
		],
	},
	"empty.middle-earth": {
		"version": "0.1.0",
		"titles": ["Planet"],
		"hits": [
			[Vector2(-3, 0), ""],
			[Vector2(5, 40), ""],
		],
	},
	"craton.middle-earth": {
		"version": "0.4.0",
		"titles": ["Planet", "Cratons", "Old Shield"],
		"hits": [
			[Vector2(-10, -8), "Old Shield"],
			[Vector2(19, 4), "Old Shield"],
			[Vector2(13, 6), "Old Shield"],
			[Vector2(2, 19), ""],
			[Vector2(-3, -37), ""],
		],
	},
	"mixed_geometry.middle-earth": {
		"version": "0.2.0",
		"titles": ["Planet", "Shapes", "Red Triangle", "Blue Ridge", "Green Stations"],
		"hits": [
			[Vector2(-3, 0), "Red Triangle"],
			[Vector2(0, 40), "Blue Ridge"],
			[Vector2(-30, -30), "Green Stations"],
			[Vector2(30, -30), "Green Stations"],
			[Vector2(5, 17), ""],
		],
	},
}


func test_every_sample_file_is_covered() -> void:
	var dir := DirAccess.open(DATA_DIR)
	assert_true(dir != null, "cannot open %s" % DATA_DIR)
	if dir == null:
		return
	var found: Array[String] = []
	for file_name in dir.get_files():
		if file_name.ends_with(".middle-earth"):
			found.append(file_name)
	found.sort()
	var expected: Array[String] = []
	for key in EXPECTED:
		expected.append(key)
	expected.sort()
	assert_eq(", ".join(found), ", ".join(expected), "every sample file needs an entry in EXPECTED")


func test_sample_files_load_and_hit_test() -> void:
	for file_name in EXPECTED:
		var root := _load("%s/%s" % [DATA_DIR, file_name])
		if root == null:
			continue

		var titles: Array[String] = []
		_collect_titles(root, titles)
		assert_eq(", ".join(titles), ", ".join(EXPECTED[file_name]["titles"]),
			"titles of %s" % file_name)

		var geometry := Planet.collect_geometry(root)
		for probe in EXPECTED[file_name]["hits"]:
			var point: Vector2 = probe[0]
			var hit := Planet.hit_test(point.x, point.y, geometry)
			var title: String = "" if hit == null else hit.title
			assert_eq(title, probe[1], "probe %s in %s" % [point, file_name])


# Every sample predates the type field, so all of them are fixtures for the one
# thing 0.3.0 asks of an older file: that it arrives whole and unclassified.
# A file older than 0.3.0 carries no type at all, so everything in it has to
# arrive unclassified; one written since carries the type it names. Which is
# which comes from the version in EXPECTED, so adding a sample cannot quietly
# skip the check.
func test_a_sample_carries_the_type_its_format_allows() -> void:
	for file_name in EXPECTED:
		var root := _load("%s/%s" % [DATA_DIR, file_name])
		if root == null:
			continue
		var carries_types := not Document._is_older_than(
			str(EXPECTED[file_name]["version"]), "0.3.0")
		var stack: Array[Feature] = [root]
		while not stack.is_empty():
			var node: Feature = stack.pop_back()
			stack.append_array(node.children)
			if node.is_group:
				continue
			if carries_types:
				assert_true(FeatureType.CATALOG.has(node.feature_type),
					"%s in %s names a type in the catalog: %s" % [
						node.title, file_name, node.feature_type])
			else:
				assert_eq(node.feature_type, FeatureType.UNCLASSIFIED,
					"%s in %s carries no type, so it is unclassified" % [node.title, file_name])
			assert_true(FeatureType.allows(node.feature_type, node.kind_name()),
				"and its type allows the kind it holds")


func test_the_craton_sample_keeps_the_type_and_colour_it_names() -> void:
	var root := _load("%s/craton.middle-earth" % DATA_DIR)
	if root == null:
		return
	var shield := _find(root, "Old Shield")
	assert_true(shield != null, "the sample holds Old Shield")
	if shield == null:
		return
	assert_eq(shield.feature_type, "craton", "it is a craton")
	assert_eq(shield.color, Color(0, 0, 1, 1),
		"and keeps the colour the file picked, not the one the type would give")
	assert_true(shield.color != FeatureType.color("craton"),
		"which are different, so the check means something")


func _find(root: Feature, title: String) -> Feature:
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if node.title == title:
			return node
		stack.append_array(node.children)
	return null


func test_the_moved_craton_sits_where_the_rotation_puts_it() -> void:
	# The README documents the green probe point; it is the red one rotated by 60 degrees.
	var root := _load("%s/two_cratons.middle-earth" % DATA_DIR)
	if root == null:
		return
	var green: Feature = null
	for node in root.children[0].children:
		if node.title == "Green Moved":
			green = node
	assert_true(green != null, "the sample must contain the Green Moved feature")
	if green == null:
		return
	assert_eq(green.keyframes.size(), 1, "the one rotation the file holds is one keyframe")
	assert_close(green.keyframes[0].time, 0.0, 1e-9, "wrapped as the keyframe at time zero")
	assert_close(green.rotation_at(0.0), Vector3(60, 0, 0), 1e-6)
	var moved := Feature.apply_rotation(
		PackedVector2Array([Vector2(-3, 0)]), green.rotation_at(0.0))[0]
	assert_close(moved, Vector2(-3, -60), 1e-4, "the documented green probe point")


func test_every_triangle_derived_from_a_sample_faces_outwards() -> void:
	# The rule from Feature.faces_outwards, which both Planet.hit_test and
	# the shader rely on. It held for the triangles the 0.1.0 files listed, and
	# it has to hold for the ones the recovered rings are cut into.
	for file_name in EXPECTED:
		var root := _load("%s/%s" % [DATA_DIR, file_name])
		if root == null:
			continue
		for feature in _leaves(root):
			var triangles := feature.triangles
			if feature.geometry_kind == Feature.GeometryKind.POLYGON:
				assert_eq(triangles.size(), (feature.vertex_count() - 2 * feature.rings.size()) * 3,
					"%s in %s covers two triangles fewer than it has vertices" % [feature.title, file_name])
			for i in range(0, triangles.size() - 2, 3):
				var a := Feature._latlon_to_xyz_s(triangles[i])
				var b := Feature._latlon_to_xyz_s(triangles[i + 1])
				var c := Feature._latlon_to_xyz_s(triangles[i + 2])
				assert_true((b - a).cross(c - a).dot((a + b + c) / 3.0) >= 0.0,
					"triangle %d of %s in %s faces inwards" % [i / 3, feature.title, file_name])


func test_the_kinds_the_samples_hold() -> void:
	var root := _load("%s/mixed_geometry.middle-earth" % DATA_DIR)
	if root == null:
		return
	var kinds: Array[String] = []
	for node in root.children[0].children:
		kinds.append(str(Feature.KIND_NAMES[node.geometry_kind]))
	assert_eq(", ".join(kinds), "polygon, polyline, multipoint",
		"mixed_geometry.middle-earth covers all three kinds")


# Mirrors the checks in Document.load_from_file, migration included.
func _load(path: String) -> Feature:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail("cannot open %s" % path)
		return null

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		fail("%s is not valid JSON: %s" % [path, json.get_error_message()])
		return null

	var data: Variant = json.data
	if data is not Dictionary:
		fail("%s does not hold a dictionary" % path)
		return null
	if data.get("application", "") != "middle-earth":
		fail("%s is not marked as a Middle-Earth file" % path)
		return null
	assert_eq(data.get("version", ""), EXPECTED[path.get_file()]["version"],
		"file format version of %s" % path)

	var root := Feature.from_json(Document.migrate(data)["features"])
	root.is_root = true
	assert_eq(root.title, "Planet", "root group title of %s" % path)
	assert_true(root.is_group, "the root of %s must be a group" % path)
	return root


func _leaves(node: Feature) -> Array[Feature]:
	var found: Array[Feature] = []
	if not node.is_group:
		found.append(node)
	for child in node.children:
		found.append_array(_leaves(child))
	return found


func _collect_titles(node: Feature, titles: Array[String]) -> void:
	titles.append(node.title)
	for child in node.children:
		_collect_titles(child, titles)
