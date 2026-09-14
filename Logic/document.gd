class_name Document
extends RefCounted

# The open document: the feature tree, the view settings, the file it came from
# and whether it differs from what is on disk.
#
# The undo stack is the only source of the dirty flag. Every edit records a
# version, of the tree and the view settings together; the document is clean
# exactly while the stack sits on the version that was last written to or read
# from a file, so undoing back to that point makes it clean again.

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

# How the scene around the features is drawn. Saved with the file and on the
# undo stack beside the tree, so a change of light or palette is undone the
# way a change of geometry is. Up to 0.7.0 it was left off the stack.
var view := ViewSettings.new()

# When everything is drawn, an age in millions of years before present, so a
# larger number is older and 0 is now. Not part of the document's content: it is
# where the document is being looked at, so moving it dirties nothing and a file
# always opens at the present.
var current_time: float = 0.0

# One recorded version: the tree and the view settings as they were.
class Version:
	var root: Feature
	var view: ViewSettings

	static func of(root_: Feature, view_: ViewSettings) -> Version:
		var version := Version.new()
		version.root = root_.clone()
		version.view = view_.clone()
		return version


# Recorded versions, oldest first, and how many of them are applied. The
# current version is versions[applied - 1]; anything above applied is redo.
var versions: Array[Version] = []
var applied: int = 0

# The value of applied that matches the file on disk, or -1 once that version
# has fallen out of the undo buffer and the document can no longer become clean.
var _saved: int = 0


func _init() -> void:
	reset()


### The document as a whole


# Start an empty document with a fresh undo stack, as after File > New. The
# style is the root group's, which is the document default for colors.
func reset(settings: ViewSettings = null, style: GroupStyle = null) -> void:
	root = Feature.create_group("Planet")
	root.is_root = true
	root.style = style.clone() if style != null else GroupStyle.for_root()
	view = settings.clone() if settings != null else ViewSettings.new()
	versions.clear()
	applied = 0
	record()
	_saved = applied
	path = ""
	set_time(0.0)
	root_replaced.emit(false)
	state_changed.emit()


func is_dirty() -> bool:
	return applied != _saved


# Say that a view setting was edited. The caller has already changed `view`;
# this records the version, which is what makes the change count and what
# lets it be undone. A block that still says what the last version says
# records nothing, so a picker opened and closed again is not an undo step.
# The View settings dialog edits the root group's style as well, so that counts
# as part of the block here.
func view_edited() -> void:
	if applied > 0 and versions[applied - 1].view.to_json() == view.to_json() \
			and versions[applied - 1].root.style.to_json() == root.style.to_json():
		return
	record()


# The file name for the window title, or "Untitled" before the first save.
func display_name() -> String:
	return UNTITLED if path.is_empty() else path.get_file()


### Undo stack


# Record the current tree and view settings as a new version, dropping any redo
# versions.
func record() -> void:
	while versions.size() > applied:
		versions.pop_back()
	versions.append(Version.of(root, view))
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
	var version := versions[applied - 1]
	root = version.root.clone()
	view = version.view.clone()
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


# Give a group another style: how the features under it are colored and how
# opaque they are. Refused on a leaf, which has no style.
func set_style(group: Feature, style: GroupStyle) -> String:
	if group == null or not group.is_group:
		return "Only a group has a style."
	group.style = style.clone()
	record()
	return ""


# Give the feature another type. On a feature holding nothing any type goes,
# since the type is what the tools then draw into it; once it holds a shape only
# a type that holds that kind, which comes down to making a polygon or a
# polyline a Circle or taking that back. The colour follows the type as long as
# it is still the one the old type gave it, so a colour someone picked is never
# overwritten.
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


# The vector is (younger, older), the order the file keeps. A range runs from
# its older end to its younger one, so the end may not be older than the start.
func set_time_range(feature: Feature, time_range: Vector2i) -> String:
	if time_range.y < time_range.x:
		return "The time range ends at %d, after it starts at %d." % [time_range.x, time_range.y]
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
	return _split_into(feature, part, halves)


# Cut a polygon in two along a path drawn across it, in the feature's own frame.
# The first and last points of the path go onto the ring and the points between
# them go to both halves; see GeometryEdit.split_along(). Otherwise the same as
# split_feature(): both halves carry what the feature was, and one version.
func split_feature_along(feature: Feature, part: int, path: PackedVector2Array) -> String:
	if feature == null or feature.is_group \
			or feature.geometry_kind != Feature.GeometryKind.POLYGON:
		return "Only a polygon is split along a cut."
	if part < 0 or part >= feature.rings.size():
		return "The feature has no part %d." % part
	var problem := GeometryEdit.split_along_problem(feature.rings[part], path)
	if not problem.is_empty():
		return problem
	return _split_into(feature, part, GeometryEdit.split_along(feature.rings[part], path))


