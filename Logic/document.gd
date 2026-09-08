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

# The oldest age anything in the application names, in millions of years before
# present. Older than the Earth, so nothing anyone models runs into it.
const MAX_TIME := 10000.0

# The feature tree was replaced: rebuild the UI from root. True while it is the
# same document, which is what stepping through the undo stack does; false when
# another document has taken its place, as File > New and File > Open do.
signal root_replaced(same_document: bool)

# The path, the dirty flag or the undo depth changed: refresh title and buttons.
signal state_changed()

# The current time moved: redraw at the new time and follow it on the timeline.
signal time_changed()

var root: Feature
var path: String = ""

# How the scene around the features is drawn. Saved with the file, but not on
# the undo stack: it says how the document is looked at rather than what it
# holds. It still dirties the document, which _view_changed tracks, since the
# file is what carries it.
var view := ViewSettings.new()
var _view_changed: bool = false

# When everything is drawn, an age in millions of years before present, so a
# larger number is older and 0 is now. Not part of the document's content: it is
# where the document is being looked at, so moving it dirties nothing and a file
# always opens at the present.
var current_time: float = 0.0

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
func reset(settings: ViewSettings = null) -> void:
	root = Feature.create_group("Planet")
	root.is_root = true
	view = settings.clone() if settings != null else ViewSettings.new()
	_view_changed = false
	versions.clear()
	applied = 0
	record()
	_saved = applied
	path = ""
	set_time(0.0)
	root_replaced.emit(false)
	state_changed.emit()


func is_dirty() -> bool:
	return applied != _saved or _view_changed


# Say that a view setting was edited, so the document is offered for saving. The
# caller has already changed `view`; this is what makes the change count.
func view_edited() -> void:
	_view_changed = true
	state_changed.emit()


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
	root_replaced.emit(true)
	state_changed.emit()


### Editing

# Every change the Properties panel makes goes through one of these: they
# validate the change, apply it and record one undo version. The ones that can
# refuse return a message saying why and leave the tree untouched; the rest
# return nothing because there is nothing they can refuse.


func rename(node: Feature, title: String) -> void:
	node.title = Feature.clamp_title(title)
	record()


func set_enabled(node: Feature, enabled: bool) -> void:
	node.enabled = enabled
	if node.is_group and not enabled:
		node.collapsed = true
	record()


func set_color(feature: Feature, color: Color) -> void:
	feature.color = color
	record()


# Give the feature another type. Refused when the feature already holds geometry
# of a kind that type does not allow, since the alternative is a feature its own
# type says cannot exist. The colour follows the type as long as it is still the
# one the old type gave it, so a colour someone picked is never overwritten.
func set_feature_type(feature: Feature, type_id: String) -> String:
	if not FeatureType.CATALOG.has(type_id):
		return "There is no feature type called %s." % type_id
	if feature.has_geometry() and not FeatureType.allows(type_id, feature.kind_name()):
		return "A %s cannot be a %s, which is %s." % [
			feature.kind_name(), FeatureType.label(type_id),
			" or ".join(FeatureType.kinds(type_id))]
	if feature.color == FeatureType.color(feature.feature_type):
		feature.color = FeatureType.color(type_id)
	feature.feature_type = type_id
	record()
	return ""


func set_time_range(feature: Feature, time_range: Vector2i) -> String:
	if time_range.y < time_range.x:
		return "The time range ends at %d, before it starts at %d." % [time_range.y, time_range.x]
	feature.time_range = time_range
	record()
	return ""


# Move one vertex of one part of the geometry, in the frame of the feature.
func set_vertex(feature: Feature, part: int, index: int, vertex: Vector2) -> String:
	var error := _check_vertex(feature, part, index, vertex)
	if not error.is_empty():
		return error
	feature.rings[part][index] = vertex
	feature.rebuild_triangles()
	record()
	return ""


# Add a vertex to a part, before the vertex currently at index. An index of the
# part's size appends, which is what the panel does with nothing selected.
func insert_vertex(feature: Feature, part: int, index: int, vertex: Vector2) -> String:
	var error := _check_vertex(feature, part, index, vertex, true)
	if not error.is_empty():
		return error
	feature.rings[part].insert(index, vertex)
	feature.rebuild_triangles()
	record()
	return ""


