extends TestCase

# Fixture for Tests/self_check.py, the sound half of the GP-0029 case. The
# runner is pointed at this file with a deliberately broken application scene,
# so that a run whose setup went wrong is seen to fail rather than to report
# this test as passed.


func test_a_method_that_passes_on_its_own() -> void:
	assert_eq(1 + 1, 2)
