class_name Document
extends RefCounted

# The open document: the feature tree, the view settings, the file it came from
# and whether it differs from what is on disk.
#
# The undo stack is the only source of the dirty flag. Every edit records a
# version, of the tree and the view settings together; the document is clean
# exactly while the stack sits on the version that was last written to or read
# from a file, so undoing back to that point makes it clean again.

const APPLICATION := "geotekt"
const EXTENSION := ".geotekt"
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

# What the last split along a cut did besides the two halves, for the status
# bar: the other features it cut, each followed by the piece split off it; the
# half it set free of the feature's parent, or null; and whether it left a
# ridge. Not part of the document's content.
var split_children: Array[Feature] = []
var split_freed: Feature = null
var split_ridge := false

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


# Start an empty document with a fresh undo stack, as after File > New.
func reset(settings: ViewSettings = null) -> void:
	root = Feature.create_group("Planet")
	root.is_root = true
	root.style = GroupStyle.for_root()
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
func view_edited() -> void:
	if applied > 0 and versions[applied - 1].view.to_json() == view.to_json():
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


# Take a node out of the tree, and with it every ridge and crust built from a
# feature under it: a ridge running along one, and a crust whose half or ridge
# goes. They have no row in the feature tree to be found by and deleted from
# afterwards. One version.
func delete_node(node: Feature) -> String:
	if node == null or node.is_root:
		return "Select a feature or a group to delete."
	var parent := root.find_parent(node)
	if parent == null:
		return "%s is not in the tree." % node.title
	var gone := {}
	var stack: Array[Feature] = [node]
	while not stack.is_empty():
		var inside: Feature = stack.pop_back()
		gone[inside.uuid] = true
		stack.append_array(inside.children)
	var doomed: Array[Feature] = [node]
	# Ridges before crusts, so a crust whose ridge was just marked goes too.
	for crusts_now in [false, true]:
		for leaf in _sea_floor():
			if gone.has(leaf.uuid) or leaf.is_crust() != crusts_now:
				continue
			var built_from := Array(leaf.halves())
			if leaf.is_crust():
				built_from.append(leaf.crust_ridge)
			if built_from.any(func(uuid: String) -> bool: return gone.has(uuid)):
				gone[leaf.uuid] = true
				doomed.append(leaf)
	for leaf in doomed:
		root.find_parent(leaf).children.erase(leaf)
	record()
	return ""


# Every ridge and crust in the tree, in tree order.
func _sea_floor() -> Array[Feature]:
	var found: Array[Feature] = []
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_front()
		if node.is_sea_floor():
			found.append(node)
		stack.append_array(node.children)
	return found


func set_enabled(node: Feature, enabled: bool) -> void:
	node.enabled = enabled
	if node.is_group and not enabled:
		node.collapsed = true
	record()


func set_color(feature: Feature, color: Color) -> void:
	feature.color = color
	record()


# Give the feature one of the built in glyphs for its tree row, or none. Only a
# leaf carries one; a group's row shows whether the group is open.
func set_icon(feature: Feature, icon: String) -> String:
	if feature == null or feature.is_group:
		return "Only a feature has an icon."
	if not icon.is_empty() and not FeatureIcon.CATALOG.has(icon):
		return "There is no icon called %s." % icon
	feature.icon = icon
	record()
	return ""


# Give a group another style: how the features under it are colored and how
# opaque they are. Refused on a leaf, which has no style, and on the root,
# whose style is pinned.
func set_style(group: Feature, style: GroupStyle) -> String:
	if group == null or not group.is_group:
		return "Only a group has a style."
	if group.is_root:
		return "The root group's style cannot be changed."
	group.style = style.clone()
	record()
	return ""


# Give the feature another type. On a feature holding nothing any type goes,
# since the type is what the tools then draw into it; once it holds a shape only
# a type that holds that kind, which comes down to making a circle a polygon or
# a line again. The colour follows the type as long as
# it is still the one the old type gave it, so a colour someone picked is never
# overwritten.
#
# Circles and hotspots build their own rings, so they are picked on a feature
# holding nothing. A circle's rings come when it is drawn or given a center and
# radius, a hotspot's when the Draw tool places it. A hotspot is fixed in the
# world frame, so it is not picked on a feature that moves either.
func set_feature_type(feature: Feature, type_id: String) -> String:
	if not FeatureType.CATALOG.has(type_id):
		return "There is no feature type called %s." % type_id
	if type_id == FeatureType.CIRCLE and not feature.is_circle() and feature.has_geometry():
		return "A circle is built from its center and radius, so it is picked on an empty feature."
	var to_hotspot := type_id == FeatureType.HOTSPOT and not feature.is_hotspot()
	if to_hotspot and (feature.has_geometry() or not feature.keyframes.is_empty()
			or not feature.couplings.is_empty()):
		return "A hotspot builds its own geometry and never moves, so it is picked on an empty feature."
	if feature.has_geometry() and not FeatureType.allows(type_id, feature.kind_name()):
		return "A %s cannot be a %s, which is %s." % [
			feature.kind_name(), FeatureType.label(type_id),
			" or ".join(FeatureType.kinds(type_id))]
	if feature.color == FeatureType.color(feature.feature_type):
		feature.color = FeatureType.color(type_id)
	feature.feature_type = type_id
	if to_hotspot:
		feature.hotspot = Feature.NO_HOTSPOT
		Hotspot.rebuild(root, feature, current_time, Config.get_skip_increment())
	record()
	return ""


# The largest radius a circle takes, and the largest one drawn at both ends of
# its axis. At 90 degrees the two circles meet on the great circle between the
# poles; past it each would reach round the other.
const MAX_CIRCLE_RADIUS := 179.99
const MAX_POLAR_RADIUS := 90.0


# Give a circle another center, radius, segment count or antipode switch and
# rebuild its rings from them, in one undo version. The center is in the
# feature's own frame, as its rings are. A circle not drawn yet is drawn by it.
func set_circle(feature: Feature, axis: Vector2, radius: float, segments: int,
		polar: bool) -> String:
	if feature == null or not feature.is_circle():
		return "Only a circle has a center and a radius."
	var problem := check_coordinates(axis)
	if not problem.is_empty():
		return problem
	var most := MAX_POLAR_RADIUS if polar else MAX_CIRCLE_RADIUS
	if radius <= 0.0 or radius > most:
		return "The radius is %s°, outside 0° to %s°%s." % [
			radius, most, " for axis circles" if polar else ""]
	if segments < Circle.MIN_SEGMENTS or segments > Circle.MAX_SEGMENTS:
		return "A circle takes %d to %d segments, not %d." % [
			Circle.MIN_SEGMENTS, Circle.MAX_SEGMENTS, segments]
	feature.axis = axis
	feature.radius = radius
	feature.circle_segments = segments
	feature.polar = polar
	feature.rebuild_circle()
	record()
	return ""