# Take a vertex out. A part left with too few vertices to be a shape goes with
# it, so removing vertices one by one ends with the part gone rather than with
# geometry nothing can draw.
func remove_vertex(feature: Feature, part: int, index: int) -> String:
	var error := _check_index(feature, part, index)
	if not error.is_empty():
		return error
	feature.rings[part].remove_at(index)
	if feature.rings[part].size() < feature.minimum_vertices():
		feature.rings.remove_at(part)
	feature.rebuild_triangles()
	record()
	return ""


# Cut one part of a feature in two, leaving two features side by side in the
# tree. A polyline is cut at one vertex and a polygon between two, and both
# halves keep the vertex or vertices the cut runs through.
#
# Both halves carry the type, the colour, the time range and the keyframes of
# the feature they came from, so the two go on moving together and go on
# existing over the same span. The original keeps its title and every other part
# it had; the second half is a new feature holding that half alone.
func split_feature(feature: Feature, part: int, first: int, second: int = -1) -> String:
	if feature == null or feature.is_group:
		return "Only a feature with geometry can be split."
	if feature.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return "A topology borrows its vertices, so there is nothing of its own to split."
	if part < 0 or part >= feature.rings.size():
		return "The feature has no part %d." % part

	var ring: PackedVector2Array = feature.rings[part]
	var problem := ""
	var halves: Array[PackedVector2Array] = []
	match feature.geometry_kind:
		Feature.GeometryKind.POLYLINE:
			problem = GeometryEdit.polyline_split_problem(ring, first)
			if problem.is_empty():
				halves = GeometryEdit.split_polyline(ring, first)
		Feature.GeometryKind.POLYGON:
			problem = GeometryEdit.polygon_split_problem(ring, first, second)
			if problem.is_empty():
				halves = GeometryEdit.split_polygon(ring, first, second)
		_:
			problem = "A multipoint is separate markers, so there is no path to split."
	if not problem.is_empty():
		return problem

	var parent := root.find_parent(feature)
	if parent == null:
		return "%s is not in the tree." % feature.title

	var other := feature.duplicate()
	other.title = Feature.clamp_title("%s 2" % feature.title)
	var only: Array[PackedVector2Array] = [halves[1]]
	other.rings = only
	other.rebuild_triangles()

	feature.rings[part] = halves[0]
	feature.rebuild_triangles()
	parent.children.insert(parent.find_child(feature) + 1, other)
	record()
	return ""


### Line topologies

# A topology's geometry is the list of sections it names; the vertices it draws
# are resolved from them whenever the tree or the current time moves. These four
# are the only things that change the list, and each records one undo version
# like every other edit. See Logic/topology.gd.


# Add a section running along the whole of one part of another feature. The
# feature becomes a topology when it holds nothing yet; one that already holds
# vertices of its own is refused, because the two cannot both be its geometry.
func add_section(feature: Feature, target: Feature, part: int) -> String:
	if feature == null or feature.is_group:
		return "Only a feature can be a topology."
	if feature.has_geometry() and feature.geometry_kind != Feature.GeometryKind.TOPOLOGY:
		return "%s already holds a %s." % [feature.title, feature.kind_name()]
	if not FeatureType.allows(feature.feature_type, "topology"):
		return "A %s cannot be a topology." % FeatureType.label(feature.feature_type)
	var problem := Topology.section_problem(feature, target)
	if not problem.is_empty():
		return problem
	if part < 0 or part >= target.rings.size():
		return "%s has no part %d." % [target.title, part + 1]

	feature.geometry_kind = Feature.GeometryKind.TOPOLOGY
	feature.sections.append(TopologySection.whole_part(target, part))
	record()
	return ""


func remove_section(feature: Feature, index: int) -> String:
	var error := _check_section(feature, index)
	if not error.is_empty():
		return error
	feature.sections.remove_at(index)
	record()
	return ""


# Walk a section the other way round. A boundary is built by clicking one
# feature after another and the vertices of the next one often run back towards
# the last, which is what this is for.
func reverse_section(feature: Feature, index: int) -> String:
	var error := _check_section(feature, index)
	if not error.is_empty():
		return error
	feature.sections[index].reversed = not feature.sections[index].reversed
	record()
	return ""


