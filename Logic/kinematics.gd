class_name Kinematics

# What the kinematics panel draws: where the middle of a feature has been over
# time, and how fast it is turning between its keyframes. Nothing here touches
# the scene, so a graph can be worked out headless and checked without a window.
# See Docs/Kinematics.md.
#
# Time is an age in millions of years before present, so a span runs from the
# oldest time to the youngest and a rate is per million years. Distances are in
# the units the planet radius is given in, kilometres everywhere in the
# application; see Config.get_planet_radius().


# The middle of a feature's vertices, as a point on the unit sphere in the
# feature's own frame. Every vertex counts once, so this is the middle of the
# outline rather than of the area it covers; the two are close for the shapes
# anyone draws, and this one is defined for a polyline and a multipoint as well.
#
# Vertices that cancel each other out have no middle: a marker at each pole is
# the plain case. The first vertex stands in for it, so a feature always has
# somewhere to follow rather than a hole in the graph.
static func centroid(feature: Feature) -> Vector3:
	var total := Vector3.ZERO
	var first := Vector3.ZERO
	for ring in feature.rings:
		for vertex in ring:
			var point := Feature._latlon_to_xyz_s(vertex)
			if first == Vector3.ZERO:
				first = point
			total += point
	if total.length() < 1e-6:
		return first
	return total.normalized()


# Whether the panel has a path to draw for a node. A group has no geometry of
# its own, and a line topology borrows every vertex of it from the features its
# sections run along, so neither has a middle that its own rotation carries.
static func can_graph(node: Feature) -> bool:
	return node != null and not node.is_group and node.has_own_vertices()


# Where the middle of a feature is at a time, as a latitude and a longitude in
# degrees, carried through the rotation its keyframes give it.
static func position_at(root: Feature, node: Feature, time: float) -> Vector2:
	return Feature._xyz_to_latlon_s(Feature.world_basis(root, node, time) * centroid(node))


# Where the middle is at each of a run of times evenly spread over a span, from
# the oldest to the youngest, which is left to right on the graph. One
# dictionary per sample: `time`, `lat` and `lon`. Empty for a node with no path.
static func path(root: Feature, node: Feature, oldest: float, youngest: float,
		samples: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not can_graph(node) or samples < 2 or oldest <= youngest:
		return result
	var middle := centroid(node)
	for i in samples:
		var time := lerpf(oldest, youngest, float(i) / float(samples - 1))
		var point := Feature.world_basis(root, node, time) * middle
		var latlon := Feature._xyz_to_latlon_s(point)
		result.append({"time": time, "lat": latlon.x, "lon": latlon.y})
	return result


# Every time the motion of a node can change, sorted youngest first: its
# keyframe times, and while it rides on another feature the ends of that span
# and every time the parent's own motion changes inside it. Nothing above it in
# the tree moves it.
static func motion_times(root: Feature, node: Feature) -> PackedFloat64Array:
	var times := PackedFloat64Array()
	if node == null:
		return times
	var nodes := Coupling.index(root) if root != null and not node.couplings.is_empty() else {}
	_add_motion_times(node, nodes, [node], times)
	times.sort()
	return times


static func _add_motion_times(node: Feature, nodes: Dictionary, visiting: Array,
		times: PackedFloat64Array) -> void:
	for keyframe in node.keyframes:
		_add_time(times, keyframe.time)
	for span in node.couplings:
		_add_time(times, span.from)
		_add_time(times, span.to)
		var parent: Feature = nodes.get(span.parent)
		if parent == null or visiting.has(parent):
			continue
		var inside := PackedFloat64Array()
		visiting.append(parent)
		_add_motion_times(parent, nodes, visiting, inside)
		visiting.pop_back()
		for time in inside:
			if span.holds(time):
				_add_time(times, time)


static func _add_time(times: PackedFloat64Array, time: float) -> void:
	for existing in times:
		if is_equal_approx(existing, time):
			return
	times.append(time)


# How fast the node turns between each pair of those times. One dictionary per
# span: `from`, the younger end, `to`, the older one, `degrees_per_my` and
# `km_per_my`.
#
# The angle is the one turn that carries where the node stands at one end to
# where it stands at the other, so the rate is what the motion averages over the
# span rather than anything instantaneous. It has no direction: a turn back the
# way it came is as fast as the turn out. The distance is what a point a quarter
# turn from the axis covers, which is the fastest any part of the feature moves.
#
# A node with fewer than two times to itself has no span and no rate at all.
static func segments(root: Feature, node: Feature, radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var times := motion_times(root, node)
	for i in range(1, times.size()):
		var span := times[i] - times[i - 1]
		if span <= 0.0:
			continue
		var from_rotation := Quaternion(Feature.world_basis(root, node, times[i - 1]))
		var to_rotation := Quaternion(Feature.world_basis(root, node, times[i]))
		var degrees := rad_to_deg(from_rotation.angle_to(to_rotation)) / span
		result.append({
			"from": times[i - 1],
			"to": times[i],
			"degrees_per_my": degrees,
			"km_per_my": deg_to_rad(degrees) * radius,
		})
	return result


# How fast the node is turning at a time: the span the time falls in, both ends
# counted as inside, and nothing at all outside every span. A time where two
# spans meet belongs to the younger of the two, so one answer comes back rather
# than two.
static func rate_at(segments_: Array[Dictionary], time: float) -> Dictionary:
	for segment in segments_:
		if time >= segment["from"] and time <= segment["to"]:
			return {
				"degrees_per_my": segment["degrees_per_my"],
				"km_per_my": segment["km_per_my"],
			}
	return {"degrees_per_my": 0.0, "km_per_my": 0.0}


# The fastest of the spans, which is what the rate graph is drawn against. Zero
# when the node does not move, and never negative.
static func peak_rate(segments_: Array[Dictionary]) -> float:
	var peak := 0.0
	for segment in segments_:
		peak = maxf(peak, float(segment["degrees_per_my"]))
	return peak
