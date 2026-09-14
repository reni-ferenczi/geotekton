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
# when it can. The cut runs from a to b through the vertices of path, which may
# be none, so both halves keep a, b and the path and neither may be left under
# three vertices; that rules out the same vertex twice and two that are already
# neighbours.
#
# The cut also has to lie inside the shape. On a concave ring a line between two
# vertices can run outside it, across the mouth of a dent, and the two rings it
# would leave overlap each other instead of covering the original.
static func polygon_split_problem(ring: PackedVector2Array, a: int, b: int,
		path := PackedVector2Array()) -> String:
	var size := ring.size()
	if a < 0 or a >= size or b < 0 or b >= size:
		return "There is no such vertex."
	if a == b:
		return "A polygon splits between two different vertices."
	if _neighbours(size, a, b):
		return "The two vertices are next to each other, so one half would be a line."
	match cut_problem(ring, a, b, path):
		CutProblem.CROSSES:
			return "The cut crosses the edge of the shape between its ends."
		CutProblem.CROSSES_ITSELF:
			return "The cut crosses itself."
		CutProblem.OUTSIDE:
			return "The cut runs outside the shape."
	return ""


enum CutProblem { NONE, CROSSES, CROSSES_ITSELF, OUTSIDE }


# Whether the cut from vertex a through path to vertex b stays inside the ring.
#
# Two things can put it outside. It can cross an edge, which is checked against
# every edge that does not already share an end of the cut with it, since those
# meet it at that end rather than crossing it. Or it can cross nothing and still
# lie outside, which is what a line across the mouth of a dent does, so the
# middle of every stretch of it has to be inside the ring as well. A cut that
# crosses itself would leave halves that overlap themselves.
static func cut_problem(ring: PackedVector2Array, a: int, b: int,
		path := PackedVector2Array()) -> CutProblem:
	var size := ring.size()
	if size < 3:
		return CutProblem.OUTSIDE
	var cut := PackedVector2Array([ring[a]])
	cut.append_array(path)
	cut.append(ring[b])
	var last := cut.size() - 2
	for k in range(last + 1):
		var from := cut[k]
		var to := cut[k + 1]
		for i in range(size):
			var j := (i + 1) % size
			if k == 0 and (i == a or j == a):
				continue
			if k == last and (i == b or j == b):
				continue
			if Geometry2D.segment_intersects_segment(from, to, ring[i], ring[j]) != null:
				return CutProblem.CROSSES
		for m in range(k + 2, last + 1):
			if Geometry2D.segment_intersects_segment(from, to, cut[m], cut[m + 1]) != null:
				return CutProblem.CROSSES_ITSELF
		if not Geometry2D.is_point_in_polygon((from + to) * 0.5, ring):
			return CutProblem.OUTSIDE
	return CutProblem.NONE


# The two polygons the ring becomes when it is cut from a to b through the
# vertices of path. Both hold the two vertices the cut runs between and the
# path; every other vertex goes to one half.
static func split_polygon(ring: PackedVector2Array, a: int, b: int,
		path := PackedVector2Array()) -> Array[PackedVector2Array]:
	var low := mini(a, b)
	var high := maxi(a, b)
	# The path as it runs from low to high.
	var forward := path.duplicate()
	if a > b:
		forward.reverse()
	var backward := forward.duplicate()
	backward.reverse()
	var halves: Array[PackedVector2Array] = []
	var first := ring.slice(low, high + 1)
	first.append_array(backward)
	halves.append(first)
	var second := ring.slice(high)
	second.append_array(ring.slice(0, low + 1))
	second.append_array(forward)
	halves.append(second)
	return halves


static func _neighbours(size: int, a: int, b: int) -> bool:
	var low := mini(a, b)
	var high := maxi(a, b)
	return high - low < 2 or size - high + low < 2


# Why the polygon cannot be split along a cut drawn across it, or an empty string
# when it can. The path is every point of the cut, ends included; see
# with_cut_ends() for where the ends go. Both ends on one edge would take a bite
# out of that edge rather than cut the polygon across, and are refused.
static func split_along_problem(ring: PackedVector2Array, path: PackedVector2Array) -> String:
	if path.size() < 2:
		return "A cut needs a start and an end."
	var cut := with_cut_ends(ring, path[0], path[path.size() - 1])
	if _neighbours((cut[0] as PackedVector2Array).size(), cut[1], cut[2]):
		return "Both ends of the cut land on the same edge."
	return polygon_split_problem(cut[0], cut[1], cut[2], path.slice(1, path.size() - 1))


# The two polygons the ring becomes when it is cut along a drawn path. Between
# them they hold every vertex of the ring once, and the two ends and the points
# between them twice.
static func split_along(ring: PackedVector2Array, path: PackedVector2Array) -> Array[PackedVector2Array]:
	var cut := with_cut_ends(ring, path[0], path[path.size() - 1])
	return split_polygon(cut[0], cut[1], cut[2], path.slice(1, path.size() - 1))


# The edge the two halves of such a cut share: the cut itself with its ends
# snapped onto the ring, which is what the ridge left behind is drawn along.
static func shared_edge(ring: PackedVector2Array, path: PackedVector2Array) -> PackedVector2Array:
	var cut := with_cut_ends(ring, path[0], path[path.size() - 1])
	var edge := PackedVector2Array([cut[0][cut[1]]])
	edge.append_array(path.slice(1, path.size() - 1))
	edge.append(cut[0][cut[2]])
	return edge


# A cut drawn across the polygon, its first and last points put on the ring.
# Each end goes to the nearest point of the boundary and becomes a vertex there,
# unless that point is a vertex already. Returns the ring with the ends in it and
# where they went, [ring, a, b]; the points between the ends are the path.
static func with_cut_ends(ring: PackedVector2Array, from: Vector2,
		to: Vector2) -> Array:
	var size := ring.size()
	var ends := [_on_ring(ring, from), _on_ring(ring, to)]
	var result := PackedVector2Array()
	var at := [-1, -1]
	for i in range(size):
		for k in 2:
			if ends[k][0] == i and ends[k][1] == 0.0:
				at[k] = result.size()
		result.append(ring[i])
		# Both ends inside one edge is refused later, as neighbours, whichever
		# order they go in here.
		for k in 2:
			if ends[k][0] == i and ends[k][1] > 0.0:
				at[k] = result.size()
				result.append(ring[i].lerp(ring[(i + 1) % size], ends[k][1]))
	return [result, at[0], at[1]]


# The nearest point of the ring's boundary, as [edge, fraction along it]. A
# point at the end of an edge is given as the start of the next one, fraction 0,
# so that a vertex is always named the same way.
static func _on_ring(ring: PackedVector2Array, point: Vector2) -> Array:
	var found := nearest_segment(ring, point, true)
	var edge := int(found[0])
	var along := float(found[2])
	if along >= 1.0:
		return [(edge + 1) % ring.size(), 0.0]
	return [edge, along]


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
