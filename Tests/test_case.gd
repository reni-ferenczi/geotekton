class_name TestCase
extends RefCounted

# Base class for test cases. Assertions record failures instead of aborting,
# so a single test method reports every problem it finds.
# Never use GDScript's built-in assert() in tests: it aborts the run and is
# stripped from release builds.

# Messages of the failed assertions, empty when the test passed.
var failures: Array[String] = []

# The SceneTree running the tests, set by the runner.
var tree: SceneTree

# The Application node in rendered mode, null in headless mode. Set by the runner.
var app


func fail(msg: String) -> void:
	failures.append(msg)


func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		fail("expected true" if msg.is_empty() else msg)


func assert_eq(a, b, msg = "") -> void:
	if a != b:
		fail("%s != %s%s" % [a, b, "" if str(msg).is_empty() else " (%s)" % msg])


func assert_close(a, b, eps: float = 1e-4, msg = "") -> void:
	var diff := _max_difference(a, b)
	if diff < 0.0:
		fail("cannot compare %s with %s%s" % [a, b, "" if str(msg).is_empty() else " (%s)" % msg])
	elif diff > eps:
		fail("%s != %s within %s, difference is %s%s" % [
			a, b, eps, diff, "" if str(msg).is_empty() else " (%s)" % msg])


# Largest absolute component difference, or -1.0 if the values are not comparable.
func _max_difference(a, b) -> float:
	if a is float or a is int:
		if b is float or b is int:
			return absf(float(a) - float(b))
		return -1.0
	if a is Vector2 and b is Vector2:
		return maxf(absf(a.x - b.x), absf(a.y - b.y))
	if a is Vector3 and b is Vector3:
		return maxf(absf(a.x - b.x), maxf(absf(a.y - b.y), absf(a.z - b.z)))
	if a is Color and b is Color:
		return maxf(
			maxf(absf(a.r - b.r), absf(a.g - b.g)),
			maxf(absf(a.b - b.b), absf(a.a - b.a)))
	return -1.0
