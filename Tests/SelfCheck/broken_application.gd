extends VBoxContainer

# Fixture for Tests/self_check.py, hosted by broken_application.tscn and
# reached with the runner's --scene switch. It stands in for the application
# scene: sound in itself, but depending on a script that does not compile.
#
# The content scale is what Application sets, so that the window the runner
# builds passes its own check and the run gets as far as the tests, which is
# where GP-0029 lost the parse errors.

const DEPENDENCY := preload("res://Tests/SelfCheck/broken_dependency.gd")


func _ready() -> void:
	get_tree().root.content_scale_factor = 1.0
