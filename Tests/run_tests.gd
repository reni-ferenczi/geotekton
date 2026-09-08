extends SceneTree

# Test runner, usually started through Tests/run.py.
#   headless: Godot ... -s res://Tests/run_tests.gd -- [--filter=SUBSTRING]
#   rendered: Godot ... -s res://Tests/run_tests.gd -- --rendered [--filter=SUBSTRING]
#   --dir=res://... discovers somewhere other than Unit or Rendered.
#   --scene=res://... hosts a scene other than the application, for the self-check.

const UNIT_DIR := "res://Tests/Unit"
const RENDERED_DIR := "res://Tests/Rendered"
const APPLICATION_SCENE := "res://Scenes/Application/application.tscn"
const WINDOW_SIZE := Vector2i(1800, 900)


# A runtime error does not raise: the engine prints it, abandons the method and
# returns, leaving the failure list empty. A test that hits one would be counted
# as passed, so the runner listens for the errors as the engine prints them and
# turns whatever arrives during a test into a failure of that test.
#
# Only script and shader errors count. An engine level error is not always a
# defect and not always the run's doing: DisplayServer.clipboard_get() reports
# one whenever another process holds the clipboard, which would fail a rendered
# test for something happening outside the machine's test run.
class ErrorWatcher extends Logger:
	var messages: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, editor_notify: bool, error_type: int,
			script_backtraces: Array) -> void:
		if error_type != ERROR_TYPE_SCRIPT and error_type != ERROR_TYPE_SHADER:
			return
		var text: String = code if rationale.is_empty() else rationale
		messages.append("%s (%s at %s:%d)" % [text, function, file, line])

	# The messages seen since the last call, and start counting again.
	func take() -> Array[String]:
		var taken := messages.duplicate()
		messages.clear()
		return taken


var rendered: bool = false
var filter: String = ""
var directory: String = ""
var scene_path: String = APPLICATION_SCENE
var passed: int = 0
var failed: int = 0
var watcher := ErrorWatcher.new()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--rendered":
			rendered = true
		elif arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
		elif arg.begins_with("--dir="):
			directory = arg.trim_prefix("--dir=")
		elif arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
		else:
			print("Unknown argument: %s" % arg)
	OS.add_logger(watcher)
	_run()


func _run() -> void:
	# The tree only exists once the main loop is iterating.
	await process_frame

	var application: Node = null
	var ready := true
	if rendered:
		application = await _setup_rendered()
		ready = application != null

	# Taken here rather than at the end, because the first test to run takes
	# what the watcher holds before it starts. A script the application scene
	# depends on failing to compile arrives this way: the engine hands back
	# what it did compile, the window comes up and the tests used to run
	# against it and pass. See GP-0029.
	if not _report_errors(watcher.take(), "setup"):
		ready = false

	if ready:
		for path in _discover(_folder()):
			await _run_file(path, application)

	# Errors from the discovery, or from work a test left running after it
	# returned, belong to no single test but still count.
	_report_errors(watcher.take(), "run")

	print("%d passed, %d failed" % [passed, failed])
	OS.remove_logger(watcher)
	quit(1 if failed > 0 else 0)


func _folder() -> String:
	if not directory.is_empty():
		return directory
	return RENDERED_DIR if rendered else UNIT_DIR


# Show the application window and check that screen coordinates equal window pixels.
func _setup_rendered() -> Node:
	var scene: PackedScene = load(scene_path)
	if scene == null:
		_fail_line("setup", "cannot load %s" % scene_path)
		return null

	var application := scene.instantiate()
	root.add_child(application)
	root.mode = Window.MODE_WINDOWED
	root.size = WINDOW_SIZE
	await process_frame
	await process_frame

	var transform := root.get_final_transform()
	if not transform.is_equal_approx(Transform2D.IDENTITY):
		_fail_line("setup", ("window transform is %s, expected the identity; " +
			"screen coordinates must equal window pixels") % transform)
		return null

	return application


func _discover(folder: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		_fail_line("discovery", "cannot open %s" % folder)
		return paths
	for file_name in dir.get_files():
		if not file_name.begins_with("test_") or not file_name.ends_with(".gd"):
			continue
		if not filter.is_empty() and not filter in file_name:
			continue
		paths.append("%s/%s" % [folder, file_name])
	paths.sort()
	return paths


func _run_file(path: String, application: Node) -> void:
	var label := path.trim_prefix("res://")
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		_fail_line(label, "cannot load the test script, see the parse errors above")
		return

	var method_names: Array[String] = []
	for method in script.new().get_method_list():
		if method["name"].begins_with("test_"):
			method_names.append(method["name"])
	method_names.sort()

	for method_name in method_names:
		var instance = script.new()
		instance.tree = self
		instance.app = application
		watcher.take()
		await instance.call(method_name)
		var errors := watcher.take()
		var name := "%s::%s" % [label, method_name]
		if instance.failures.is_empty() and errors.is_empty():
			passed += 1
			print("PASS %s" % name)
		else:
			for message in instance.failures:
				failed += 1
				print("FAIL %s: %s" % [name, message])
			for message in errors:
				failed += 1
				print("FAIL %s: runtime error: %s" % [name, message])


# Report the errors that belong to no test against name, and say whether the
# list was empty.
func _report_errors(messages: Array[String], name: String) -> bool:
	for message in messages:
		_fail_line(name, "script error: %s" % message)
	return messages.is_empty()


func _fail_line(name: String, message: String) -> void:
	failed += 1
	print("FAIL %s: %s" % [name, message])
