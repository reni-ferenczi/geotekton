class_name Ridge

# A mid-ocean ridge: a midway topology whose two sections are the two sides of
# the cut a split left, one on each half. See Docs/Editing.md#the-ridge.
#
# GPlates reconstructs a ridge at the half stage rotation of the two plates.
# The same holds here vertex by vertex: each pair of section vertices is taken
# back into its own feature's frame, where the two lay on each other when the
# plate was split, and carried out again by the rotation halfway between the
# two features' rotations. For two features that have not moved apart, that is
# the point midway between the pair.


# The ridge at that time, in world coordinates: one vertex for each pair of
# section vertices. Empty when the topology does not have two sections that
# resolve to the same number of vertices; Topology.resolve() says why.
static func ring_at(root: Feature, node: Feature, time: float) -> PackedVector2Array:
	var ring := PackedVector2Array()
	var resolved := Topology.resolve(root, node, time)
	if resolved.size() != 2:
		return ring
	for entry in resolved:
		if not str(entry["problem"]).is_empty():
			return ring
	var first: PackedVector2Array = resolved[0]["local"]
	var second: PackedVector2Array = resolved[1]["local"]
	var half := Basis(Quaternion(resolved[0]["basis"] as Basis).slerp(
		Quaternion(resolved[1]["basis"] as Basis), 0.5))
	for i in first.size():
		var middle := Feature._latlon_to_xyz_s(first[i]) + Feature._latlon_to_xyz_s(second[i])
		ring.append(Feature._xyz_to_latlon_s(half * middle.normalized()))
	return ring
