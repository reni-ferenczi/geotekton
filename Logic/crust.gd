class_name Crust

# The oceanic crust a ridge leaves on one side: bands of sea floor between
# isochrons, with the isochrons and the flowlines drawn as lines over them. One
# feature holds both. See Docs/Editing.md#the-crust.
#
# An isochron is where the ridge was at some age, carried with the half since:
# at the current time T the ridge of age a is at B(T) * B(a)^T * R(a), where B
# is the half's rotation into the world and R(a) the ridge at a. The oldest
# isochron, at the split age, is the half's side of the cut, and the youngest,
# at T, is the ridge itself. The ages between are the multiples of the crust's
# own time step, or of the timeline's Skip when it carries none, as for a
# hotspot track; see Hotspot.step_of().
#
# A flowline follows one vertex of the cut across every isochron, from the
# continent to the ridge.
#
# Like a hotspot, a crust depends on other features, on the time and on the
# step, so Application rebuilds it whenever any of them changes. It is a
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
	for age in Hotspot.sample_ages(Hotspot.step_of(node, skip), float(node.time_range.y), time):
		var ring := Ridge.ring_at(root, ridge, age)
		if ring.is_empty():
			result.clear()
			return result
		result.append(Feature.apply_basis(ring,
			now * Feature.world_basis(root, half, age).transposed()))
	return result


# The isochrons and the flowlines of the crust at that time, in world
# coordinates: every isochron, then one flowline per cut vertex. Kept apart from
# bands() so a later ticket can hide or recolor the lines on their own.
static func flowlines(node: Feature,
		lines: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var rings: Array[PackedVector2Array] = []
	rings.append_array(lines)
	if lines.size() < 2:
		return rings
	for i in mini(node.crust_edge, lines[0].size()):
		var flowline := PackedVector2Array()
		for isochron in lines:
			flowline.append(isochron[i])
		rings.append(flowline)
	return rings


# The bands of sea floor between the isochrons, in world coordinates: one closed
# ring each, the older isochron forwards and the younger one back.
static func bands(lines: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var rings: Array[PackedVector2Array] = []
	for k in lines.size() - 1:
		var band := lines[k].duplicate()
		var younger := lines[k + 1].duplicate()
		younger.reverse()
		band.append_array(younger)
		rings.append(band)
	return rings


# How old the crust in each band is at that time, oldest band first: the age of
# the older of its two isochrons, counted from the time rather than from the
# present, so the crust beside the ridge is new whenever it is looked at. The
# ages come from the same sampling the isochrons do, so the k-th is the k-th
# band's; `count` is how many bands there are.
static func band_ages(node: Feature, time: float, skip: float,
		count: int) -> PackedFloat64Array:
	var sampled := Hotspot.sample_ages(Hotspot.step_of(node, skip),
		float(node.time_range.y), time)
	var ages := PackedFloat64Array()
	for k in mini(count, sampled.size()):
		ages.append(sampled[k] - time)
	return ages


# Give a crust its rings at that time, in its own frame: the bands as its rings,
# which are what it fills, measures and hands to Copy Shape, and the isochrons
# and the flowlines as its line rings, which Planet.collect_geometry() draws
# over them in the crust lines color. The age of the crust in each band goes
# beside them, for the ramp that colors the bands.
static func rebuild(root: Feature, node: Feature, time: float, skip: float) -> void:
	var lines := isochrons(root, node, time, skip)
	var into_local := Feature.world_basis(root, node, time).transposed()
	var localize := func(rings: Array[PackedVector2Array]) -> Array:
		return rings.map(func(ring: PackedVector2Array) -> PackedVector2Array:
			return Feature.apply_basis(ring, into_local))
	node.rings.assign(localize.call(bands(lines)))
	node.crust_line_rings.assign(localize.call(flowlines(node, lines)))
	node.band_ages = band_ages(node, time, skip, node.rings.size())
	node.rebuild_triangles()


# How many bands the crust has, read off the rings rebuild() last gave it.
static func chunks(node: Feature) -> int:
	return node.rings.size()


# What the Properties panel says about a crust.
static func describe(root: Feature, node: Feature) -> String:
	var half := root.get_node_by_uuid(node.crust_half) if root != null else null
	var title := half.title if half != null else "a missing half"
	var count := chunks(node)
	return "Crust of %s, %d chunk%s" % [title, count, "" if count == 1 else "s"]


# Rebuild every crust in the tree at that time and skip, after the topologies,
# since a crust reads the ridge. The skip is the timeline's; a crust carrying a
# step of its own ignores it.
static func rebuild_all(root: Feature, time: float, skip: float) -> void:
	if root == null:
		return
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		stack.append_array(node.children)
		if node.is_crust():
			rebuild(root, node, time, skip)
