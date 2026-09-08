extends TestCase

# Rules the rendered tests have to keep, checked from the headless suite so that
# breaking one fails at the next run rather than somewhere it cannot be traced.

const RENDERED_DIR := "res://Tests/Rendered"


# GP-0025: a script level static variable in a rendered test makes the engine
# segfault during shutdown, after every test has passed and the summary has been
# printed, so the run fails with nothing to point at. It takes two such scripts
# to show, and the file passes when it is the only one being run, which is why
# this is worth catching here instead of waiting for someone to hit it.
#
# The headless tests are unaffected: Tests/Unit/test_hit_test.gd has declared one
# since Phase 2. A const array of Vector2, turned into a PackedVector2Array
# where it is used, does the same job in a rendered test.
func test_no_rendered_test_declares_a_static_var() -> void:
	var pattern := RegEx.create_from_string("(?m)^static\\s+var\\s+(\\w+)")
	var checked := 0
	for path in _rendered_scripts():
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			fail("cannot read %s" % path)
			continue
		checked += 1
		for found in pattern.search_all(file.get_as_text()):
			fail(("%s declares the static variable %s. A rendered test cannot: " +
				"see GP-0025 and Docs/Testing.md.") % [path, found.get_string(1)])
	assert_true(checked > 0, "there are rendered tests to check, found %d" % checked)


func _rendered_scripts() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(RENDERED_DIR)
	if dir == null:
		fail("cannot open %s" % RENDERED_DIR)
		return paths
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			paths.append("%s/%s" % [RENDERED_DIR, file_name])
	paths.sort()
	return paths