# Give a hotspot another place, plate or time step and rebuild its rings, in one
# undo version. The place is in the world frame, where the hotspot is fixed, or
# Feature.NO_HOTSPOT, so the plate can be picked before the hotspot is placed.
func set_hotspot(feature: Feature, hotspot: Vector2, plate_uuid: String,
		time_step: float) -> String:
	if feature == null or not feature.is_hotspot():
		return "Only a hotspot has a place, a plate and a time step."
	var problem := "" if hotspot == Feature.NO_HOTSPOT else check_coordinates(hotspot)
	if problem.is_empty():
		problem = Hotspot.plate_problem(root, feature, plate_uuid)
	if problem.is_empty():
		problem = check_time_step(time_step)
	if not problem.is_empty():
		return problem
	feature.hotspot = hotspot
	feature.plate_uuid = plate_uuid
	feature.time_step = time_step
	Hotspot.rebuild(root, feature, current_time, Config.get_skip_increment())
	record()
	return ""


# Give a crust its own time step and rebuild its bands, in one undo version. A
# crust is generated, but the step is a setting on it, like the step of a
# hotspot, so this is the one thing about a crust anybody edits.
func set_crust_step(feature: Feature, time_step: float) -> String:
	if feature == null or not feature.is_crust():
		return "Only a crust has a time step of its own."
	var problem := check_time_step(time_step)
	if not problem.is_empty():
		return problem
	feature.time_step = time_step
	Crust.rebuild(root, feature, current_time, Config.get_skip_increment())
	record()
	return ""


# Why that time step cannot be, or an empty string when it can. 0 is the
# timeline's Skip; anything above it is the feature's own step.
func check_time_step(time_step: float) -> String:
	if time_step < 0.0 or time_step > Hotspot.MAX_STEP:
		return "The time step is %s My, outside 0 to %s My." % [time_step, Hotspot.MAX_STEP]
	return ""


# Give a feature another line width, a multiple of what its type draws at, in
# one undo version. Refused on a group, which draws nothing, and on a feature
# that has no lines to widen: a polygon, a multipoint or a closed topology.
func set_line_width(feature: Feature, line_width: float) -> String:
	if feature == null or feature.is_group:
		return "Only a feature has a line width."
	if not feature.draws_lines():
		return "A %s%s has no lines to widen." % [
			"closed " if feature.closed else "", feature.kind_name()]
	if line_width < Feature.MIN_LINE_WIDTH or line_width > Feature.MAX_LINE_WIDTH:
		return "The line width is %s, outside %s to %s." % [line_width,
			Feature.MIN_LINE_WIDTH, Feature.MAX_LINE_WIDTH]
	feature.line_width = line_width
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


# The shape of a feature, in world coordinates at the current time, as
# {"kind": GeometryKind, "rings": Array[PackedVector2Array]}, or an empty
# dictionary when there is nothing to take. This is what Copy Shape holds on to.
#
# A topology has no vertices of its own, so what comes out of one is what its
# sections resolve to, one run per section, which is a polyline, or for a closed
# one the single ring, which is a polygon. That is the one way to turn a
# topology into a shape someone can edit. A ridge and a crust are copied as the
# rings they were last rebuilt into: the ridge's one line and the crust's bands.
func shape_of(feature: Feature) -> Dictionary:
	if feature == null or feature.is_group or not feature.has_geometry():
		return {}

	var rings: Array[PackedVector2Array] = []
	if feature.geometry_kind == Feature.GeometryKind.TOPOLOGY \
			and not feature.midway and not feature.is_crust():
		for entry in Topology.resolve(root, feature, current_time):
			var run: PackedVector2Array = entry["vertices"]
			if not run.is_empty():
				rings.append(run)
		if rings.is_empty():
			return {}
		# A closed one is copied as the one ring it is drawn as.
		if feature.closed:
			rings.assign([Topology.join(rings)])
		return {"kind": feature.drawn_as(), "rings": rings}

	var to_world := Feature.world_basis(root, feature, current_time)
	for ring in feature.rings:
		rings.append(Feature.apply_basis(ring, to_world))
	if rings.is_empty():
		return {}
	return {"kind": feature.drawn_as(), "rings": rings}


# Append a shape taken with shape_of() to a feature, in the frame that feature
# has at the current time, so the vertices land where they were copied from.
# This is what Paste Shape does, in one undo version.
#
# A feature holding nothing takes the shape's kind, and its type follows the
# kind. One already holding another kind is refused: the parts of a feature are
# all of one kind.
func paste_shape(feature: Feature, shape: Dictionary) -> String:
	if feature == null or feature.is_group:
		return "Only a feature takes a shape."
	if shape.is_empty():
		return "There is no shape to paste."

	if feature.is_circle():
		return "A circle is built from its center and radius, so a shape cannot be added to it."
	if feature.is_hotspot():
		return "A hotspot is built from its place and its plate, so a shape cannot be added to it."
	var kind: Feature.GeometryKind = shape["kind"]
	if feature.has_geometry():
		if feature.geometry_kind == Feature.GeometryKind.TOPOLOGY:
			return "A topology borrows its vertices, so a shape cannot be added to it."
		if feature.geometry_kind != kind:
			return "A %s cannot take a %s." % [feature.kind_name(), Feature.KIND_NAMES[kind]]

	var into_local := Feature.world_basis(root, feature, current_time).transposed()
	for ring in shape["rings"]:
		feature.add_ring(Feature.apply_basis(ring, into_local), kind)
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


# Cut a polygon along a path drawn across it, in the feature's own frame, into
# the pieces on one side of the path and those on the other; see
# GeometryEdit.cut_pieces(). Every part the path crosses is cut, and a part it
# misses goes by the side of the path its middle is on. The feature keeps its
# side, with its title and every other property, and a copy, "<title> 2"
# beside it, takes the other; either may end up with several parts. `part` is
# the part whose side the feature keeps when the cut crosses more than one. One
# version.
#
# With `ridge` on, one midway topology is left along the whole cut as well,
# between the two sides, bays and the sea between islands included; see
# _ridge_sections() and Docs/Editing.md#the-ridge. With `crust` on as well, each
# half gets a crust of bands between isochrons, with the isochrons and flowlines
# drawn over them; see _add_crust().
#
# An older ridge or topology running along a feature the split changes is
# pointed at the piece now holding its vertices, and a cut across an older
# ridge's coast is refused; see _repoint() and _older_ridge_problem().
#
# When the feature follows a parent, the half on the other side of the path
# from the parent stops following it at the current time, where it stands. With
# `children` on, everything that follows the parent, or the feature itself when
# it follows nothing, all the way down, is cut or sorted the same way; see
# _sort_riders(). Docs/Editing.md#the-split-tool.
func split_feature_along(feature: Feature, part: int, path: PackedVector2Array,
		ridge: bool = false, crust: bool = false, children: bool = false) -> String:
	if feature == null or feature.is_group \
			or feature.geometry_kind != Feature.GeometryKind.POLYGON:
		return "Only a polygon is split along a cut."
	if part < 0 or part >= feature.rings.size():
		return "The feature has no part %d." % part
	return _split_by_path(feature, part, path, ridge, crust, children)


# Divide a feature of several polygons along a path that touches none of them:
# the same as a cut that crosses no part, each part going to the side of the
# path its middle is on, the first part's side staying with the feature. See
# GeometryEdit.far_parts() and Docs/Editing.md#dividing. With `ridge` on the
# whole path is the ridge, and `crust` fills the sea on either side of it. One
# version.
func divide_feature(feature: Feature, path: PackedVector2Array, children := false,
		ridge := false, crust := false) -> String:
	if feature == null or feature.is_group \
			or feature.geometry_kind != Feature.GeometryKind.POLYGON:
		return "Only a polygon is split along a cut."
	var problem := GeometryEdit.divide_problem(feature.rings, path)
	if not problem.is_empty():
		return problem
	return _split_by_path(feature, 0, path, ridge, crust, children)


