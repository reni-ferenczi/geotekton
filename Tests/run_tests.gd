extends SceneTree

# Test runner, usually started through Tests/run.py.
#   headless: Godot ... -s res://Tests/run_tests.gd -- [--filter=SUBSTRING]
#   rendered: Godot ... -s res://Tests/run_tests.gd -- --rendered [--filter=SUBSTRING]

const UNIT_DIR := "res://Tests/Unit"
const RENDERED_DIR := "res://Tests/Rendered"
const APPLICATION_SCENE := "res://Scenes/Application/application.tscn"
const WINDOW_SIZE := Vector2i(1800, 900)

var rendered: bool = false
var filter: String = ""
var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--rendered":
			rendered = true
		elif arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")
		else:
			print("Unknown argument: %s" % arg)
	_run()


func _run() -> void:
	# The tree only exists once the main loop is iterating.
	await process_frame

	var application: Node = null
	var ready := true
	if rendered:
		application = await _setup_rendered()
		ready = application != null

	if ready:
		for path in _discover(RENDERED_DIR if rendered else UNIT_DIR):
			await _run_file(path, application)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


# Show the application window and check that screen coordinates equal window pixels.
func _setup_rendered() -> Node:
	var scene: PackedScene = load(APPLICATION_SCENE)
	if scene == null:
		_fail_line("setup", "cannot load %s" % APPLICATION_SCENE)
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
		await instance.call(method_name)
		var name := "%s::%s" % [label, method_name]
		if instance.failures.is_empty():
			passed += 1
			print("PASS %s" % name)
		else:
			for message in instance.failures:
				failed += 1
				print("FAIL %s: %s" % [name, message])


func _fail_line(name: String, message: String) -> void:
	failed += 1
	print("FAIL %s: %s" % [name, message])