# Which vertices of the section's feature the section runs between, counting
# from zero. A range beyond the part is not refused here: the feature it names
# can grow or shrink under it, so Topology.resolve() brings the range back into
# whatever the part holds at the time it is drawn.
func set_section_range(feature: Feature, index: int, from_index: int, to_index: int) -> String:
	var error := _check_section(feature, index)
	if not error.is_empty():
		return error
	if from_index < 0 or to_index < 0:
		return "Vertices are numbered from 1."
	feature.sections[index].from_index = from_index
	feature.sections[index].to_index = to_index
	record()
	return ""


func _check_section(feature: Feature, index: int) -> String:
	if feature == null or feature.geometry_kind != Feature.GeometryKind.TOPOLOGY:
		return "The selected feature is not a topology."
	if index < 0 or index >= feature.sections.size():
		return "%s has no section %d." % [feature.title, index + 1]
	return ""


### Time and motion

# The current time is view state and records no undo version. The keyframes are
# content and each change to them records one, like every other edit.


# Look at the document at another time. Ages run from now to MAX_TIME, so a
# time outside that is brought back to the nearer end rather than refused.
func set_time(time: float) -> void:
	var wanted := clampf(time, 0.0, MAX_TIME)
	if is_equal_approx(wanted, current_time):
		return
	current_time = wanted
	time_changed.emit()


# Give the node the rotation it has at that time, replacing the keyframe already
# there or adding one. This is what the Move tool commits.
func set_keyframe(node: Feature, time: float, rotation: Vector3) -> void:
	Keyframe.upsert(node.keyframes, time, rotation)
	record()


func remove_keyframe(node: Feature, index: int) -> String:
	var error := _check_keyframe(node, index)
	if not error.is_empty():
		return error
	node.keyframes.remove_at(index)
	record()
	return ""


# Move a keyframe to another time. Refused when another keyframe is already
# there, since the two would have to become one and the caller would not know
# which rotation survived.
func set_keyframe_time(node: Feature, index: int, time: float) -> String:
	var error := _check_keyframe(node, index)
	if not error.is_empty():
		return error
	if time < 0.0 or time > MAX_TIME:
		return "The time %s is outside 0 to %d." % [time, MAX_TIME]
	var existing := Keyframe.index_at(node.keyframes, time)
	if existing >= 0 and existing != index:
		return "There is already a keyframe at %s." % time
	var rotation: Vector3 = node.keyframes[index].rotation
	node.keyframes.remove_at(index)
	Keyframe.upsert(node.keyframes, time, rotation)
	record()
	return ""


func set_keyframe_rotation(node: Feature, index: int, rotation: Vector3) -> String:
	var error := _check_keyframe(node, index)
	if not error.is_empty():
		return error
	node.keyframes[index].rotation = rotation
	record()
	return ""


func _check_keyframe(node: Feature, index: int) -> String:
	if node == null:
		return "Nothing is selected."
	if index < 0 or index >= node.keyframes.size():
		return "%s has no keyframe %d." % [node.title, index]
	return ""


func _check_index(feature: Feature, part: int, index: int, past_the_end: bool = false) -> String:
	if part < 0 or part >= feature.rings.size():
		return "The feature has no part %d." % part
	var limit := feature.rings[part].size() + (1 if past_the_end else 0)
	if index < 0 or index >= limit:
		return "Part %d has no vertex %d." % [part, index]
	return ""


func _check_vertex(feature: Feature, part: int, index: int, vertex: Vector2,
		past_the_end: bool = false) -> String:
	var error := _check_index(feature, part, index, past_the_end)
	if not error.is_empty():
		return error
	return check_coordinates(vertex)


# Whether a latitude and longitude pair is on the planet at all. Separate from
# the vertex checks above because a script sends coordinates for a feature that
# does not exist yet, so there is no part or index to check them against.
static func check_coordinates(vertex: Vector2) -> String:
	if vertex.x < -90.0 or vertex.x > 90.0:
		return "Latitude %s is outside -90 to 90." % vertex.x
	if vertex.y < -180.0 or vertex.y > 180.0:
		return "Longitude %s is outside -180 to 180." % vertex.y
	return ""


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

	var migrated := migrate(data)
	var loaded := Feature.from_json(migrated["features"])
	loaded.is_root = true

	root = loaded
	view = ViewSettings.from_json(migrated.get("view"))
	_view_changed = false
	versions.clear()
	applied = 0
	record()
	_saved = applied
	path = file_path
	set_time(0.0)
	root_replaced.emit(false)
	state_changed.emit()
	return ""