func _split_by_path(feature: Feature, part: int, path: PackedVector2Array,
		ridge: bool, crust: bool, children: bool) -> String:
	var parent := root.find_parent(feature)
	if parent == null:
		return "%s is not in the tree." % feature.title
	var sorted := _rings_by_side(feature.rings, path, feature.geometry_kind, part)
	if not str(sorted["problem"]).is_empty():
		return sorted["problem"]
	var first: int = sorted["first"]
	var rings: Dictionary = sorted["rings"]
	if (rings[first] as Array).is_empty() or (rings[-first] as Array).is_empty():
		return "The cut leaves every part on one side."
	var watched := _watch_sections()
	var problem := _older_ridge_problem(watched, feature, rings)
	if not problem.is_empty():
		return problem
	_cut_edges = {}

	# What the feature follows, found before anything changes.
	var span := Coupling.span_at(feature, current_time)
	var leader: Feature = null
	if span != null and span.parent_b.is_empty():
		leader = Coupling.index(root).get(span.parent)
	var riders: Array[Feature] = []
	if children:
		riders = Coupling.children_of(root, (leader if leader != null else feature).uuid,
			current_time)
	var world_path := Feature.apply_basis(path, Feature.world_basis(root, feature, current_time))
	var leader_side := first
	if leader != null:
		leader_side = _side_of_node(leader, world_path)

	var kept: Array[PackedVector2Array] = []
	kept.assign(rings[first])
	var given: Array[PackedVector2Array] = []
	given.assign(rings[-first])
	feature.rings = kept
	feature.rebuild_triangles()
	var other := feature.duplicate()
	other.title = Feature.clamp_title("%s 2" % feature.title)
	other.rings = given
	other.rebuild_triangles()
	parent.children.insert(parent.find_child(feature) + 1, other)

	# Who stands in for whom on each side of the path: a feature cut stands for
	# itself by its piece there, and one left whole by its parent's stand-in on
	# the side it is not on.
	var stand_in := {feature.uuid: {first: feature, -first: other}}
	split_freed = null
	if leader != null:
		var free: Feature = stand_in[feature.uuid][-leader_side]
		stand_in[leader.uuid] = {leader_side: leader, -leader_side: free}
		_let_go(free, current_time)
		split_freed = free
	split_children.clear()
	var changed := {feature.uuid: [feature, other]}
	_sort_riders(riders, feature, world_path, stand_in, leader_side, watched, changed)
	_repoint(watched, changed)

	_cut_edges[feature.uuid] = sorted["edges"]
	var sections: Array[TopologySection] = []
	if ridge:
		sections = _ridge_sections(world_path, stand_in, feature.uuid, first)
	split_ridge = not sections.is_empty()
	if split_ridge:
		var laid := _add_ridge(parent, feature, other, sections)
		if crust:
			var edge := 0
			for section in sections:
				if section.side == 0:
					edge += section.points.size() if section.is_gap() \
						else absi(section.to_index - section.from_index) + 1
			_add_crust(parent, laid, [feature, other], edge)
	record()
	return ""


# The edge of every stretch a split cut, by the uuid of the feature it cut, in
# that feature's own frame; see GeometryEdit.cut_pieces(). Filled while a split
# cuts, for _ridge_sections().
var _cut_edges := {}

# How close to the path, along it, a vertex has to be to count as reached: a
# fraction of a segment of the path.
const ALONG_CLOSE := 1e-6


# The two sides of the ridge a cut leaves, as the sections of a midway topology
# in the order the cut runs, side 0 the side the split feature keeps; see
# Logic/ridge.gd. Empty when the cut leaves no ridge of two vertices or more.
#
# The cut line runs from where it first enters to where it last leaves any
# polygon it cut, the split feature or anything cut under Children. Where it
# runs through land, each side is the coast that land's piece on that side has:
# a coast piece, naming the piece, the part and the run of its vertices. Where
# two edges overlap, a continent and the craton on it, the one reached first
# along the path is followed until it ends. Where the cut crosses sea, a bay or
# the strait between two islands, each side is a gap piece: the path's points
# there, riding with the split feature's half on that side, which is the plate
# everything on that side moves with. A divide is all gap.
func _ridge_sections(world_path: PackedVector2Array, stand_in: Dictionary,
		split_uuid: String, first: int) -> Array[TopologySection]:
	var runs := []
	for uuid: String in _cut_edges:
		var basis := Feature.world_basis(root, stand_in[uuid][first], current_time)
		for edge: PackedVector2Array in _cut_edges[uuid]:
			var along := PackedFloat64Array()
			for vertex in Feature.apply_basis(edge, basis):
				along.append(_along(world_path, vertex))
			if along[0] > along[-1]:
				edge = edge.duplicate()
				edge.reverse()
				along.reverse()
			runs.append({"uuid": uuid, "edge": edge, "along": along})
	runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["along"][0] < b["along"][0])

	# Walk the path: the coast of each edge from where the last one ended, and
	# the path's own points between two coasts.
	var pieces := []
	var reached := -INF
	for run: Dictionary in runs:
		var along: PackedFloat64Array = run["along"]
		var from := 0
		while from < along.size() and along[from] <= reached + ALONG_CLOSE:
			from += 1
		if from == along.size():
			continue
		if not pieces.is_empty():
			var sea := PackedVector2Array()
			for k in world_path.size():
				if k > reached + ALONG_CLOSE and k < along[from] - ALONG_CLOSE:
					sea.append(world_path[k])
			if not sea.is_empty():
				pieces.append(sea)
		pieces.append({"uuid": run["uuid"], "run": (run["edge"] as PackedVector2Array).slice(from)})
		reached = along[-1]
	if pieces.is_empty():
		pieces.append(world_path)

	var sections: Array[TopologySection] = []
	for side in [first, -first]:
		var plate: Feature = stand_in[split_uuid][side]
		var count := 0
		for piece: Variant in pieces:
			if piece is PackedVector2Array:
				var local := Feature.apply_basis(piece,
					Feature.world_basis(root, plate, current_time).transposed())
				sections.append(TopologySection.gap(plate.uuid, local, int(side != first)))
				count += local.size()
				continue
			var found := _coast_sections(stand_in[piece["uuid"]][side], piece["run"],
				int(side != first))
			if found.is_empty():
				return [] as Array[TopologySection]
			sections.append_array(found)
			count += (piece["run"] as PackedVector2Array).size()
		if count < 2:
			return [] as Array[TopologySection]
	return sections


