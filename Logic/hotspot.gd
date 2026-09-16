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
# Application rebuilds it whenever the tree or the current time changes.

# The radius of the ring marking the hotspot itself, in degrees, and how many
# segments it has.
const MARK_DEGREES := 1.0
const MARK_SEGMENTS := 24

const MIN_STEP := 0.1
const MAX_STEP := 100.0


# The track at that time, in world coordinates, oldest first: one point for
# every step of the hotspot's own time range from its older end down to the
# time, the time itself included, leaving out the ages the plate is not there.
# Empty without a plate.
#
# ponytail: one world_basis per sample, so a 0.1 My step over 2000 My is 20000
# of them on every time change; cache the plate's bases if that ever shows.
static func track(root: Feature, node: Feature, time: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var plate := root.get_node_by_uuid(node.plate_uuid) if root != null else null
	if plate == null:
		return points
	var now := Feature.world_basis(root, plate, time)
	# Clamped, since a hand written file could hold a step that never ends.
	var step := clampf(node.track_step, MIN_STEP, MAX_STEP)
	var ages: Array[float] = []
	var age := float(node.time_range.y)
	while age > time + 1e-6:
		ages.append(age)
		age -= step
	ages.append(time)
	for t in ages:
		if plate.exists_at(t):
			var carried := now * Feature.world_basis(root, plate, t).transposed()
			points.append(Feature.apply_basis(PackedVector2Array([node.hotspot]), carried)[0])
	return points


# Give a hotspot its rings at that time, in its own frame: the mark around the
# hotspot and, when there are at least two samples, the track.
static func rebuild(root: Feature, node: Feature, time: float) -> void:
	var into_local := Feature.world_basis(root, node, time).transposed()
	var rings: Array[PackedVector2Array] = [Feature.apply_basis(
		Circle.vertices(node.hotspot, MARK_DEGREES, MARK_SEGMENTS, false), into_local)]
	var points := track(root, node, time)
	if points.size() >= 2:
		rings.append(Feature.apply_basis(points, into_local))
	node.geometry_kind = Feature.GeometryKind.POLYLINE
	node.rings = rings
	node.rebuild_triangles()


# Rebuild every hotspot in the tree at that time, beside Topology.rebuild_all().
static func rebuild_all(root: Feature, time: float) -> void:
	for node in _hotspots(root):
		rebuild(root, node, time)


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