# Put the first half in place of the part and the second in a new feature beside
# the original, named after it.
func _split_into(feature: Feature, part: int, halves: Array[PackedVector2Array]) -> String:
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
# A group carries no motion, so only a leaf takes a keyframe.
func set_keyframe(node: Feature, time: float, rotation: Vector3) -> String:
	if node == null:
		return "Nothing is selected."
	if node.is_group:
		return "%s is a group and does not move; keyframes belong to features." % node.title
	Keyframe.upsert(node.keyframes, time, rotation)
	record()
	return ""


func remove_keyframe(node: Feature, index: int) -> String:
	var error := _check_keyframe(node, index)
	if not error.is_empty():
		return error
	node.keyframes.remove_at(index)
	record()
	return ""


### Coupling

# A coupling is a span of the timeline over which a feature rides on another.
# Couple and Decouple are a cut in time: nothing older than the time they act at
# changes at all, and the keyframes the span covered younger than that time are
# dropped, so the feature is rigid from the cut until the user moves it again.
# Remove is the exception and converts pointwise. Each records one version.
# See Logic/coupling.gd and Docs/Time.md#a-coupling-edit-is-a-cut-in-time.


# Start a span at the time: the feature rides on the parent from then until the
# next span it already has towards the present, or the present itself. A
# keyframe at the time holds it where it stands, and the keyframes the span
# covers younger than the time are dropped.
func couple(child: Feature, parent: Feature, time: float) -> String:
	var problem := coupling_problem(child, parent, time)
	if not problem.is_empty():
		return problem
	var nodes := Coupling.index(root)
	var here := Coupling.world_basis(child, time, nodes)
	var span := Coupling.create(time, _span_end(child, time), parent.uuid)
	_drop_younger_keyframes(child, span, time)
	var worlds := _keyframe_worlds(child, nodes)
	child.couplings.append(span)
	Coupling.sort(child.couplings)
	_rebase(child, worlds, nodes)
	Keyframe.upsert(child.keyframes, time, Coupling.rotation_for(child, time, here, nodes))
	record()
	return ""


# Why the child cannot start riding on the parent at the time, or an empty
# string when it can.
func coupling_problem(child: Feature, parent: Feature, time: float) -> String:
	if child == null or child.is_group:
		return "Only a feature can ride on another feature."
	if child.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return "%s is a topology and has no motion of its own to couple." % child.title
	if parent == null:
		return "Pick the feature %s is to ride on." % child.title
	if parent == child:
		return "%s cannot ride on itself." % child.title
	if parent.is_group:
		return "%s is a group; a feature rides on another feature." % parent.title
	if parent.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return "%s is a topology and has no motion of its own to ride on." % parent.title
	var nodes := Coupling.index(root)
	if nodes.get(child.uuid) != child or nodes.get(parent.uuid) != parent:
		return "Both features have to be in the document."
	var current := Coupling.span_at(child, time)
	if current != null:
		var rides_on: Feature = nodes.get(current.parent)
		return "%s already rides on %s at %s Ma; decouple it first." % [
			child.title, rides_on.title if rides_on != null else "a missing feature", time]
	if Coupling.reaches(nodes, parent, child):
		return "%s already rides on %s, so the chain would go round in a circle." % [
			parent.title, child.title]
	var end := _span_end(child, time)
	if float(parent.time_range.x) > end or float(parent.time_range.y) < time:
		return "%s is not there all the way from %s to %s Ma; it exists from %d to %d Ma." % [
			parent.title, time, end, parent.time_range.x, parent.time_range.y]
	return ""