# How far along the path a point lies, in segments: k and a fraction on the
# k-th segment, measured on the sphere. A point off either end of the path
# falls before 0 or past the last segment.
static func _along(path: PackedVector2Array, point: Vector2) -> float:
	var p := Feature._latlon_to_xyz_s(point)
	var best := INF
	var at := 0.0
	for k in path.size() - 1:
		var a := Feature._latlon_to_xyz_s(path[k])
		var b := Feature._latlon_to_xyz_s(path[k + 1])
		var normal := a.cross(b)
		var length := a.angle_to(b)
		if normal.length() < 1e-12 or length < 1e-12:
			continue
		normal = normal.normalized()
		var t := atan2(a.cross(p).dot(normal), a.dot(p)) / length
		var low := -INF if k == 0 else 0.0
		var high := INF if k == path.size() - 2 else 1.0
		var off := absf(p.dot(normal))
		if t < low or t > high:
			off = minf(p.angle_to(a), p.angle_to(b))
			t = clampf(t, 0.0, 1.0)
		if off < best:
			best = off
			at = k + t
	return at


# The run of a piece's coast as sections on one side of a ridge: one, or two
# when the run goes round past the end of its ring, since a range cannot.
func _coast_sections(piece: Feature, run: PackedVector2Array, side: int) -> Array[TopologySection]:
	var sections: Array[TopologySection] = []
	for part in piece.rings.size():
		var found := _find_run(piece.rings[part], run)
		if found.is_empty():
			continue
		var size := piece.rings[part].size()
		var start: int = found[0]
		var head := mini(run.size(), size - start)
		var chunks := [[start, start + head - 1]]
		if head < run.size():
			chunks.append([0, run.size() - head - 1])
		if found[1]:
			chunks.reverse()
		for chunk: Array in chunks:
			var section := TopologySection.create(piece.uuid, part, chunk[0], chunk[1], found[1])
			section.side = side
			sections.append(section)
		return sections
	return sections


# The rings of a feature by the side of the path they end up on, as a
# dictionary: problem, rings {LEFT: [...], RIGHT: [...]}, first (the side the
# feature keeps), and edges, the edge of every stretch the path cut, in the
# order and direction it runs through each part. The other half's rings start
# with the cut part's other piece.
func _rings_by_side(parts: Array[PackedVector2Array], path: PackedVector2Array,
		kind: Feature.GeometryKind, part: int) -> Dictionary:
	var result := {"problem": "", "rings": {GeometryEdit.LEFT: [], GeometryEdit.RIGHT: []},
		"first": 0, "edges": []}
	var rings: Dictionary = result["rings"]
	var lead := -1
	var lead_other := -1
	for i in parts.size():
		var ring := parts[i]
		if kind == Feature.GeometryKind.POLYLINE:
			var runs := GeometryEdit.cut_runs(ring, path)
			for side in runs:
				rings[side].append_array(runs[side])
			continue
		var cut := GeometryEdit.cut_pieces(ring, path) if kind == Feature.GeometryKind.POLYGON \
			else {"problem": GeometryEdit.OUTSIDE_PROBLEM}
		if cut["problem"] == GeometryEdit.OUTSIDE_PROBLEM:
			rings[_side_of_ring(ring, path)].append(ring)
			continue
		if not str(cut["problem"]).is_empty():
			result["problem"] = cut["problem"]
			return result
		result["edges"].append_array(cut["edges"])
		var side: int = cut["first"]
		if lead < 0 or i == part:
			lead = i
			result["first"] = side
			lead_other = rings[-side].size()
		for on in [GeometryEdit.LEFT, GeometryEdit.RIGHT]:
			rings[on].append_array(cut["pieces"][on])
	if lead < 0:
		result["first"] = _side_of_ring(parts[0], path) if not parts.is_empty() else GeometryEdit.LEFT
	else:
		# The cut part's other piece goes first in the other half.
		var other: Array = rings[-int(result["first"])]
		other.push_front(other.pop_at(lead_other))
	return result


func _side_of_ring(ring: PackedVector2Array, path: PackedVector2Array) -> int:
	return GeometryEdit.sides(path, PackedVector2Array([GeometryEdit.sphere_middle(ring)]))[0]


# The side of a world path the middle of a node lies on, where it stands now.
func _side_of_node(node: Feature, world_path: PackedVector2Array) -> int:
	var middle := Feature._xyz_to_latlon_s(
		Feature.world_basis(root, node, current_time) * Kinematics.centroid(node))
	return GeometryEdit.sides(world_path, PackedVector2Array([middle]))[0]


# Cut or sort everything riding along with the split, parents before their
# children. A polygon or a line the path crosses is cut, its pieces on the
# `keep` side staying in the feature and the rest going to a copy beside it; a
# feature the path misses goes whole to the side its middle is on. Each piece
# then follows its old parent's stand-in on its own side. Circles, hotspots,
# ridges and crusts are left alone, and so is anything that follows two
# parents, and whatever follows them.
func _sort_riders(riders: Array[Feature], split: Feature, world_path: PackedVector2Array,
		stand_in: Dictionary, keep: int, watched: Array, changed: Dictionary) -> void:
	var pending: Array[Feature] = riders.filter(func(node: Feature) -> bool: return node != split)
	var moved := true
	while moved:
		moved = false
		for rider in pending.duplicate():
			var span := Coupling.span_at(rider, current_time)
			if span == null or not stand_in.has(span.parent):
				continue
			pending.erase(rider)
			moved = true
			if not span.parent_b.is_empty() or rider.is_group or rider.is_circle() \
					or rider.is_hotspot() or rider.geometry_kind == Feature.GeometryKind.TOPOLOGY:
				continue
			_sort_rider(rider, span.parent, world_path, stand_in, keep, watched, changed)


func _sort_rider(rider: Feature, parent_uuid: String, world_path: PackedVector2Array,
		stand_in: Dictionary, keep: int, watched: Array, changed: Dictionary) -> void:
	var local := Feature.apply_basis(world_path,
		Feature.world_basis(root, rider, current_time).transposed())
	var rings: Dictionary
	if rider.geometry_kind == Feature.GeometryKind.MULTIPOINT:
		rings = {GeometryEdit.LEFT: [], GeometryEdit.RIGHT: []}
		for ring in rider.rings:
			rings[_side_of_ring(ring, local)].append(ring)
	else:
		var sorted := _rings_by_side(rider.rings, local, rider.geometry_kind, 0)
		if not str(sorted["problem"]).is_empty() \
				or not _older_ridge_problem(watched, rider, sorted["rings"]).is_empty():
			# A path the checks refuse here, crossing itself inside the rider or
			# crossing the coast an older ridge lies along, leaves it whole on its
			# middle's side.
			rings = {GeometryEdit.LEFT: [], GeometryEdit.RIGHT: []}
			rings[_side_of_node(rider, world_path)].assign(rider.rings)
		else:
			rings = sorted["rings"]
			if rider.geometry_kind == Feature.GeometryKind.POLYGON:
				_cut_edges[rider.uuid] = sorted["edges"]
	var stays := keep if not (rings[keep] as Array).is_empty() else -keep
	var pieces := {}
	var own: Array[PackedVector2Array] = []
	own.assign(rings[stays])
	rider.rings = own
	rider.rebuild_triangles()
	pieces[stays] = rider
	if not (rings[-stays] as Array).is_empty():
		var copy := rider.duplicate()
		copy.title = Feature.clamp_title("%s 2" % rider.title)
		var theirs: Array[PackedVector2Array] = []
		theirs.assign(rings[-stays])
		copy.rings = theirs
		copy.rebuild_triangles()
		var group := root.find_parent(rider)
		group.children.insert(group.find_child(rider) + 1, copy)
		pieces[-stays] = copy
		split_children.append_array([rider, copy])
	changed[rider.uuid] = pieces.values()
	var parent_stand_in: Dictionary = stand_in[parent_uuid]
	var own_stand_in := {}
	for side in [GeometryEdit.LEFT, GeometryEdit.RIGHT]:
		if pieces.has(side):
			var target: Feature = parent_stand_in[side]
			if target.uuid != parent_uuid:
				_follow_instead(pieces[side], parent_uuid, target)
			own_stand_in[side] = pieces[side]
		else:
			own_stand_in[side] = parent_stand_in[side]
	stand_in[rider.uuid] = own_stand_in


