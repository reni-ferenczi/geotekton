class_name Topology

# Resolving a line topology: turning its list of sections into the vertices it
# draws at one time. See Docs/Editing.md#line-topologies.
#
# A topology borrows its geometry from other features, so where it is follows
# from where they are. Resolving it at a time therefore means finding each
# section's feature, taking the run of vertices the section names and carrying
# that run through the rotation the feature has then.
#
# Nothing here touches a Document or a scene. Application rebuilds the resolved
# rings whenever the tree or the current time changes, and everything that
# draws, hit tests or measures a feature goes on reading rings and knows nothing
# about topologies.

# The fewest vertices a section can contribute and still be a piece of a line.
const MINIMUM_VERTICES := 2


# Every section of a topology at one time, in order, as one dictionary each:
#
#   vertices: the run in world coordinates, empty when the section is broken
#   problem:  why it contributes nothing, an empty string when it does
#   title:    the title of the feature it names, or an empty string
#
# A section is never dropped: one whose feature has been deleted comes back with
# the reason, so the panel can show it as broken and the file can keep it. That
# is what makes a topology survive a feature going away and coming back through
# an undo.
static func resolve(root: Feature, node: Feature, time: float) -> Array:
	var resolved: Array = []
	for section in node.sections:
		resolved.append(_resolve_section(root, node, section, time))
	return resolved


static func _resolve_section(root: Feature, node: Feature, section: TopologySection,
		time: float) -> Dictionary:
	var empty := PackedVector2Array()
	var target := root.get_node_by_uuid(section.feature_uuid) if root != null else null
	if target == null:
		return {"vertices": empty, "problem": "the feature it ran along is gone", "title": ""}
	if target == node:
		return {"vertices": empty, "problem": "a topology cannot run along itself",
			"title": target.title}
	if target.is_group:
		return {"vertices": empty, "problem": "a group has no vertices of its own",
			"title": target.title}
	if target.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return {"vertices": empty, "problem": "a topology cannot run along another one",
			"title": target.title}
	if not target.exists_at(time):
		return {"vertices": empty, "problem": "it is not there at this time",
			"title": target.title}
	if section.part < 0 or section.part >= target.rings.size():
		return {"vertices": empty, "problem": "part %d of it is gone" % (section.part + 1),
			"title": target.title}

	var ring: PackedVector2Array = target.rings[section.part]
	var low := clampi(mini(section.from_index, section.to_index), 0, ring.size() - 1)
	var high := clampi(maxi(section.from_index, section.to_index), 0, ring.size() - 1)
	var run := ring.slice(low, high + 1)
	if run.size() < MINIMUM_VERTICES:
		return {"vertices": empty,
			"problem": "it names fewer than %d vertices" % MINIMUM_VERTICES,
			"title": target.title}
	if section.reversed:
		run.reverse()

	return {
		"vertices": Feature.apply_basis(run, Feature.world_basis(root, target, time)),
		"problem": "",
		"title": target.title,
	}


# Give a topology the rings its sections resolve to at that time.
#
# One ring per section that resolved, so the two ends of neighbouring sections
# are not joined by a segment that no feature drew: a line topology is the
# sections it names, not a shape closed around them.
#
# The runs come back in world coordinates and are put into the topology's own
# frame, because that is the frame everything else reads a feature's rings in.
# The rotation cancels out where it is drawn again, so a topology has no motion
# of its own: it goes where the features under it go.
static func rebuild(root: Feature, node: Feature, time: float) -> void:
	var into_local := Feature.world_basis(root, node, time).transposed()
	var rings: Array[PackedVector2Array] = []
	for entry in resolve(root, node, time):
		var vertices: PackedVector2Array = entry["vertices"]
		if not vertices.is_empty():
			rings.append(Feature.apply_basis(vertices, into_local))
	node.rings = rings
	node.rebuild_triangles()


# Resolve every topology in the tree at that time. Called before the geometry is
# collected and whenever the current time moves, since both change where the
# features a topology runs along are.
static func rebuild_all(root: Feature, time: float) -> void:
	if root == null:
		return
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		stack.append_array(node.children)
		if not node.is_group and node.geometry_kind == Feature.GeometryKind.TOPOLOGY:
			rebuild(root, node, time)


# Whether anything in the tree is a topology. Moving the current time is a cheap
# redraw without one and a full rebuild with one, so it is worth asking.
static func holds_any(root: Feature) -> bool:
	if root == null:
		return false
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if not node.is_group and node.geometry_kind == Feature.GeometryKind.TOPOLOGY:
			return true
		stack.append_array(node.children)
	return false


# Why the feature cannot become a section of the topology, or an empty string
# when it can. This is what the Topology tool refuses a click with.
static func section_problem(node: Feature, target: Feature) -> String:
	if target == null:
		return "Click a feature to add it to the topology."
	if target == node:
		return "A topology cannot run along itself."
	if target.is_group:
		return "%s is a group, which has no vertices of its own." % target.title
	if target.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return "%s is a topology, and one cannot run along another." % target.title
	if not target.has_geometry():
		return "%s has no vertices to run along." % target.title
	return ""