# End the span in effect at the time there. A keyframe at the time holds the
# world pose and the keyframes the span covered younger than the time are
# dropped. Decoupling where the span starts takes the whole span away.
func decouple(child: Feature, time: float) -> String:
	if child == null or child.is_group:
		return "Only a feature rides on another."
	var span := Coupling.span_at(child, time)
	if span == null:
		return "%s rides on nothing at %s Ma." % [child.title, time]
	if span.to <= 0.0 and is_equal_approx(time, 0.0) and not is_equal_approx(span.from, 0.0):
		return "%s rides on to the present; decouple it at an older time." % child.title
	var nodes := Coupling.index(root)
	var here := Coupling.world_basis(child, time, nodes)
	_drop_younger_keyframes(child, span, time)
	var worlds := _keyframe_worlds(child, nodes)
	if is_equal_approx(time, span.from):
		child.couplings.erase(span)
	else:
		span.to = time
	_rebase(child, worlds, nodes)
	Keyframe.upsert(child.keyframes, time, Coupling.rotation_for(child, time, here, nodes))
	record()
	return ""


# Take a span away. Every keyframe it held becomes the world pose it gave, so the
# feature stands where it stood at each of them. Unlike Couple and Decouple this
# keeps the keyframes and so changes the path between them: taking a relation
# away is expected to, and undo brings it back.
func remove_coupling(child: Feature, index: int) -> String:
	if child == null or child.is_group:
		return "Only a feature rides on another."
	if index < 0 or index >= child.couplings.size():
		return "%s has no coupling %d." % [child.title, index + 1]
	var nodes := Coupling.index(root)
	var worlds := _keyframe_worlds(child, nodes)
	child.couplings.remove_at(index)
	_rebase(child, worlds, nodes)
	record()
	return ""


# Where a span starting at the time ends: where the next span towards the
# present starts, or the present.
func _span_end(child: Feature, time: float) -> float:
	var end := 0.0
	for span in child.couplings:
		if span.from < time:
			end = maxf(end, span.from)
	return end


# Drop the keyframes the span covers younger than the time. That is the younger
# half of the cut a coupling edit makes: the keyframe the edit writes at the time
# is then the youngest one the span holds, and the feature rides rigidly, or
# stands still, from there on. Keyframes older than the time and keyframes the
# span does not cover are left alone, frames and all.
func _drop_younger_keyframes(child: Feature, span: Coupling, time: float) -> void:
	for i in range(child.keyframes.size() - 1, -1, -1):
		var at := child.keyframes[i].time
		if at < time and not is_equal_approx(at, time) and span.holds(at):
			child.keyframes.remove_at(i)


# Where each keyframe of the child stands in the world, in keyframe order, so
# _rebase() can put it back after the couplings change.
func _keyframe_worlds(child: Feature, nodes: Dictionary) -> Array[Basis]:
	var worlds: Array[Basis] = []
	for keyframe in child.keyframes:
		worlds.append(Coupling.world_basis(child, keyframe.time, nodes))
	return worlds


# Put each keyframe back where it stood, in the frame the couplings now put it
# in. After a cut only the keyframe at the edit time can have changed frame, and
# that one is written again straight after; Remove is what this really works for.
func _rebase(child: Feature, worlds: Array[Basis], nodes: Dictionary) -> void:
	for i in child.keyframes.size():
		var keyframe := child.keyframes[i]
		keyframe.rotation = Coupling.rotation_for(child, keyframe.time, worlds[i], nodes)


func _check_keyframe(node: Feature, index: int) -> String:
	if node == null:
		return "Nothing is selected."
	if node.is_group:
		return "%s is a group and has no keyframes." % node.title
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
	# The root has nothing above it to inherit from.
	if loaded.style != null and loaded.style.mode == Styling.INHERIT:
		loaded.style.mode = Styling.BY_FEATURE

	root = loaded
	view = ViewSettings.from_json(migrated.get("view"))
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
	if not _is_older_than(version, "0.13.0"):
		return data
	data = data.duplicate(true)
	if _is_older_than(version, "0.2.0"):
		data["features"] = _to_0_2_0(data.get("features", {}))
	if _is_older_than(version, "0.4.0"):
		data["features"] = _to_0_4_0(data.get("features", {}))
	if _is_older_than(version, "0.8.0"):
		data["features"] = _to_0_8_0(data.get("features", {}), [])
	var view: Variant = data.get("view")
	if _is_older_than(version, "0.9.0"):
		data["features"] = _to_0_9_0(data.get("features", {}))
		if view is Dictionary and view.get("hidden_classes") is Array:
			view["hidden_classes"] = view["hidden_classes"].map(
				func(name: Variant) -> Variant: return "circles" if name == "small_circles" else name)
	if _is_older_than(version, "0.10.0"):
		_to_0_10_0(data)
	# 0.11.0 added the age ramp to the group style. A style without it takes the
	# default ramp, which nothing drew with before, so there is no step.
	# 0.12.0 added couplings to a leaf. A leaf without them rides on nothing,
	# which is what every feature did before, so there is no step either.
	_to_0_13_0(data.get("features", {}))
	data["version"] = "0.13.0"
	return data