# Put the first half in place of the part and the second in a new feature beside
# the original, named after it: the Vertex tool's split.
func _split_into(feature: Feature, part: int, halves: Array[PackedVector2Array]) -> String:
	var parent := root.find_parent(feature)
	if parent == null:
		return "%s is not in the tree." % feature.title
	var watched := _watch_sections()
	var rings: Array = feature.rings.duplicate()
	rings[part] = halves[0]
	var problem := _older_ridge_problem(watched, feature, {0: rings, 1: [halves[1]]})
	if not problem.is_empty():
		return problem
	var other := _split_off(parent, feature, part, halves)
	_repoint(watched, {feature.uuid: [feature, other]})
	record()
	return ""


# Give the part the first half and a copy of the feature, "<title> 2" inserted
# after it, the second. Returns the copy.
func _split_off(parent: Feature, feature: Feature, part: int,
		halves: Array[PackedVector2Array]) -> Feature:
	var other := feature.duplicate()
	other.title = Feature.clamp_title("%s 2" % feature.title)
	var only: Array[PackedVector2Array] = [halves[1]]
	other.rings = only
	other.rebuild_triangles()
	feature.rings[part] = halves[0]
	feature.rebuild_triangles()
	parent.children.insert(parent.find_child(feature) + 1, other)
	return other


# Cut the span in effect at the current time there, the younger part following
# `instead` where the older one followed `uuid`, and keep every keyframe where it
# stands, the way couple() does.
func _follow_instead(child: Feature, uuid: String, instead: Feature) -> void:
	var nodes := Coupling.index(root)
	var here := Coupling.world_basis(child, current_time, nodes)
	var worlds := _keyframe_worlds(child, nodes)
	var span := Coupling.span_at(child, current_time)
	if not is_equal_approx(span.from, current_time):
		var older := span.clone()
		older.to = current_time
		span.from = current_time
		child.couplings.append(older)
		Coupling.sort(child.couplings)
	if span.parent == uuid:
		span.parent = instead.uuid
	else:
		span.parent_b = instead.uuid
	_rebase(child, worlds, nodes)
	Keyframe.upsert(child.keyframes, current_time,
		Coupling.rotation_for(child, current_time, here, nodes))


# Every topology section in the tree with the run of vertices it names now, in
# its feature's own frame and ring order, taken before a split changes the rings
# so _repoint() can find the run again afterwards. A section whose feature or part
# is gone is left out: there is nothing to follow.
func _watch_sections() -> Array:
	var watched: Array = []
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		stack.append_array(node.children)
		for section in node.sections:
			if section.is_gap():
				watched.append({"topology": node, "section": section, "run": section.points,
					"gap": true})
				continue
			var target := root.get_node_by_uuid(section.feature_uuid)
			if target == null or section.part < 0 or section.part >= target.rings.size():
				continue
			var ring: PackedVector2Array = target.rings[section.part]
			var low := clampi(mini(section.from_index, section.to_index), 0, ring.size() - 1)
			var high := clampi(maxi(section.from_index, section.to_index), 0, ring.size() - 1)
			watched.append({"topology": node, "section": section,
				"run": ring.slice(low, high + 1)})
	return watched


# Why a split giving the node these rings, by side, would break an older ridge:
# the run of one of its sections is no longer whole in any one of them, because
# the cut crosses it. Splitting the ridge there as well waits for GP-0121. Empty
# when nothing breaks.
func _older_ridge_problem(watched: Array, node: Feature, rings: Dictionary) -> String:
	for entry: Dictionary in watched:
		var topology: Feature = entry["topology"]
		var section: TopologySection = entry["section"]
		if not topology.midway or section.feature_uuid != node.uuid or entry.has("gap"):
			continue
		var found := false
		for side_rings: Array in rings.values():
			for ring: PackedVector2Array in side_rings:
				found = found or not _find_run(ring, entry["run"]).is_empty()
		if not found:
			return "The cut crosses the coast %s lies along, and an older ridge cannot be split yet." \
				% topology.title
	return ""


# Point every watched section of a feature the split changed at the feature, part
# and range now holding its run: a section names its run by index, and a split
# moves the run within the ring, to another part, or to the copy. A crust whose
# half was that feature moves with its ridge's section, so it goes on moving with
# the plate that carries its coast. `changed` gives each changed feature's uuid
# the pieces its run may now be in. A run found nowhere is left as it was.
#
# A run that goes round past the end of its new ring has the ring turned to start
# with it, since a range cannot go round; the Vertex tool's halves start at the
# far vertex of the split, not at the cut. A gap piece goes with the piece
# nearest its points; see _point_gap().
func _repoint(watched: Array, changed: Dictionary) -> void:
	for entry: Dictionary in watched:
		var section: TopologySection = entry["section"]
		if not changed.has(section.feature_uuid) or entry.has("gap"):
			continue
		for piece: Feature in changed[section.feature_uuid]:
			for part in piece.rings.size():
				var found := _find_run(piece.rings[part], entry["run"])
				if found.is_empty() or found[0] + entry["run"].size() <= piece.rings[part].size():
					continue
				var ring: PackedVector2Array = piece.rings[part]
				piece.rings[part] = ring.slice(found[0]) + ring.slice(0, found[0])
				piece.rebuild_triangles()
	for entry: Dictionary in watched:
		var section: TopologySection = entry["section"]
		if not changed.has(section.feature_uuid):
			continue
		if entry.has("gap"):
			_point_gap(entry["topology"], section, changed[section.feature_uuid])
		else:
			_point(entry["topology"], section, entry["run"], changed[section.feature_uuid])


# Give a gap piece to the piece of its plate nearest its points, in the frame
# the pieces share: the one holding the coast beside the gap. A ridge side of
# gaps alone, a divide's, takes its crust along, the way a coast does in
# _point().
func _point_gap(topology: Feature, section: TopologySection, pieces: Array) -> void:
	var nearest := INF
	var carrier: Feature = null
	for piece: Feature in pieces:
		for ring in piece.rings:
			for vertex in ring:
				for point in section.points:
					if vertex.distance_squared_to(point) < nearest:
						nearest = vertex.distance_squared_to(point)
						carrier = piece
	if carrier == null or carrier.uuid == section.feature_uuid:
		return
	if topology.sections.all(func(other: TopologySection) -> bool:
			return other.side != section.side or other.is_gap()):
		_move_crusts(topology, section.feature_uuid, carrier.uuid)
	section.feature_uuid = carrier.uuid


