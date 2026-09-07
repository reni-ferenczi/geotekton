class_name Document
extends RefCounted

# The open document: the feature tree, the file it came from and whether it
# differs from what is on disk.
#
# The undo stack is the only source of the dirty flag. Every edit records a
# version; the document is clean exactly while the stack sits on the version
# that was last written to or read from a file, so undoing back to that point
# makes it clean again.

const APPLICATION := "middle-earth"
const EXTENSION := ".middle-earth"
const UNTITLED := "Untitled"
const MAX_UNDO_STEPS := 100

# The feature tree was replaced: rebuild the UI from root.
signal root_replaced()

# The path, the dirty flag or the undo depth changed: refresh title and buttons.
signal state_changed()

var root: Feature
var path: String = ""

# Recorded versions of the tree, oldest first, and how many of them are applied.
# The current version is versions[applied - 1]; anything above applied is redo.
var versions: Array[Feature] = []
var applied: int = 0

# The value of applied that matches the file on disk, or -1 once that version
# has fallen out of the undo buffer and the document can no longer become clean.
var _saved: int = 0


func _init() -> void:
	reset()


### The document as a whole


# Start an empty document with a fresh undo stack, as after File > New.
func reset() -> void:
	root = Feature.create_group("Planet")
	root.is_root = true
	versions.clear()
	applied = 0
	record()
	_saved = applied
	path = ""
	root_replaced.emit()
	state_changed.emit()


func is_dirty() -> bool:
	return applied != _saved


# The file name for the window title, or "Untitled" before the first save.
func display_name() -> String:
	return UNTITLED if path.is_empty() else path.get_file()


### Undo stack


# Record the current tree as a new version, dropping any redo versions.
func record() -> void:
	while versions.size() > applied:
		versions.pop_back()
	versions.append(root.clone())
	applied += 1
	while applied > MAX_UNDO_STEPS:
		versions.pop_front()
		applied -= 1
		_saved -= 1
		if _saved < 1:
			# The saved version is gone, so the document stays dirty from here.
			_saved = -1
	state_changed.emit()


func can_undo() -> bool:
	return applied > 1


func can_redo() -> bool:
	return applied < versions.size()


func undo() -> void:
	if not can_undo():
		return
	applied -= 1
	_apply_current()


func redo() -> void:
	if not can_redo():
		return
	applied += 1
	_apply_current()


func _apply_current() -> void:
	root = versions[applied - 1].clone()
	root_replaced.emit()
	state_changed.emit()


### Files


# Read a document from a file. Returns an empty string on success, otherwise a
# message describing why the file could not be read.
func load_from_file(file_path: String) -> String:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return "Cannot read %s: %s" % [file_path, error_string(FileAccess.get_open_error())]

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return "%s is not valid JSON: %s" % [file_path, json.get_error_message()]

	var data: Variant = json.data
	if data is not Dictionary:
		return "%s is not a Middle Earth file: the root is not an object" % file_path
	if data.get("application", "") != APPLICATION:
		return "%s is not a Middle Earth file" % file_path

	var loaded := Feature.from_json(migrate(data)["features"])
	loaded.is_root = true

	root = loaded
	versions.clear()
	applied = 0
	record()
	_saved = applied
	path = file_path
	root_replaced.emit()
	state_changed.emit()
	return ""


# Write the document to a file and mark it clean. Returns an empty string on
# success, otherwise a message describing why the file could not be written.
func save_to_file(file_path: String) -> String:
	var data := {
		"application": APPLICATION,
		"version": Application.VERSION,
		"features": root.to_json(),
	}
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return "Cannot write %s: %s" % [file_path, error_string(FileAccess.get_open_error())]
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	path = file_path
	_saved = applied
	state_changed.emit()
	return ""


# Bring a parsed file up to the format this version writes, based on the
# version field it carries. See Docs/Persistence.md for the formats themselves.
static func migrate(data: Dictionary) -> Dictionary:
	if _is_older_than(str(data.get("version", "0.1.0")), "0.2.0"):
		data = data.duplicate(true)
		data["features"] = _to_0_2_0(data.get("features", {}))
		data["version"] = "0.2.0"
	return data