# 0.13.0 made the group style's ramp a list of two or more colours. A style that
# named both ends keeps them as the two stops of the new list; one that named
# only one of them, or neither, takes the new default, black to white.
static func _to_0_13_0(node: Variant) -> void:
	if node is not Dictionary:
		return
	var style: Variant = node.get("style")
	if style is Dictionary:
		var ends: Array = []
		for key in ["ramp_from", "ramp_to"]:
			if style.has(key):
				ends.append(style[key])
			style.erase(key)
		if ends.size() == 2:
			style["ramp_colors"] = ends
	for child in node.get("children", []):
		_to_0_13_0(child)


# 0.10.0 gave groups a style, in place of GPlates layer coloring. The document's
# draw style, single colour and palette left the view block and became the style
# of the root group, which is the document default. A block that named none of
# them leaves the root on its default, each feature's own colour.
static func _to_0_10_0(data: Dictionary) -> void:
	var view: Variant = data.get("view")
	var features: Variant = data.get("features")
	if view is not Dictionary:
		return
	var style := GroupStyle.json_from_view_block(view)
	for key in GroupStyle.VIEW_KEYS:
		view.erase(key)
	if not style.is_empty() and features is Dictionary:
		features["style"] = style


# The eight types up to 0.8.0 and the one each became. Unclassified, and a type
# no catalog had, is left to the geometry, and so is a type that no longer holds
# the kind: a coastline drawn as a line is a Line.
const TYPES_BEFORE_0_9_0 := {
	"craton": "polygon",
	"terrane": "polygon",
	"coastline": "polygon",
	"ridge": "line",
	"marker": "points",
	"small_circle": "circle",
	"topology": "topology",
}


# 0.9.0 cut the type catalog down to what the program treats differently:
# Polygon, Line, Points, Circle and Topology. Feature.feature_type settles
# whatever the id left open against the geometry the feature holds. The View
# menu switch for circles, stored by name, lost its "small" at the same time.
static func _to_0_9_0(node: Variant) -> Variant:
	if node is not Dictionary:
		return node
	if node.get("is_group", node.get("type") == "Group"):
		var children: Array = []
		for child in node.get("children", []):
			children.append(_to_0_9_0(child))
		node["children"] = children
		return node
	node["feature_type"] = TYPES_BEFORE_0_9_0.get(str(node.get("feature_type", "")), FeatureType.NONE)
	return node


# Up to 0.7.0 a group had keyframes and everything under it inherited them.
# 0.8.0 took motion off groups: only a leaf moves. Every leaf under a moving
# group gets the composition of the chain's rotations as keyframes of its own,
# sampled at every time any keyframe along the chain sits at, so what was drawn
# at each of those times is drawn there still. Between two of them a slerp of
# the composed rotations is not the composition of the slerps, so a file with
# group motion may differ slightly between keyframes. The group's own list is
# dropped. `chain` is the keyframe lists of the moving groups above the node,
# root first.
static func _to_0_8_0(node: Variant, chain: Array) -> Variant:
	if node is not Dictionary:
		return node
	var is_group: bool = node.get("is_group", node.get("type") == "Group")
	var own := Keyframe.list_from_json(node.get("keyframes", []))
	if is_group:
		var below := chain.duplicate()
		if not own.is_empty():
			below.append(own)
		node.erase("keyframes")
		var children: Array = []
		for child in node.get("children", []):
			children.append(_to_0_8_0(child, below))
		node["children"] = children
		return node
	if chain.is_empty():
		return node
	var times := PackedFloat64Array()
	for list in chain:
		for keyframe in list:
			if not times.has(keyframe.time):
				times.append(keyframe.time)
	for keyframe in own:
		if not times.has(keyframe.time):
			times.append(keyframe.time)
	times.sort()
	var baked: Array[Keyframe] = []
	for time in times:
		var m := Basis()
		for list in chain:
			m = m * Feature.build_rotation_basis(Keyframe.interpolate(list, time))
		m = m * Feature.build_rotation_basis(Keyframe.interpolate(own, time))
		baked.append(Keyframe.create(time, Feature.decompose_rotation_degrees(m)))
	node["keyframes"] = Keyframe.list_to_json(baked)
	return node


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