# Point the section at the first of the pieces holding the run whole.
func _point(topology: Feature, section: TopologySection, run: PackedVector2Array,
		pieces: Array) -> void:
	for piece: Feature in pieces:
		for part in piece.rings.size():
			var found := _find_run(piece.rings[part], run)
			if found.is_empty() or found[0] + run.size() > piece.rings[part].size():
				continue
			if topology.midway and piece.uuid != section.feature_uuid:
				_move_crusts(topology, section.feature_uuid, piece.uuid)
			section.feature_uuid = piece.uuid
			section.part = part
			section.from_index = found[0]
			section.to_index = found[0] + run.size() - 1
			section.reversed = section.reversed != found[1]
			return


func _move_crusts(ridge: Feature, from_uuid: String, to_uuid: String) -> void:
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		stack.append_array(node.children)
		if node.is_crust() and node.crust_ridge == ridge.uuid and node.crust_half == from_uuid:
			node.crust_half = to_uuid


# Where a run lies in a ring vertex for vertex, as [first index, walked the other
# way], or empty when it is not there whole. The run may go round past the ring's
# last vertex. The vertices of a cut piece come back through the turned frame, so
# they are matched to about ten meters, not exactly.
static func _find_run(ring: PackedVector2Array, run: PackedVector2Array) -> Array:
	const CLOSE := 1e-4
	var count := run.size()
	if count > ring.size():
		return []
	for start in ring.size():
		for backwards: bool in [false, true]:
			var whole := true
			for k in count:
				var want := run[count - 1 - k] if backwards else run[k]
				if ring[(start + k) % ring.size()].distance_to(want) > CLOSE:
					whole = false
					break
			if whole:
				return [start, backwards]
	return []


# The rift the cut leaves behind: a midway topology between the two sides of the
# cut, from the current time to the present, with the sections
# _ridge_sections() found. The ridge has no motion of its own; see
# Logic/ridge.gd. Part of the split's own undo version.
func _add_ridge(parent: Feature, first: Feature, second: Feature,
		sections: Array[TopologySection]) -> Feature:
	var ridge := Feature.create_feature(Feature.clamp_title("%s ridge" % first.title),
		FeatureType.color(FeatureType.LINE), Vector2i(0, int(round(current_time))))
	ridge.feature_type = "topology"
	ridge.geometry_kind = Feature.GeometryKind.TOPOLOGY
	ridge.midway = true
	ridge.sections = sections
	parent.children.insert(parent.find_child(second) + 1, ridge)
	Topology.rebuild(root, ridge, current_time)
	return ridge


# The sea floor a ridge opens: one crust per half, inserted after the ridge with
# its time range, holding the bands between the isochrons and the isochrons and
# flowlines drawn over them. Its rings follow the time and the timeline's Skip,
# so Crust.rebuild_all() gives them to it. Part of the split's own undo version.
func _add_crust(parent: Feature, ridge: Feature, halves: Array, edge_size: int) -> void:
	var at := parent.find_child(ridge)
	for half: Feature in halves:
		var crust := Feature.create_feature(Feature.clamp_title("%s crust" % half.title),
			Color.WHITE, ridge.time_range)
		crust.feature_type = "topology"
		crust.geometry_kind = Feature.GeometryKind.TOPOLOGY
		crust.closed = true
		crust.crust_half = half.uuid
		crust.crust_ridge = ridge.uuid
		crust.crust_edge = edge_size
		at += 1
		parent.children.insert(at, crust)


### Topologies

# A topology's geometry is the list of sections it names; the vertices it draws
# are resolved from them whenever the tree or the current time moves. These four
# are the only things that change the list, and each records one undo version
# like every other edit, as does closing or opening it. See Logic/topology.gd.


# Join the sections into one filled ring, or leave them separate lines.
func set_topology_closed(feature: Feature, closed: bool) -> String:
	if feature == null or feature.geometry_kind != Feature.GeometryKind.TOPOLOGY:
		return "Only a topology can be closed."
	if feature.midway or feature.is_crust():
		return "%s is built from what it lies between, so it cannot be closed or opened." \
			% feature.title
	feature.closed = closed
	Topology.rebuild(root, feature, current_time)
	record()
	return ""


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
	var section := TopologySection.whole_part(target, part)
	# A midway topology's second section is its second side.
	section.side = int(feature.midway and not feature.sections.is_empty())
	feature.sections.append(section)
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

# A coupling is a span of the timeline over which a feature follows another.
# Couple and Decouple are a cut in time: nothing older than the time they act at
# changes at all, and the keyframes the span covered younger than that time are
# dropped, so the feature is rigid from the cut until the user moves it again.
# Remove is the exception and converts pointwise. Each records one version.
# See Logic/coupling.gd and Docs/Time.md#a-coupling-edit-is-a-cut-in-time.


# Start a span at the time: the feature follows the parent from then until the
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


