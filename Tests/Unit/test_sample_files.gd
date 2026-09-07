extends TestCase

# The sample files in Tests/Data are the fixtures for the rendered tests.
# Loading them here proves that the format is readable and that every craton is
# wound so the shader's half-plane test finds it at the documented probe point.
# Keep this table and Tests/Data/README.md in sync.

const DATA_DIR := "res://Tests/Data"

# file name -> { titles: every title in the tree, in depth-first order,
#                hits: probe point (latitude, longitude) -> expected feature title or "" }
const EXPECTED := {
	"triangle.middle-earth": {
		"titles": ["Planet", "Cratons", "Red Triangle"],
		"hits": [
			[Vector2(-3, 0), "Red Triangle"],
			[Vector2(5, 40), ""],
		],
	},
	"two_cratons.middle-earth": {
		"titles": ["Planet", "Cratons", "Red Triangle", "Blue Quad", "Green Moved"],
		"hits": [
			[Vector2(-3, 0), "Red Triangle"],
			[Vector2(30, 45), "Blue Quad"],
			[Vector2(-3, -60), "Green Moved"],
			[Vector2(5, 40), ""],
		],
	},
	"empty.middle-earth": {
		"titles": ["Planet"],
		"hits": [
			[Vector2(-3, 0), ""],
			[Vector2(5, 40), ""],
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

		var triangles := Planet.collect_triangles(root)
		for probe in EXPECTED[file_name]["hits"]:
			var point: Vector2 = probe[0]
			var hit := Planet.hit_test_craton(point.x, point.y, triangles)
			var title: String = "" if hit == null else hit.title
			assert_eq(title, probe[1], "probe %s in %s" % [point, file_name])


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
	assert_close(green.rotation_angles, Vector3(60, 0, 0), 1e-6)
	var moved := Feature.apply_rotation([Vector2(-3, 0)] as Array[Vector2], green.rotation_angles)[0]
	assert_close(moved, Vector2(-3, -60), 1e-4, "the documented green probe point")


# Mirrors the checks in Features._load_from_file.
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
	assert_eq(data.get("version", ""), "0.1.0", "file format version of %s" % path)

	var root := Feature.from_json(data["features"])
	root.is_root = true
	assert_eq(root.title, "Planet", "root group title of %s" % path)
	assert_true(root.is_group, "the root of %s must be a group" % path)
	return root


func _collect_titles(node: Feature, titles: Array[String]) -> void:
	titles.append(node.title)
	for child in node.children:
		_collect_titles(child, titles)