# Read a document that was converted from something else. It is loaded like any
# other file and then cut loose from the one it was read out of: an import has
# no `.middle-earth` file of its own yet, so it opens Untitled and dirty and
# Save asks where to put it. See Docs/Import.md.
func load_imported(file_path: String) -> String:
	var error := load_from_file(file_path)
	if error.is_empty():
		path = ""
		# The version that was saved is not this document's, which is the same
		# state a document reaches when its saved version falls off the stack.
		_saved = -1
		state_changed.emit()
	return error


# The document as a file holds it: the feature tree, the view settings and the
# format version they are written at.
func to_json() -> Dictionary:
	return {
		"application": APPLICATION,
		"version": Application.VERSION,
		"features": root.to_json(),
		"view": view.to_json(),
	}


# Write the document to a file and mark it clean. Returns an empty string on
# success, otherwise a message describing why the file could not be written.
func save_to_file(file_path: String) -> String:
	# An image beside the file being written is stored relative to it, wherever
	# it was picked from and wherever the document was saved before, so a
	# project and its images can be moved together.
	view.backdrop_path = relative_backdrop(resolve_backdrop(), file_path)
	var data := to_json()
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return "Cannot write %s: %s" % [file_path, error_string(FileAccess.get_open_error())]
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	path = file_path
	_view_changed = false
	_saved = applied
	state_changed.emit()
	return ""


### The backdrop image
#
# The path is stored relative when the image sits in the project's own folder or
# under it, so a project and its images can be moved together, and absolute
# otherwise. A document with no path of its own has nothing to be relative to
# and stores what it was given.


# The path to write for an image the user picked, given where the file is going.
static func relative_backdrop(image_path: String, project_path: String) -> String:
	if image_path.is_empty() or project_path.is_empty() or image_path.is_relative_path():
		return image_path
	var folder := project_path.get_base_dir().replace("\\", "/").rstrip("/")
	var image := image_path.replace("\\", "/")
	if folder.is_empty() or not image.begins_with(folder + "/"):
		return image_path
	return image.substr(folder.length() + 1)


# Where the backdrop image actually is, resolved against the project file it was
# stored beside. Empty when the document names no image.
func resolve_backdrop() -> String:
	if view.backdrop_path.is_empty():
		return ""
	if view.backdrop_path.is_absolute_path():
		return view.backdrop_path
	if path.is_empty():
		return view.backdrop_path
	return path.get_base_dir().path_join(view.backdrop_path)


# Bring a parsed file up to the format this version writes, based on the
# version field it carries. See Docs/Persistence.md for the formats themselves.
static func migrate(data: Dictionary) -> Dictionary:
	var version := str(data.get("version", "0.1.0"))
	if not _is_older_than(version, "0.4.0"):
		return data
	data = data.duplicate(true)
	if _is_older_than(version, "0.2.0"):
		data["features"] = _to_0_2_0(data.get("features", {}))
	data["features"] = _to_0_4_0(data.get("features", {}))
	data["version"] = "0.4.0"
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


# Up to 0.3.0 a leaf carried one rotation and nothing moved in time. 0.4.0 keeps
# a list of keyframes instead, on groups as well as on leaves, and the one
# rotation becomes the keyframe at time zero: the present, which is where a file
# written before this was drawn. A group had no rotation to carry over and so
# arrives without keyframes, standing still until someone moves it.
static func _to_0_4_0(node: Variant) -> Variant:
	if node is not Dictionary:
		return node
	if node.get("is_group", node.get("type") == "Group"):
		var children: Array = []
		for child in node.get("children", []):
			children.append(_to_0_4_0(child))
		node["children"] = children
		return node

	var rotation: Array = node.get("rotation", [0, 0, 0])
	node.erase("rotation")
	node["keyframes"] = [{"time": 0.0, "rotation": rotation}]
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