# Why the child cannot start following the parent at the time, or an empty
# string when it can.
func coupling_problem(child: Feature, parent: Feature, time: float) -> String:
	if child == null or child.is_group:
		return "Only a feature can follow another feature."
	if child.feature_type == FeatureType.CIRCLE:
		return Coupling.CIRCLE_CHILD_PROBLEM
	if child.feature_type == FeatureType.HOTSPOT:
		return Coupling.HOTSPOT_CHILD_PROBLEM
	if child.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return "%s is a topology and has no motion of its own to couple." % child.title
	if parent == null:
		return "Pick the feature %s is to follow." % child.title
	if parent == child:
		return "%s cannot follow itself." % child.title
	if parent.is_group:
		return "%s is a group; a feature follows another feature." % parent.title
	if parent.feature_type == FeatureType.CIRCLE:
		return Coupling.CIRCLE_PARENT_PROBLEM
	if parent.feature_type == FeatureType.HOTSPOT:
		return Coupling.HOTSPOT_PARENT_PROBLEM
	if parent.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return "%s is a topology and has no motion of its own to follow." % parent.title
	var nodes := Coupling.index(root)
	if nodes.get(child.uuid) != child or nodes.get(parent.uuid) != parent:
		return "Both features have to be in the document."
	var current := Coupling.span_at(child, time)
	if current != null:
		return "%s already follows %s at %s Ma; decouple it first." % [
			child.title, Coupling.parents_label(nodes, current), time]
	if Coupling.reaches(nodes, parent, child):
		return "%s already follows %s, so the chain would go round in a circle." % [
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
		return "Only a feature follows another."
	var span := Coupling.span_at(child, time)
	if span == null:
		return "%s follows nothing at %s Ma." % [child.title, time]
	if span.to <= 0.0 and is_equal_approx(time, 0.0) and not is_equal_approx(span.from, 0.0):
		return "%s follows to the present; decouple it at an older time." % child.title
	_let_go(child, time)
	record()
	return ""


# End the span in effect at the time there, leaving the child standing where it
# stands, without recording a version: what decouple() and a split's freed half
# share.
func _let_go(child: Feature, time: float) -> void:
	var span := Coupling.span_at(child, time)
	if span == null:
		return
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


# Take a span away. Every keyframe it held becomes the world pose it gave, so the
# feature stands where it stood at each of them. Unlike Couple and Decouple this
# keeps the keyframes and so changes the path between them: taking a relation
# away is expected to, and undo brings it back.
func remove_coupling(child: Feature, index: int) -> String:
	if child == null or child.is_group:
		return "Only a feature follows another."
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
# is then the youngest one the span holds, and the feature follows rigidly, or
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
		return "%s is not a Geotekton file: the root is not an object" % file_path
	if data.get("application", "") != APPLICATION:
		return "%s is not a Geotekton file" % file_path

	var migrated := migrate(data)
	var loaded := Feature.from_json(migrated["features"])
	loaded.is_root = true
	# The root's style is pinned: the style block a file gives it is read and
	# then replaced, so a feature under no group of its own is drawn in its own
	# color at full opacity. Saving writes this style back, which is what an
	# older reader expects to find there.
	loaded.style = GroupStyle.for_root()

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
# no `.geotekt` file of its own yet, so it opens Untitled and dirty and
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
	view.raster_path = relative_raster(resolve_raster(), file_path)
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


### The raster
#
# The path is stored relative when the image sits in the project's own folder or
# under it, so a project and its images can be moved together, and absolute
# otherwise. A document with no path of its own has nothing to be relative to
# and stores what it was given. An image the application ships, a res:// path,
# is stored and resolved as it is.


# The path to write for an image the user picked, given where the file is going.
static func relative_raster(image_path: String, project_path: String) -> String:
	if image_path.is_empty() or project_path.is_empty() or image_path.is_relative_path() \
			or image_path.begins_with("res://"):
		return image_path
	var folder := project_path.get_base_dir().replace("\\", "/").rstrip("/")
	var image := image_path.replace("\\", "/")
	if folder.is_empty() or not image.begins_with(folder + "/"):
		return image_path
	return image.substr(folder.length() + 1)


# Where the raster actually is, resolved against the project file it was
# stored beside. Empty when the document names no image.
func resolve_raster() -> String:
	if view.raster_path.is_empty():
		return ""
	if view.raster_path.is_absolute_path() or view.raster_path.begins_with("res://"):
		return view.raster_path
	if path.is_empty():
		return view.raster_path
	return path.get_base_dir().path_join(view.raster_path)


# Bring a parsed file up to the format this version writes, based on the
# version field it carries. See Docs/Persistence.md for the formats themselves.
static func migrate(data: Dictionary) -> Dictionary:
	var version := str(data.get("version", "0.1.0"))
	if not _is_older_than(version, "0.30.0"):
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
	# 0.12.0 added couplings to a leaf. A leaf without them follows nothing,
	# which is what every feature did before, so there is no step either.
	if _is_older_than(version, "0.13.0"):
		_to_0_13_0(data.get("features", {}))
	# 0.14.0 gave a leaf an icon for its tree row. A leaf without the key has
	# none, which is what every feature had before, so there is no step.
	# 0.15.0 let a coupling span name a second parent. A span without the key
	# follows one parent, which is what every span did before, so there is
	# none either.
	if _is_older_than(version, "0.16.0") and view is Dictionary:
		rename_view_keys(view)
	if _is_older_than(version, "0.17.0"):
		data["view"] = _to_0_17_0(view)
	# 0.18.0 gave a leaf the axis, radius and segment count of polar circles.
	# A leaf without them is not polar circles, so there is nothing to change
	# but the version.
	# 0.19.0 gave a leaf the place, plate and track step of a hotspot. A leaf
	# without them is not a hotspot, so again only the version moves.
	# 0.20.0 let a topology be closed. A topology without the key is open, which
	# is what every topology was before, so once more only the version moves.
	if _is_older_than(version, "0.21.0"):
		_to_0_21_0(data.get("features", {}))
	if _is_older_than(version, "0.22.0"):
		_to_0_22_0(data.get("features", {}))
	if _is_older_than(version, "0.23.0"):
		_to_0_23_0(data.get("features", {}))
	if _is_older_than(version, "0.24.0"):
		_to_0_24_0(data.get("features", {}))
	# 0.25.0 gave a hotspot and a crust a time step of their own. A leaf without
	# the key carries 0, which follows the timeline's Skip, and that is what both
	# did before, so only the version moves.
	if _is_older_than(version, "0.26.0"):
		var dropped := _to_0_26_0(data.get("features", {}))
		if dropped > 0:
			push_warning(("%d coupling span%s on a circle or a hotspot %s dropped: "
				+ "neither takes part in coupling.") % [dropped,
				"" if dropped == 1 else "s", "was" if dropped == 1 else "were"])
	# 0.27.0 renamed the program, so a file now says geotekt in its application
	# field; a file from before it is not read. 0.29.0 gave a leaf its line
	# width, and a leaf without the key reads as 1, which is what every feature
	# was drawn at. 0.30.0 let a ridge's sections say their side and hold
	# points of their own, and a ridge of two sections without sides reads as
	# one a side; see Feature.from_json(). Nothing else in the file changed, so
	# only the version moves.
	data["version"] = "0.30.0"
	return data


# 0.26.0 took circles and hotspots out of coupling altogether, so every span
# whose child or parent is one goes. The features stay and so do their
# keyframes, so a child left without a span stops following but does not move.
# Answers with how many spans were dropped. See Docs/Persistence.md.
static func _to_0_26_0(features: Variant) -> int:
	var leaves: Array = []
	_leaves_of(features, leaves)
	var apart := {}
	for leaf: Dictionary in leaves:
		var uuid := str(leaf.get("uuid", ""))
		if not uuid.is_empty() and str(leaf.get("feature_type", "")) in \
				[FeatureType.CIRCLE, FeatureType.HOTSPOT]:
			apart[uuid] = true
	var dropped := 0
	for leaf: Dictionary in leaves:
		var spans: Variant = leaf.get("couplings")
		if spans is not Array or spans.is_empty():
			continue
		var kept: Array = []
		if not apart.has(str(leaf.get("uuid", ""))):
			kept = spans.filter(func(span: Variant) -> bool:
				return span is not Dictionary or not (apart.has(str(span.get("parent", "")))
					or apart.has(str(span.get("parent_b", "")))))
		dropped += spans.size() - kept.size()
		leaf["couplings"] = kept
	return dropped


# 0.24.0 put the isochrons and the flowlines into the crust feature itself, so
# the leaf that held them alone goes. A crust leaf carrying "lines": true is
# dropped; the crust beside it is already what it should be. See
# Docs/Persistence.md.
static func _to_0_24_0(node: Variant) -> void:
	if node is not Dictionary or node.get("children") is not Array:
		return
	var children: Array = node["children"]
	for child in children:
		_to_0_24_0(child)
	children.assign(children.filter(func(child: Variant) -> bool:
		return child is not Dictionary or child.get("crust") is not Dictionary \
			or not bool((child["crust"] as Dictionary).get("lines", false))))


# 0.23.0 made the ridge a midway topology and the crust bands between isochrons.
# A ridge the Split tool left, a Line with one ring, one keyframe and one span
# following two parents, becomes a midway topology between the two halves' sides
# of the cut, the second walked back; the side of the first half is in the part
# its crust names, else in part 0. A closed topology whose second section runs
# along such a ridge was its crust, and becomes one, with the lines feature
# inserted before it, so the bands do not hide them. See Docs/Persistence.md.
static func _to_0_23_0(features: Variant) -> void:
	var leaves: Array = []
	_leaves_of(features, leaves)
	var ridges := {}
	for leaf: Dictionary in leaves:
		if _is_ridge_before_0_23_0(leaf):
			ridges[str(leaf.get("uuid", ""))] = leaf
	var parts := {}
	for leaf: Dictionary in leaves:
		var sections: Variant = _crust_sections(leaf, ridges)
		if sections != null:
			parts[str(sections[0].get("feature", ""))] = int(sections[0].get("part", 0))
	for leaf: Dictionary in ridges.values():
		var span: Dictionary = leaf["couplings"][0]
		var last: int = (leaf["rings"][0] as Array).size() - 1
		var first := str(span.get("parent", ""))
		leaf["feature_type"] = "topology"
		leaf["geometry_kind"] = "topology"
		leaf["midway"] = true
		leaf["sections"] = [
			{"feature": first, "part": parts.get(first, 0), "from": 0, "to": last,
				"reversed": false},
			{"feature": str(span["parent_b"]), "part": 0, "from": 0, "to": last,
				"reversed": true},
		]
		leaf.erase("rings")
		leaf["keyframes"] = []
		leaf["couplings"] = []
	_crusts_to_0_23_0(features, ridges)


static func _leaves_of(node: Variant, leaves: Array) -> void:
	if node is not Dictionary:
		return
	if node.has("children"):
		for child in node["children"]:
			_leaves_of(child, leaves)
	elif not bool(node.get("is_group", false)):
		leaves.append(node)


static func _is_ridge_before_0_23_0(leaf: Dictionary) -> bool:
	var couplings: Variant = leaf.get("couplings")
	var keyframes: Variant = leaf.get("keyframes")
	var rings: Variant = leaf.get("rings")
	return str(leaf.get("geometry_kind", "")) == "polyline" \
		and couplings is Array and couplings.size() == 1 and couplings[0] is Dictionary \
		and not str(couplings[0].get("parent_b", "")).is_empty() \
		and keyframes is Array and keyframes.size() == 1 \
		and rings is Array and rings.size() == 1 and rings[0] is Array


# The two sections of a 0.22.0 crust, one along its half and one along one of
# the ridges, or null when the leaf is not one.
static func _crust_sections(leaf: Variant, ridges: Dictionary) -> Variant:
	if leaf is not Dictionary or not bool(leaf.get("closed", false)):
		return null
	var sections: Variant = leaf.get("sections")
	if sections is not Array or sections.size() != 2 or sections[0] is not Dictionary \
			or sections[1] is not Dictionary \
			or not ridges.has(str(sections[1].get("feature", ""))):
		return null
	return sections


static func _crusts_to_0_23_0(node: Variant, ridges: Dictionary) -> void:
	if node is not Dictionary or not node.has("children"):
		return
	var children: Array = node["children"]
	var index := 0
	while index < children.size():
		var child: Variant = children[index]
		index += 1
		_crusts_to_0_23_0(child, ridges)
		var sections: Variant = _crust_sections(child, ridges)
		if sections == null:
			continue
		child["crust"] = {"half": str(sections[0].get("feature", "")),
			"ridge": str(sections[1]["feature"]), "edge": int(sections[0].get("to", 0)) + 1}
		child["sections"] = []
		var lines: Dictionary = child.duplicate(true)
		lines["uuid"] = Helpers.generate_uuid_v4()
		lines["title"] = Feature.clamp_title("%s lines" % child.get("title", ""))
		var color := FeatureType.color(FeatureType.CRUST_LINES)
		lines["color"] = [color.r, color.g, color.b, color.a]
		lines.erase("closed")
		lines["crust"]["lines"] = true
		children.insert(index - 1, lines)
		index += 1


# 0.22.0 samples a hotspot's track at the timeline's Skip, so a hotspot leaf
# loses the track step it carried.
static func _to_0_22_0(node: Variant) -> void:
	if node is not Dictionary:
		return
	for child in node.get("children", []):
		_to_0_22_0(child)
	if str(node.get("feature_type", "")) == FeatureType.HOTSPOT:
		node.erase("track_step")


# 0.21.0 folded Polar circles into Circle. A polar circles leaf becomes a circle
# drawn at both ends of its axis, keeping its parameters. A drawn circle, which
# kept only its ring, is given the center, radius and segment count that ring
# was cut from; see Feature.fit_circle_json().
static func _to_0_21_0(node: Variant) -> void:
	if node is not Dictionary:
		return
	for child in node.get("children", []):
		_to_0_21_0(child)
	match str(node.get("feature_type", "")):
		"polar_circles":
			node["feature_type"] = FeatureType.CIRCLE
			node["polar"] = true
		FeatureType.CIRCLE:
			Feature.fit_circle_json(node)


# 0.17.0 gave the planet a color of its own and made the built in Earth, which
# was always under everything, a raster like any other. A file from before that
# names no raster showed the Earth, so it gets the Earth as its raster, fully
# opaque and shown, which is how it looked; the opacity and the switch did
# nothing without an image. A file naming an image keeps it, over the planet
# color now rather than over the Earth. A file with no view block at all gets
# one holding just the raster. Returns the block.
static func _to_0_17_0(view: Variant) -> Dictionary:
	var block: Dictionary = view if view is Dictionary else {}
	if str(block.get("raster_path", "")).is_empty():
		block["raster_path"] = ViewSettings.BUILT_IN_EARTH
		block["raster_opacity"] = 1.0
		block["raster_visible"] = true
	return block


# 0.16.0 renamed five keys of the view block, calling the backdrop image a
# raster, the word GPlates uses, and the graticule a grid.
const VIEW_KEYS_BEFORE_0_16_0 := {
	"backdrop_path": "raster_path",
	"backdrop_opacity": "raster_opacity",
	"backdrop_visible": "raster_visible",
	"graticule_color": "grid_color",
	"graticule_spacing": "grid_spacing",
}


# Rename the keys a view block had before 0.16.0, in place. The preferences'
# view_defaults hold the same block, so Config uses this too. A block naming a
# setting by both keys keeps the new one. Returns whether anything was renamed.
static func rename_view_keys(view: Dictionary) -> bool:
	var renamed := false
	for old: String in VIEW_KEYS_BEFORE_0_16_0:
		if not view.has(old):
			continue
		var value: Variant = view[old]
		view.erase(old)
		view.get_or_add(VIEW_KEYS_BEFORE_0_16_0[old], value)
		renamed = true
	return renamed


# The built in tables 0.13.0 dropped when the palette list became Custom and
# Rainbow. A style that named one of them has nothing left to read.
const PALETTES_BEFORE_0_13_0 := ["age", "grayscale", "steps"]


# 0.13.0 made the group style's ramp a list of two or more colours. A style that
# named both ends keeps them as the two stops of the new list; one that named
# only one of them, or neither, takes the new default, black to white. A style
# naming a built in table that is gone takes the custom ramp, which is what
# replaced them.
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
		if str(style.get("palette", "")) in PALETTES_BEFORE_0_13_0:
			style["palette"] = Palette.RAMP
	for child in node.get("children", []):
		_to_0_13_0(child)


# 0.10.0 gave groups a style, in place of GPlates layer coloring. The document's
# draw style, single colour and palette left the view block and became the style
# of the root group. A block that named none of them leaves the root on its
# default, each feature's own colour. load_from_file() pins the root's style
# afterwards, so what this step writes there is read and then replaced.
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