# True when version a was released before version b. Missing or unparsable
# parts count as 0, so "0.2" and "0.2.0" are the same version.
static func _is_older_than(a: String, b: String) -> bool:
	var left := a.split(".")
	var right := b.split(".")
	for i in range(3):
		var l := int(left[i]) if i < left.size() else 0
		var r := int(right[i]) if i < right.size() else 0
		if l != r:
			return l < r
	return false


# 0.1.0 stored a leaf as a flat triangle list and carried five switches left
# over from the rule editor this interface came from. 0.2.0 stores the outline
# the triangles cover and has dropped the switches.
static func _to_0_2_0(node: Variant) -> Variant:
	if node is not Dictionary:
		return node
	for key in ["repeat", "invert", "single", "wrap", "resize"]:
		node.erase(key)
	if node.get("is_group", node.get("type") == "Group"):
		var children: Array = []
		for child in node.get("children", []):
			children.append(_to_0_2_0(child))
		node["children"] = children
		return node

	# The oldest files called the rotation angles a position.
	if not node.has("rotation") and node.has("position"):
		node["rotation"] = node["position"]
	node.erase("position")

	var vertices: Array = node.get("vertices", [])
	node.erase("vertices")
	node["geometry_kind"] = "polygon"
	node["rings"] = rings_from_triangles(vertices)
	return node


# Recover the outlines a triangle soup covers: an edge shared by two triangles
# is inside the shape, one used by a single triangle is on its boundary, and
# the boundary edges chain up into one ring per polygon. Triangles that do not
# chain up, which a file written by hand can hold, are each kept as their own
# ring, so no vertex is ever lost.
static func rings_from_triangles(vertices: Array) -> Array:
	var points: Array[Vector2] = []
	var index_of := {}
	var indices := PackedInt32Array()
	for v in vertices:
		var point := Vector2(v[0], v[1])
		if not index_of.has(point):
			index_of[point] = points.size()
			points.append(point)
		indices.append(int(index_of[point]))

	var count := indices.size() / 3
	if count == 0:
		return []

	# How many triangles use each edge, without regard to its direction.
	var uses := {}
	for t in range(count):
		for e in range(3):
			var key := _edge_key(indices, t, e)
			uses[key] = int(uses.get(key, 0)) + 1

	# The boundary edges keep the direction the triangle gave them, so each one
	# says which vertex follows which around the outline.
	var follows := {}
	var starts: Array[int] = []
	for t in range(count):
		for e in range(3):
			if int(uses[_edge_key(indices, t, e)]) != 1:
				continue
			var from := indices[t * 3 + e]
			var to := indices[t * 3 + (e + 1) % 3]
			if follows.has(from):
				return _rings_per_triangle(points, indices, count)
			follows[from] = to
			starts.append(from)

	var rings: Array = []
	var visited := {}
	for start in starts:
		if visited.has(start):
			continue
		var ring: Array = []
		var current := start
		while not visited.has(current):
			visited[current] = true
			ring.append([points[current].x, points[current].y])
			if not follows.has(current):
				return _rings_per_triangle(points, indices, count)
			current = int(follows[current])
		if current != start or ring.size() < 3:
			return _rings_per_triangle(points, indices, count)
		rings.append(ring)
	return rings


static func _edge_key(indices: PackedInt32Array, triangle: int, edge: int) -> Vector2i:
	var a := indices[triangle * 3 + edge]
	var b := indices[triangle * 3 + (edge + 1) % 3]
	return Vector2i(mini(a, b), maxi(a, b))


static func _rings_per_triangle(points: Array[Vector2], indices: PackedInt32Array, count: int) -> Array:
	var rings: Array = []
	for t in range(count):
		var ring: Array = []
		for e in range(3):
			var point := points[indices[t * 3 + e]]
			ring.append([point.x, point.y])
		rings.append(ring)
	return rings
