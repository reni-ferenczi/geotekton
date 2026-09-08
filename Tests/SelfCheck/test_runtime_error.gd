extends TestCase

# Fixture for Tests/self_check.py, deliberately broken. It lives outside
# Tests/Unit so the ordinary suites never discover it, and is reached with
# the runner's --dir switch.
#
# GP-0022: a method that hits a runtime error is abandoned by the engine and
# returns with an empty failure list. Before the fix the runner read that
# empty list and printed PASS.


func test_a_passing_method_still_passes() -> void:
	assert_eq(1 + 1, 2)


func test_reading_a_field_that_does_not_exist() -> void:
	var node := Node.new()
	assert_true(node.no_such_field == null, "never reached")
	fail("never reached either")
	node.free()
