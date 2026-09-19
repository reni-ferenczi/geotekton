extends TestCase

# A connection a scene file makes from a node it does not declare, one inside
# an instanced child scene, is kept by the text loader and dropped when the
# export converts the scene to binary. The feature toolbar was wired that way:
# every button worked from the editor and none of them did in a release build,
# and nothing had said a word. Such a connection belongs in the script, as
# Features._ready makes them now. See GP-0110.

const SCENES_DIR := "res://Scenes"


func test_no_scene_connects_a_signal_of_an_instanced_node() -> void:
	var node_pattern := RegEx.create_from_string(
		'(?m)^\\[node name="([^"]+)"(?: type="[^"]+")?(?: parent="([^"]+)")?')
	var connection_pattern := RegEx.create_from_string(
		'(?m)^\\[connection signal="([^"]+)" from="([^"]+)"')
	var checked := 0
	for path in _scene_files(SCENES_DIR):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			fail("cannot read %s" % path)
			continue
		checked += 1
		var text := file.get_as_text()
		var declared := {}
		for found in node_pattern.search_all(text):
			declared[_declared_path(found.get_string(1), found.get_string(2))] = true
		for found in connection_pattern.search_all(text):
			var from := found.get_string(2)
			if not declared.has(from):
				fail(("%s connects %s of %s, a node of an instanced scene. The export " +
					"drops that connection: make it from the script instead.")
					% [path, found.get_string(1), from])
	assert_true(checked > 0, "there are scenes to check, found %d" % checked)


# The path a [node] header declares, the way a [connection] names it: the
# root is ".", a child of the root its name, anything deeper parent/name.
func _declared_path(name: String, parent: String) -> String:
	if parent.is_empty():
		return "."
	if parent == ".":
		return name
	return "%s/%s" % [parent, name]


func _scene_files(folder: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		fail("cannot open %s" % folder)
		return paths
	for sub in dir.get_directories():
		paths.append_array(_scene_files("%s/%s" % [folder, sub]))
	for file_name in dir.get_files():
		if file_name.ends_with(".tscn"):
			paths.append("%s/%s" % [folder, file_name])
	paths.sort()
	return paths
