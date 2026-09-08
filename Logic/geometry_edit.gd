class_name GeometryEdit

# Edits to the vertices of one part of a feature, as functions that take a ring
# and give back another. Nothing here touches a Feature or a Document: the
# Vertex tool and the Properties panel both work out what the ring should become
# here, and Document then applies it and records the undo version.
#
# A ring is a run of (latitude, longitude) vertices in degrees, in the frame of
# the feature itself. What a ring means follows the feature's geometry kind; see
# Feature.GeometryKind.


### Editing one ring


# The ring with a vertex put in before index. An index of the ring's size
# appends. The ring is left alone and a copy comes back, so a caller can compare
# the two or throw the result away.
static func inserted(ring: PackedVector2Array, index: int, vertex: Vector2) -> PackedVector2Array:
	var result := ring.duplicate()
	result.insert(clampi(index, 0, result.size()), vertex)
	return result


# The ring with one vertex moved somewhere else.
static func moved(ring: PackedVector2Array, index: int, vertex: Vector2) -> PackedVector2Array:
	var result := ring.duplicate()
	if index >= 0 and index < result.size():
		result[index] = vertex
	return result


# The ring with one vertex taken out.
static func removed(ring: PackedVector2Array, index: int) -> PackedVector2Array:
	var result := ring.duplicate()
	if index >= 0 and index < result.size():
		result.remove_at(index)
	return result


# Why the vertex cannot be taken out, or an empty string when it can. A part
# that would fall under the minimum its kind needs is refused rather than
# quietly taking the whole shape with it: on the globe the Vertex tool would
# otherwise make a triangle disappear under a single key press.
static func removal_problem(ring: PackedVector2Array, index: int,
		kind: Feature.GeometryKind) -> String:
	if index < 0 or index >= ring.size():
		return "There is no vertex %d." % index
	var minimum := int(Feature.MINIMUM_VERTICES[kind])
	if ring.size() - 1 < minimum:
		return "A %s needs %d vertices; delete the feature instead." % [
			Feature.KIND_NAMES[kind], minimum]
	return ""


### Splitting


# Why the polyline cannot be split at that vertex, or an empty string when it
# can. Both halves keep the vertex it is split at, so an end vertex would leave
# one half with a single point.
static func polyline_split_problem(ring: PackedVector2Array, index: int) -> String:
	if index < 0 or index >= ring.size():
		return "There is no vertex %d." % index
	if index == 0 or index == ring.size() - 1:
		return "A polyline splits at a vertex between its ends, not at an end."
	return ""


# The two polylines the ring becomes when it is split at index. Both hold that
# vertex, and between them they hold every other vertex once.
static func split_polyline(ring: PackedVector2Array, index: int) -> Array[PackedVector2Array]:
	var halves: Array[PackedVector2Array] = []
	halves.append(ring.slice(0, index + 1))
	halves.append(ring.slice(index))
	return halves


# Why the polygon cannot be split between those two vertices, or an empty string
# when it can. The cut runs from one to the other, so both halves keep both of
# them and neither may be left under three vertices; that rules out the same
# vertex twice and two that are already neighbours.
#
# The cut also has to lie inside the shape. On a concave ring a line between two
# vertices can run outside it, across the mouth of a dent, and the two rings it
# would leave overlap each other instead of covering the original.
static func polygon_split_problem(ring: PackedVector2Array, a: int, b: int) -> String:
	var size := ring.size()
	if a < 0 or a >= size or b < 0 or b >= size:
		return "There is no such vertex."
	if a == b:
		return "A polygon splits between two different vertices."
	var low := mini(a, b)
	var high := maxi(a, b)
	if high - low < 2 or size - high + low < 2:
		return "The two vertices are next to each other, so one half would be a line."
	if not is_diagonal(ring, low, high):
		return "The cut between those two vertices runs outside the shape."
	return ""


# Whether the straight line between two vertices stays inside the ring.
#
# Two things can put it outside. It can cross an edge, which is checked against
# every edge that does not already share one of the two vertices with it, since
# those meet it at an end rather than crossing it. Or it can cross nothing and
# still lie outside, which is what a line across the mouth of a dent does, so
# its middle has to be inside the ring as well.
static func is_diagonal(ring: PackedVector2Array, a: int, b: int) -> bool:
	var size := ring.size()
	if size < 3:
		return false
	var from := ring[a]
	var to := ring[b]
	for i in range(size):
		var j := (i + 1) % size
		if i == a or i == b or j == a or j == b:
			continue
		if Geometry2D.segment_intersects_segment(from, to, ring[i], ring[j]) != null:
			return false
	return Geometry2D.is_point_in_polygon((from + to) * 0.5, ring)


# The two polygons the ring becomes when it is cut from a to b. Both hold the
# two vertices the cut runs between; every other vertex goes to one half.
static func split_polygon(ring: PackedVector2Array, a: int, b: int) -> Array[PackedVector2Array]:
	var low := mini(a, b)
	var high := maxi(a, b)
	var halves: Array[PackedVector2Array] = []
	halves.append(ring.slice(low, high + 1))
	var second := ring.slice(high)
	second.append_array(ring.slice(0, low + 1))
	halves.append(second)
	return halves


### Picking
#
# Both of these work in whatever plane their points are given in. The Vertex
# tool passes window pixels, so that snapping and picking an edge happen at the
# distance the user sees rather than at a distance on the sphere, which the
# projection and the zoom would keep changing.


# The point nearest to target and no further from it than radius, or -1 when
# there is none. Ties go to the earlier point, so the result does not depend on
# the order two coincident points happen to be in.
static func nearest_point(points: PackedVector2Array, target: Vector2, radius: float) -> int:
	var best := -1
	var best_distance := radius
	for i in range(points.size()):
		var distance := points[i].distance_to(target)
		if distance <= best_distance:
			if best >= 0 and distance == best_distance:
				continue
			best = i
			best_distance = distance
	return best


# The segment of a run of points that target is nearest to: the index of the
# point the segment leaves, how far target is from it, and how far along it the
# nearest point sits, from 0 to 1. A closed run has the segment from the last
# point back to the first as well. Returns [-1, INF, 0.0] when there is no
# segment to be near.
static func nearest_segment(points: PackedVector2Array, target: Vector2,
		closed: bool) -> Array:
	var size := points.size()
	var last := size if closed else size - 1
	var best := [-1, INF, 0.0]
	for i in range(maxi(0, last)):
		var from := points[i]
		var to := points[(i + 1) % size]
		var along := from.direction_to(to)
		var length := from.distance_to(to)
		var t := 0.0 if length < 1e-9 else clampf((target - from).dot(along) / length, 0.0, 1.0)
		var distance := target.distance_to(from.lerp(to, t))
		if distance < best[1]:
			best = [i, distance, t]
	return best
