class_name Kinematics

# What the kinematics panel draws: where the middle of a feature has been over
# time, and how fast that middle moves between its keyframes. Nothing here touches
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
# keyframe times, and while it follows another feature the ends of that span
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
		# Both parents of a midway span, since either one turning moves the midpoint.
		for uuid in span.parents():
			var parent: Feature = nodes.get(uuid)
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


# How fast the middle of the node moves between each pair of those times. One
# dictionary per span: `from`, the younger end, `to`, the older one,
# `km_per_my`, the speed of the middle, and `bearing`, the compass direction it
# moves in, in degrees clockwise from north.
#
# The arithmetic is GPlates' calculate_velocity_vector_and_omega(): the stage
# rotation that carries the world rotation at the older end to the one at the
# younger end, its angle over the length of the span, and the velocity that
# gives the middle where it stands at the younger end. A spin about the middle
# moves the middle by nothing and reads zero. Between two keyframes the
# feature turns about one axis at one steady rate, so the speed holds over the
# whole span.
#
# A node with fewer than two times to itself has no span and no rate at all.
static func segments(root: Feature, node: Feature, radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var times := motion_times(root, node)
	if times.size() < 2:
		return result
	var middle := centroid(node)
	for i in range(1, times.size()):
		var span := times[i] - times[i - 1]
		if span <= 0.0:
			continue
		var younger := Feature.world_basis(root, node, times[i - 1])
		var older := Feature.world_basis(root, node, times[i])
		var point := younger * middle
		var velocity := stage_velocity(older, younger, span, point) * radius
		result.append({
			"from": times[i - 1],
			"to": times[i],
			"km_per_my": velocity.length(),
			"bearing": bearing(point, velocity),
		})
	return result


# The velocity of a point on the unit sphere under the stage rotation from one
# world rotation to another `span` My later, per My. The angle is worked out in
# doubles from the quaternion's parts: the angle between two nearby rotations
# taken from 32-bit quaternions moved in steps of about 0.03 cm/yr with one My
# between keyframes. Of q and -q the shorter turn is taken.
static func stage_velocity(older: Basis, younger: Basis, span: float, point: Vector3) -> Vector3:
	var a := Quaternion(younger)
	var b := Quaternion(older)
	var aw := a.w
	var ax := a.x
	var ay := a.y
	var az := a.z
	# The conjugate of b, which is its inverse.
	var bw := b.w
	var bx := -b.x
	var by := -b.y
	var bz := -b.z
	var w := aw * bw - ax * bx - ay * by - az * bz
	var x := aw * bx + ax * bw + ay * bz - az * by
	var y := aw * by - ax * bz + ay * bw + az * bx
	var z := aw * bz + ax * by - ay * bx + az * bw
	if w < 0.0:
		w = -w
		x = -x
		y = -y
		z = -z
	var sine := sqrt(x * x + y * y + z * z)
	if sine <= 0.0 or span <= 0.0:
		return Vector3.ZERO
	var angle := 2.0 * atan2(sine, w)
	var axis := Vector3(x / sine, y / sine, z / sine)
	return axis.cross(point) * (angle / span)


# The compass bearing of a velocity at a point on the unit sphere, in degrees
# clockwise from north. Zero at a pole, where north is every way, and for a
# point that does not move.
static func bearing(point: Vector3, velocity: Vector3) -> float:
	var east := Vector3(-point.z, 0.0, point.x)
	if east.length() < 1e-9 or velocity.length() <= 0.0:
		return 0.0
	east = east.normalized()
	var north := east.cross(point)
	return fposmod(rad_to_deg(atan2(velocity.dot(east), velocity.dot(north))), 360.0)


# How fast the node moves at a time: the span that brought it there, the way
# GPlates reads the motion from t + dt to t. A time where two spans meet
# belongs to the older of the two, so the readout at a keyframe gives the move
# that was just made there. Nothing at all outside every span, and nothing at
# the oldest time, where the feature has not moved yet.
static func rate_at(segments_: Array[Dictionary], time: float) -> Dictionary:
	for segment in segments_:
		if time >= segment["from"] and time < segment["to"]:
			return {"km_per_my": segment["km_per_my"], "bearing": segment["bearing"]}
	return {"km_per_my": 0.0, "bearing": 0.0}


# The fastest of the spans in km/My, which is what the rate graph is drawn
# against. Zero when the node does not move, and never negative.
static func peak_rate(segments_: Array[Dictionary]) -> float:
	var peak := 0.0
	for segment in segments_:
		peak = maxf(peak, float(segment["km_per_my"]))
	return peak
