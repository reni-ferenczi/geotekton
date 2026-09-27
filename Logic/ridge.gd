class_name Ridge

# A mid-ocean ridge: a midway topology between the two sides of the cut a split
# left. See Docs/Editing.md#the-ridge.
#
# Each side is a list of sections in the order the cut runs, marked by
# TopologySection.side. A coast piece is a run of vertices of a feature that
# has that coast, a continent or an island; a gap piece, where the cut crosses
# sea, is points of its own riding with the half of the plate on that side.
# The two sides are the same line when the plate is split, so they have the
# same number of vertices, and the ridge pairs them up one by one.
#
# GPlates reconstructs a ridge at the half stage rotation of the two plates.
# The same holds here vertex by vertex: each pair of vertices is taken back into
# its own feature's frame, where the two lay on each other when the plate was
# split, and carried out again by the rotation halfway between the two
# features' rotations. For two features that have not moved apart, that is the
# point midway between the pair.
#
# Where three ridges meet at a triple junction, each end there is its own pair's
# half stage point, and once the three plates drift apart those are three
# points, leaving a wedge of bare sea floor between the crusts. So every end
# that meets others (Feature.ridge_junctions) is put at the mean of all their
# ends: the ridges meet in one point, and the crusts beside them, which are
# built from the ridge at every age, meet along the path that point takes. A
# ridge younger than the time is left out, since it was not there yet. As long
# as the plates have not drifted apart the ends lie on each other and nothing
# moves.


# The ridge at that time, in world coordinates: one vertex for each pair of
# vertices of the two sides, its ends put where they meet other ridges. Empty
# when the sides cannot be resolved or differ in length; Topology.resolve()
# says why.
static func ring_at(root: Feature, node: Feature, time: float) -> PackedVector2Array:
	var ring := _pairs_at(root, node, time)
	if ring.is_empty() or node.ridge_junctions.is_empty():
		return ring
	for end in 2:
		var id := node.ridge_junctions[end]
		if id.is_empty():
			continue
		var sum := Vector3.ZERO
		for other in _meeting(root, id):
			if other != node and time > other.time_range.y:
				continue
			var line := ring if other == node else _pairs_at(root, other, time)
			if not line.is_empty():
				sum += Feature._latlon_to_xyz_s(line[other.ridge_junctions.find(id) * (line.size() - 1)])
		if sum.length() > 1e-9:
			ring[end * (ring.size() - 1)] = Feature._xyz_to_latlon_s(sum.normalized())
	return ring


# Every ridge with an end at that junction.
static func _meeting(root: Feature, id: String) -> Array[Feature]:
	var found: Array[Feature] = []
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		stack.append_array(node.children)
		if node.midway and id in node.ridge_junctions:
			found.append(node)
	return found


# The ridge vertex by vertex, each the half stage point of its pair.
static func _pairs_at(root: Feature, node: Feature, time: float) -> PackedVector2Array:
	var ring := PackedVector2Array()
	var sides := [[], []]
	for entry: Dictionary in Topology.resolve(root, node, time):
		if not str(entry["problem"]).is_empty():
			return ring
		var turn := Quaternion(entry["basis"] as Basis)
		for vertex in entry["local"] as PackedVector2Array:
			sides[entry["side"]].append([Feature._latlon_to_xyz_s(vertex), turn])
	if sides[0].size() != sides[1].size():
		return ring
	for i in sides[0].size():
		var a: Array = sides[0][i]
		var b: Array = sides[1][i]
		var half := Basis((a[1] as Quaternion).slerp(b[1] as Quaternion, 0.5))
		ring.append(Feature._xyz_to_latlon_s(half * ((a[0] as Vector3) + (b[0] as Vector3)).normalized()))
	return ring


# One side of the ridge at that time, in world coordinates, in the order the cut
# runs. Empty when the sides cannot be resolved.
static func side_at(root: Feature, node: Feature, time: float, side: int) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for entry: Dictionary in Topology.resolve(root, node, time):
		if not str(entry["problem"]).is_empty():
			return PackedVector2Array()
		if entry["side"] == side:
			ring.append_array(entry["vertices"])
	return ring


# Which side of the ridge runs along that feature: the side one of whose
# sections names it, or -1 when neither does.
static func side_of(node: Feature, feature: Feature) -> int:
	for section in node.sections:
		if section.feature_uuid == feature.uuid:
			return section.side
	return -1
