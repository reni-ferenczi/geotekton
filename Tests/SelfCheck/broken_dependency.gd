extends RefCounted

# Fixture for Tests/self_check.py, deliberately broken: this file does not
# compile. broken_application.gd depends on it, the way Application depends on
# AutomationPort, so setting the scene up prints a parse error.
#
# GP-0029: those errors were taken and thrown away by the first test that ran,
# and the run reported every test as passed.


func _deliberately_broken() -> void:
	var bad := some_undefined_thing_that_does_not_exist()
