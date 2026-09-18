class_name Hotspot

# A hotspot: a plume fixed in the mantle, and the track it burns into the plate
# drifting over it. See Docs/Editing.md#hotspots.
#
# The world frame is the mantle frame here: the hotspot sits still in it, and
# the plate is whatever feature the hotspot names. A plate point that was over
# the hotspot at age t has since been carried along with the plate, so at the
# current time T it is at B(T) * B(t)^T * H, where B is the plate's rotation
# into the world and H the hotspot. Those points, oldest first, are the track.
#
# Like a topology, the track depends on another feature and on the time, so
# Application rebuilds it whenever the tree, the current time or the timeline's
# Skip changes. The track has a sample at every multiple of the hotspot's own
# time step, or of the Skip when it carries none; see step_of().

# The radius of the ring marking the hotspot itself, in degrees, and how many
# segments it has.
const MARK_DEGREES := 1.0
const MARK_SEGMENTS := 24

# The finest skip a track is sampled at. The timeline's Skip box goes much
# lower, and a track at that would never finish.
const MIN_SKIP := 0.1

# The coarsest step a feature may carry of its own. Nothing samples over a
# range longer than Document.MAX_TIME anyway.
const MAX_STEP := 1000.0

# How close two ages are to count as the same.
const AGE_EPSILON := 1e-6


# The ages a range is sampled at for the timeline's skip, oldest first: every
# multiple of the skip older than the time and no older than the oldest age,
# the oldest age in front when it is not one of them, and the time itself last.
# The time is not on the grid, so it is always there.
static func sample_ages(skip: float, oldest: float, time: float) -> PackedFloat64Array:
	var step := maxf(skip, MIN_SKIP)
	var ages := PackedFloat64Array()
	if oldest > time + AGE_EPSILON:
		var k := floorf((oldest + AGE_EPSILON) / step)
		if oldest - k * step > AGE_EPSILON:
			ages.append(oldest)
		while k * step > time + AGE_EPSILON:
			ages.append(k * step)
			k -= 1.0
	ages.append(time)
	return ages


# How far apart in time the feature is sampled: the step it carries, or the
# fallback when it carries none. The fallback is the timeline's Skip, which is
# a setting of the machine, so a feature with a step of its own draws the same
# wherever the file is opened. sample_ages() floors whichever it gets at
# MIN_SKIP. See Docs/Time.md#the-time-control.
static func step_of(node: Feature, skip: float) -> float:
	return node.time_step if node.time_step > 0.0 else skip


# Whether the hotspot has been put somewhere. A new one waits for the click of
# the Draw tool that places it.
static func placed(node: Feature) -> bool:
	return node.hotspot != Feature.NO_HOTSPOT


# The track at that time, in world coordinates, oldest first: one point for
# each of sample_ages() over the hotspot's own time range, leaving out the ages
# the plate is not there. The skip is what step_of() uses when the hotspot
# carries no step of its own. Empty without a plate or a place.
#
# ponytail: one world_basis per sample, so a 0.1 My skip over 2000 My is 20000
# of them on every time change; cache the plate's bases if that ever shows.
static func track(root: Feature, node: Feature, time: float, skip: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var plate := root.get_node_by_uuid(node.plate_uuid) if root != null else null
	if plate == null or not placed(node):
		return points
	var now := Feature.world_basis(root, plate, time)
	for t in sample_ages(step_of(node, skip), node.time_range.y, time):
		if plate.exists_at(t):
			var carried := now * Feature.world_basis(root, plate, t).transposed()
			points.append(Feature.apply_basis(PackedVector2Array([node.hotspot]), carried)[0])
	return points


# Give a hotspot its rings at that time, in its own frame: the mark around the
# hotspot and, when there are at least two samples, the track. One not placed
# yet has none.
static func rebuild(root: Feature, node: Feature, time: float, skip: float) -> void:
	node.geometry_kind = Feature.GeometryKind.POLYLINE
	if not placed(node):
		node.rings.clear()
		node.rebuild_triangles()
		return
	var into_local := Feature.world_basis(root, node, time).transposed()
	var rings: Array[PackedVector2Array] = [Feature.apply_basis(
		Circle.vertices(node.hotspot, MARK_DEGREES, MARK_SEGMENTS, false), into_local)]
	var points := track(root, node, time, skip)
	if points.size() >= 2:
		rings.append(Feature.apply_basis(points, into_local))
	node.rings = rings
	node.rebuild_triangles()


# The samples of the track, in the hotspot's own frame, each of which is drawn
# with a dot: the second ring rebuild() gives it. Empty for any other feature.
static func samples(node: Feature) -> PackedVector2Array:
	if not node.is_hotspot() or node.rings.size() < 2:
		return PackedVector2Array()
	return node.rings[1]


# Rebuild every hotspot in the tree at that time and skip, beside
# Topology.rebuild_all(). The skip is the timeline's,
# Config.get_skip_increment(); a hotspot carrying a step of its own ignores it.
static func rebuild_all(root: Feature, time: float, skip: float) -> void:
	for node in _hotspots(root):
		rebuild(root, node, time, skip)


# Whether anything in the tree is a hotspot, which makes a time move a rebuild.
static func holds_any(root: Feature) -> bool:
	return not _hotspots(root).is_empty()


static func _hotspots(root: Feature) -> Array[Feature]:
	var found: Array[Feature] = []
	if root == null:
		return found
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		stack.append_array(node.children)
		if node.is_hotspot():
			found.append(node)
	return found


# Why the feature cannot be the plate of the hotspot, or an empty string when it
# can. An empty uuid is no plate, which is always fine.
static func plate_problem(root: Feature, node: Feature, plate_uuid: String) -> String:
	if plate_uuid.is_empty():
		return ""
	var plate := root.get_node_by_uuid(plate_uuid) if root != null else null
	if plate == null:
		return "There is no feature with uuid %s to be the plate." % plate_uuid
	if plate == node:
		return "A hotspot cannot burn through itself."
	if plate.is_group or not plate.has_own_vertices():
		return "%s holds no vertices of its own, so it cannot be the plate." % plate.title
	return ""
