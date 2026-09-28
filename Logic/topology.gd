class_name Topology

# Resolving a topology: turning its list of sections into the vertices it
# draws at one time. The topologies are the ridges and crusts the Split tool
# generates; none is built by hand (GP-0147). See Docs/Editing.md#the-ridge.
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
#   local:    the run in that feature's own frame
#   basis:    the rotation carrying it into the world at that time
#
# A section is never dropped: one whose feature has been deleted comes back with
# the reason, so the panel can show it as broken and the file can keep it. That
# is what makes a topology survive a feature going away and coming back through
# an undo.
static func resolve(root: Feature, node: Feature, time: float) -> Array:
	var resolved: Array = []
	for section in node.sections:
		resolved.append(_resolve_section(root, node, section, time))
	if node.midway:
		_check_midway(node, resolved)
	return resolved


# A midway topology pairs the vertices of its two sides, one after the other,
# so each side needs a section and both the same number of vertices. What does
# not fit is reported on the last section of the second side.
static func _check_midway(node: Feature, resolved: Array) -> void:
	var counts := [0, 0]
	var last := -1
	for index in resolved.size():
		var side: int = node.sections[index].side
		counts[side] += (resolved[index]["vertices"] as PackedVector2Array).size()
		if side == 1:
			last = index
	if resolved.is_empty() or resolved.any(func(entry: Dictionary) -> bool:
			return not str(entry["problem"]).is_empty()):
		return
	if last < 0:
		resolved[-1]["problem"] = "a midway topology needs a second side"
	elif counts[0] != counts[1]:
		resolved[last]["problem"] = "its side has %d vertices and the first side %d" \
			% [counts[1], counts[0]]
	else:
		return
	for entry: Dictionary in resolved:
		entry["vertices"] = PackedVector2Array()


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
	# A ridge is the one topology a section may run along, and only in a
	# topology that is not midway itself; see rebuild_all().
	if target.geometry_kind == Feature.GeometryKind.TOPOLOGY \
			and (not target.midway or node.midway):
		return {"vertices": empty, "problem": "a topology cannot run along another one",
			"title": target.title}
	if not target.exists_at(time):
		return {"vertices": empty, "problem": "it is not there at this time",
			"title": target.title}
	var run := section.points.duplicate()
	if not section.is_gap():
		if section.part < 0 or section.part >= target.rings.size():
			return {"vertices": empty, "problem": "part %d of it is gone" % (section.part + 1),
				"title": target.title}
		var ring: PackedVector2Array = target.rings[section.part]
		var low := clampi(mini(section.from_index, section.to_index), 0, ring.size() - 1)
		var high := clampi(maxi(section.from_index, section.to_index), 0, ring.size() - 1)
		run = ring.slice(low, high + 1)
	# A piece of a ridge side may be a single vertex; the side as a whole is
	# the line.
	if run.size() < (1 if node.midway else MINIMUM_VERTICES):
		return {"vertices": empty,
			"problem": "it names fewer than %d vertices" % MINIMUM_VERTICES,
			"title": target.title}
	if section.reversed:
		run.reverse()

	var basis := Feature.world_basis(root, target, time)
	return {
		"vertices": Feature.apply_basis(run, basis),
		"problem": "",
		"title": target.title,
		"local": run,
		"basis": basis,
		"side": section.side,
	}


# Give a ridge the one ring between its two sides at that time; see
# Ridge.ring_at(). Ridges and crusts are the only topologies (GP-0147), and a
# crust is built by Crust.rebuild_all().
#
# The ring comes back in world coordinates and is put into the ridge's own
# frame, because that is the frame everything else reads a feature's rings in.
# The rotation cancels out where it is drawn again, so a ridge has no motion of
# its own: it goes where the features under it go.
static func rebuild(root: Feature, node: Feature, time: float) -> void:
	var into_local := Feature.world_basis(root, node, time).transposed()
	var rings: Array[PackedVector2Array] = []
	if node.midway:
		var ring := Ridge.ring_at(root, node, time)
		if not ring.is_empty():
			rings.append(Feature.apply_basis(ring, into_local))
	node.rings = rings
	node.rebuild_triangles()


# Resolve every ridge in the tree at that time. Called before the geometry is
# collected and whenever the current time moves, since both change where the
# features a ridge runs between are.
static func rebuild_all(root: Feature, time: float) -> void:
	if root == null:
		return
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		stack.append_array(node.children)
		if not node.is_group and node.midway:
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

