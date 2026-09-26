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


# The ridge at that time, in world coordinates: one vertex for each pair of
# vertices of the two sides. Empty when the sides cannot be resolved or differ
# in length; Topology.resolve() says why.
static func ring_at(root: Feature, node: Feature, time: float) -> PackedVector2Array:
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
