class_name Crust

# The oceanic crust a ridge leaves on one side: bands of sea floor between
# isochrons, and the isochrons and flowlines drawn as lines. See
# Docs/Editing.md#the-crust.
#
# An isochron is where the ridge was at some age, carried with the half since:
# at the current time T the ridge of age a is at B(T) * B(a)^T * R(a), where B
# is the half's rotation into the world and R(a) the ridge at a. The oldest
# isochron, at the split age, is the half's side of the cut, and the youngest,
# at T, is the ridge itself. The ages between are the multiples of the
# timeline's Skip, as for a hotspot track.
#
# A flowline follows one vertex of the cut across every isochron, from the
# continent to the ridge.
#
# Like a hotspot, a crust depends on other features, on the time and on the
# Skip, so Application rebuilds it whenever any of them changes. It is a
# topology without sections: Topology.holds_any() already makes a time move a
# rebuild.


# The isochrons of the crust at that time, in world coordinates, oldest first.
# Empty when the half or the ridge is gone or the ridge cannot be resolved at
# one of the ages.
static func isochrons(root: Feature, node: Feature, time: float,
		skip: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var half := root.get_node_by_uuid(node.crust_half) if root != null else null
	var ridge := root.get_node_by_uuid(node.crust_ridge) if root != null else null
	if half == null or ridge == null or not ridge.midway:
		return result
	var now := Feature.world_basis(root, half, time)
	for age in Hotspot.sample_ages(skip, float(node.time_range.y), time):
		var ring := Ridge.ring_at(root, ridge, age)
		if ring.is_empty():
			result.clear()
			return result
		result.append(Feature.apply_basis(ring,
			now * Feature.world_basis(root, half, age).transposed()))
	return result


# Give a crust its rings at that time, in its own frame: one closed ring per
# band, the older isochron forwards and the younger one back, or for the lines
# feature every isochron and then one flowline per cut vertex.
static func rebuild(root: Feature, node: Feature, time: float, skip: float) -> void:
	var lines := isochrons(root, node, time, skip)
	var rings: Array[PackedVector2Array] = []
	if node.crust_lines:
		rings.append_array(lines)
		if lines.size() >= 2:
			for i in mini(node.crust_edge, lines[0].size()):
				var flowline := PackedVector2Array()
				for isochron in lines:
					flowline.append(isochron[i])
				rings.append(flowline)
	else:
		for k in lines.size() - 1:
			var band := lines[k].duplicate()
			var younger := lines[k + 1].duplicate()
			younger.reverse()
			band.append_array(younger)
			rings.append(band)
	var into_local := Feature.world_basis(root, node, time).transposed()
	node.rings.assign(rings.map(func(ring: PackedVector2Array) -> PackedVector2Array:
		return Feature.apply_basis(ring, into_local)))
	node.rebuild_triangles()


# How many bands the crust has, read off the rings rebuild() last gave it.
static func chunks(node: Feature) -> int:
	if not node.crust_lines:
		return node.rings.size()
	# The isochrons, less the flowlines, are one more than the bands.
	return maxi(0, node.rings.size() - node.crust_edge - 1)


# What the Properties panel says about a crust.
static func describe(root: Feature, node: Feature) -> String:
	var half := root.get_node_by_uuid(node.crust_half) if root != null else null
	var title := half.title if half != null else "a missing half"
	var count := chunks(node)
	return "%s of %s, %d chunk%s" % ["Crust lines" if node.crust_lines else "Crust",
		title, count, "" if count == 1 else "s"]


# Rebuild every crust in the tree at that time and skip, after the topologies,
# since a crust reads the ridge. The skip is the timeline's.
static func rebuild_all(root: Feature, time: float, skip: float) -> void:
	if root == null:
		return
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		stack.append_array(node.children)
		if node.is_crust():
			rebuild(root, node, time, skip)
