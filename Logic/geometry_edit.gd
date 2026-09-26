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
# that would fall under the minimum its kind needs is not refused: the part
# goes with the vertex, which Document.remove_vertex() does, and which is the
# one way to take a single part out of a feature of several. See
# Docs/Editing.md#deleting.
static func removal_problem(ring: PackedVector2Array, index: int) -> String:
	if index < 0 or index >= ring.size():
		return "There is no vertex %d." % index
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
	var plane := plane_for(ring, path)
	match cut_problem(turned(ring, plane), a, b, turned(path, plane)):
		CutProblem.CROSSES:
			return "The cut crosses the edge of the shape between its ends."
		CutProblem.CROSSES_ITSELF:
			return "The cut crosses itself."
		CutProblem.OUTSIDE:
			return "The cut runs outside the shape."
	return ""


enum CutProblem { NONE, CROSSES, CROSSES_ITSELF, OUTSIDE }


# Whether the cut from vertex a through path to vertex b stays inside the ring,
# both as flat x and y; polygon_split_problem() turns them into the plane first.
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
#
# Each half starts with the cut: its first path.size() + 2 vertices are the cut,
# ends included, from high back to low in the first half and from low to high
# in the second. The crust a split leaves names that run by index; see
# Document._add_crust().
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
	var first := PackedVector2Array([ring[high]])
	first.append_array(backward)
	first.append_array(ring.slice(low, high))
	var second := PackedVector2Array([ring[low]])
	second.append_array(forward)
	second.append_array(ring.slice(high))
	second.append_array(ring.slice(0, low))
	var halves: Array[PackedVector2Array] = [first, second]
	return halves


static func _neighbours(size: int, a: int, b: int) -> bool:
	var low := mini(a, b)
	var high := maxi(a, b)
	return high - low < 2 or size - high + low < 2


# Why the polygon cannot be split along a cut drawn across it, or an empty string
# when it can; see cut_pieces().
static func split_along_problem(ring: PackedVector2Array, path: PackedVector2Array) -> String:
	return cut_pieces(ring, path)["problem"]


# The two polygons the ring becomes when a cut of one stretch runs across it:
# the piece the feature keeps and the other one. Between them they hold every
# vertex of the ring once, and the two ends and the points between them twice.
# A cut of several stretches makes more pieces; cut_pieces() has them all.
static func split_along(ring: PackedVector2Array, path: PackedVector2Array) -> Array[PackedVector2Array]:
	var cut := cut_pieces(ring, path)
	var first: int = cut["first"]
	var halves: Array[PackedVector2Array] = [cut["pieces"][first][0], cut["pieces"][-first][0]]
	return halves


# The edge the two halves of a cut of one stretch share: the stretch, from
# where it meets the ring to where it leaves it, which is where the ridge left
# behind starts out. Each half's ring starts with it.
static func shared_edge(ring: PackedVector2Array, path: PackedVector2Array) -> PackedVector2Array:
	return cut_pieces(ring, path)["edge"]


### Cutting along a drawn line
#
# A line drawn across a polygon cuts it wherever it runs inside the outline.
# Each stretch of it inside, from where it crosses the outline to where it
# crosses back, cuts the piece it lies in in two, so a line that goes in and out
# of a bay or across the arms of a C makes more than two pieces. The pieces left
# of the line, in the direction it was drawn, are one side and those right of it
# the other, which is what lets a split make two features of any number of
# pieces: each holds its side's pieces as its parts.

const LEFT := 1
const RIGHT := -1
const OUTSIDE_PROBLEM := "The cut runs outside the shape."


# The pieces a drawn line cuts the ring into, as a dictionary:
#   problem   why it cannot be cut, or an empty string
#   pieces    {LEFT: [ring, ...], RIGHT: [ring, ...]}
#   first     the side of the piece the feature keeps
#   stretches how many stretches of the line run inside the ring
#   edge      for a cut of one stretch, the edge the two pieces share
#   edges     the edge of every stretch, in the order and direction the line
#             runs; each is a run of vertices of one piece on each side
# An end clicked inside the ring is carried on along the line to the outline,
# so a cut stopped a little short still goes through. A cut of one stretch
# keeps the order split_polygon() gives, each piece starting with the edge, the
# kept piece first on its side and the other first on the other, which is what
# the ridge is laid along.
static func cut_pieces(ring: PackedVector2Array, path: PackedVector2Array) -> Dictionary:
	var result := {"problem": "", "pieces": {LEFT: [], RIGHT: []}, "first": LEFT,
		"stretches": 0, "edge": PackedVector2Array(), "edges": []}
	if path.size() < 2:
		result["problem"] = "A cut needs a start and an end."
		return result
	if ring.size() < 3:
		result["problem"] = OUTSIDE_PROBLEM
		return result
	var plane := plane_for(ring, path)
	var flat := turned(ring, plane)
	var line := _reach_outline(flat, turned(path, plane))
	var stretches := _stretches(flat, line)
	if stretches.is_empty():
		result["problem"] = OUTSIDE_PROBLEM
		return result
	if _cross(stretches):
		result["problem"] = "The cut crosses itself."
		return result
	result["stretches"] = stretches.size()

	var pieces: Array[PackedVector2Array] = [flat]
	for k in stretches.size():
		var stretch: PackedVector2Array = stretches[k]
		var at := _piece_holding(pieces, stretch)
		if at < 0:
			result["problem"] = "The cut crosses itself."
			return result
		var cut := cut_across(pieces[at], stretch)
		var between: PackedVector2Array = cut[3]
		if cut[1] == cut[2] or (between.is_empty() \
				and _neighbours((cut[0] as PackedVector2Array).size(), cut[1], cut[2])):
			result["problem"] = "The cut runs along the edge of the shape."
			return result
		var halves := split_polygon(cut[0], cut[1], cut[2], between)
		if k == 0:
			result["first"] = LEFT if _holds(halves[0], _beside(stretch, LEFT)) else RIGHT
			result["edge"] = _back_all(stretch, plane)
		result["edges"].append(_back_all(stretch, plane))
		pieces[at] = halves[0]
		pieces.append(halves[1])

	for piece in pieces:
		var side := _side_of_piece(piece, stretches, line)
		result["pieces"][side].append(_back_all(piece, plane))
	# For one stretch the kept piece is pieces[0] and the other pieces[1], each
	# alone on its side already.
	return result


static func _back_all(points: PackedVector2Array, plane: Basis) -> PackedVector2Array:
	if plane == Basis.IDENTITY:
		return points
	var result := PackedVector2Array()
	for point in points:
		result.append(_back(point, plane))
	return result


# The line with each end that lies inside the ring carried on, the way the line
# was going, to where it meets the outline.
static func _reach_outline(ring: PackedVector2Array, line: PackedVector2Array) -> PackedVector2Array:
	var result := line.duplicate()
	if Geometry2D.is_point_in_polygon(result[0], ring):
		var reached: Variant = _ray_to_outline(ring, result[0], result[0] - result[1])
		if reached != null:
			result.insert(0, reached)
	var last := result.size() - 1
	if Geometry2D.is_point_in_polygon(result[last], ring):
		var reached: Variant = _ray_to_outline(ring, result[last], result[last] - result[last - 1])
		if reached != null:
			result.append(reached)
	return result


# Where a ray from inside the ring first meets its outline, or null.
static func _ray_to_outline(ring: PackedVector2Array, from: Vector2, direction: Vector2) -> Variant:
	if direction.length() < 1e-12:
		return null
	var reach := 0.0
	for vertex in ring:
		reach = maxf(reach, from.distance_to(vertex))
	var to := from + direction.normalized() * (reach * 2.0 + 1.0)
	var best: Variant = null
	var nearest := INF
	for i in ring.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(
			from, to, ring[i], ring[(i + 1) % ring.size()])
		if hit != null and from.distance_to(hit) < nearest:
			nearest = from.distance_to(hit)
			best = hit
	return best


# The stretches of the line inside the ring, in the order the line runs, each
# from a crossing of the outline through the line's points to the next one.
static func _stretches(ring: PackedVector2Array, line: PackedVector2Array) -> Array:
	var crossings := []
	for k in line.size() - 1:
		var length := line[k].distance_to(line[k + 1])
		if length < 1e-12:
			continue
		for i in ring.size():
			var at: Variant = Geometry2D.segment_intersects_segment(
				line[k], line[k + 1], ring[i], ring[(i + 1) % ring.size()])
			if at != null:
				crossings.append([k + line[k].distance_to(at) / length, at])
	crossings.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	# A crossing through a vertex is found on both of its edges.
	var unique := []
	for crossing in crossings:
		if unique.is_empty() or (crossing[1] as Vector2).distance_to(unique[-1][1]) > 1e-9:
			unique.append(crossing)
	var stretches := []
	for c in unique.size() - 1:
		var from: float = unique[c][0]
		var to: float = unique[c + 1][0]
		if not Geometry2D.is_point_in_polygon(_at(line, (from + to) * 0.5), ring):
			continue
		var stretch := PackedVector2Array([unique[c][1]])
		for k in range(ceili(from), floori(to) + 1):
			if k > from + 1e-9 and k < to - 1e-9:
				stretch.append(line[k])
		stretch.append(unique[c + 1][1])
		stretches.append(stretch)
	return stretches


# The point that far along the line, counted in segments.
static func _at(line: PackedVector2Array, along: float) -> Vector2:
	var k := clampi(floori(along), 0, line.size() - 2)
	return line[k].lerp(line[k + 1], along - k)


# Whether any stretch crosses itself or another one.
static func _cross(stretches: Array) -> bool:
	for a in stretches.size():
		var one: PackedVector2Array = stretches[a]
		for b in range(a, stretches.size()):
			var two: PackedVector2Array = stretches[b]
			for i in one.size() - 1:
				for j in two.size() - 1:
					if a == b and absi(i - j) < 2:
						continue
					if Geometry2D.segment_intersects_segment(one[i], one[i + 1], two[j], two[j + 1]) != null:
						return true
	return false


# Which of the pieces the stretch runs through: both its ends on the piece's
# outline and the stretch inside it. -1 when none is.
static func _piece_holding(pieces: Array[PackedVector2Array], stretch: PackedVector2Array) -> int:
	for at in pieces.size():
		var piece := pieces[at]
		if nearest_segment(piece, stretch[0], true)[1] > 1e-4 \
				or nearest_segment(piece, stretch[stretch.size() - 1], true)[1] > 1e-4:
			continue
		if _holds(piece, _beside(stretch, LEFT)) or _holds(piece, _beside(stretch, RIGHT)):
			return at
	return -1


# A point just off the middle of the stretch's longest segment, on that side.
static func _beside(stretch: PackedVector2Array, side: int) -> Vector2:
	var longest := 0
	for i in stretch.size() - 1:
		if stretch[i].distance_to(stretch[i + 1]) > stretch[longest].distance_to(stretch[longest + 1]):
			longest = i
	var from := stretch[longest]
	var to := stretch[longest + 1]
	var along := to - from
	var off := Vector2(-along.y, along.x).normalized() * maxf(along.length() * 1e-4, 1e-7)
	return (from + to) * 0.5 + off * side


static func _holds(piece: PackedVector2Array, point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, piece)


# Which side of the line a piece is on: the side of a stretch it lies beside.
# Every piece borders one; the side of its middle is a fallback for a piece
# the checks miss by rounding.
static func _side_of_piece(piece: PackedVector2Array, stretches: Array, line: PackedVector2Array) -> int:
	for stretch: PackedVector2Array in stretches:
		if _holds(piece, _beside(stretch, LEFT)):
			return LEFT
		if _holds(piece, _beside(stretch, RIGHT)):
			return RIGHT
	return side_of(line, middle(piece))


# The runs a line feature's ring is cut into where the drawn line crosses it,
# by the side of the drawn line each lies on: {LEFT: [run, ...], RIGHT: [...]}.
# Both runs keep the point they were cut at. A ring the line misses is one run.
static func cut_runs(run: PackedVector2Array, path: PackedVector2Array) -> Dictionary:
	var result := {LEFT: [], RIGHT: []}
	if run.size() < 2 or path.size() < 2:
		result[sides(path, [sphere_middle(run)])[0] if path.size() >= 2 else LEFT].append(run)
		return result
	var plane := plane_for(run, path)
	var flat := turned(run, plane)
	var flat_path := turned(path, plane)
	var runs := []
	var current := PackedVector2Array([flat[0]])
	for k in flat.size() - 1:
		var hits := []
		for j in flat_path.size() - 1:
			var at: Variant = Geometry2D.segment_intersects_segment(
				flat[k], flat[k + 1], flat_path[j], flat_path[j + 1])
			if at != null:
				hits.append(at)
		hits.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return flat[k].distance_to(a) < flat[k].distance_to(b))
		for at: Vector2 in hits:
			if at.distance_to(current[current.size() - 1]) < 1e-9:
				continue
			current.append(at)
			runs.append(current)
			current = PackedVector2Array([at])
		current.append(flat[k + 1])
	runs.append(current)
	for piece: PackedVector2Array in runs:
		if piece.size() < 2:
			continue
		var side := side_of(flat_path, (piece[0] + piece[1]) * 0.5)
		result[side].append(_back_all(piece, plane))
	return result


### Dividing
#
# A cut that touches no ring of a feature of several polygons does not cut a
# ring; it divides the parts, each going to the side of it that its middle lies
# on. The Split tool tells the two apart with touches(); see
# Docs/Editing.md#dividing.


# Whether the path touches the ring: crosses one of its edges, or has a point
# inside it. A path that does neither runs wholly outside the ring.
static func touches(ring: PackedVector2Array, path: PackedVector2Array) -> bool:
	var plane := plane_for(ring, path)
	var flat := turned(ring, plane)
	var flat_path := turned(path, plane)
	var size := flat.size()
	for point in flat_path:
		if Geometry2D.is_point_in_polygon(point, flat):
			return true
	for k in flat_path.size() - 1:
		for i in size:
			if Geometry2D.segment_intersects_segment(
					flat_path[k], flat_path[k + 1], flat[i], flat[(i + 1) % size]) != null:
				return true
	return false


# Whether the point lies inside the ring.
static func contains(ring: PackedVector2Array, point: Vector2) -> bool:
	var only := PackedVector2Array([point])
	var plane := plane_for(ring, only)
	return Geometry2D.is_point_in_polygon(turned(only, plane)[0], turned(ring, plane))


# Which side of the divider a point lies on, 1 or -1: the sign of the point
# against the segment of the divider it is nearest to. The first and last
# segments reach on past their ends, so every point of the plane has a side and
# a divider that stops short of a part still puts it somewhere. A point on the
# divider itself counts as 1.
static func side_of(divider: PackedVector2Array, point: Vector2) -> int:
	var last := divider.size() - 2
	var best := INF
	var sign := 1
	for i in range(last + 1):
		var from := divider[i]
		var to := divider[i + 1]
		var length := from.distance_to(to)
		if length < 1e-9:
			continue
		var along := (to - from) / length
		var t := (point - from).dot(along) / length
		if i > 0:
			t = maxf(t, 0.0)
		if i < last:
			t = minf(t, 1.0)
		var distance := point.distance_to(from + (to - from) * t)
		if distance < best:
			best = distance
			sign = 1 if (to - from).cross(point - from) >= 0.0 else -1
	return sign


# The mean of a ring's vertices, in the plane the ring is given in.
static func middle(ring: PackedVector2Array) -> Vector2:
	var total := Vector2.ZERO
	for vertex in ring:
		total += vertex
	return total / maxi(1, ring.size())


# The middle of a ring on the sphere, as (latitude, longitude): the mean of its
# vertices as unit vectors, which holds across ±180° and round a pole where the
# mean of the numbers does not.
static func sphere_middle(ring: PackedVector2Array) -> Vector2:
	var total := Vector3.ZERO
	for vertex in ring:
		total += Feature._latlon_to_xyz_s(vertex)
	if total.length() < 1e-12:
		return ring[0] if not ring.is_empty() else Vector2.ZERO
	return Feature._xyz_to_latlon_s(total.normalized())


# Which side of the divider each point is on, as side_of() gives it, in the
# plane the divider and the points call for.
static func sides(divider: PackedVector2Array, points: PackedVector2Array) -> PackedInt32Array:
	# Taken as one run, so a point across ±180° from the divider counts too.
	var together := divider.duplicate()
	together.append_array(points)
	var plane := plane_for(together)
	var flat := turned(divider, plane)
	var result := PackedInt32Array()
	for point in turned(points, plane):
		result.append(side_of(flat, point))
	return result


# The parts on the other side of the divider from the first part, as indices
# into rings; the first part keeps the feature's title, so its side is the one
# that stays.
static func far_parts(rings: Array, divider: PackedVector2Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	if rings.is_empty():
		return result
	var middles := PackedVector2Array()
	for ring: PackedVector2Array in rings:
		middles.append(sphere_middle(ring))
	var found := sides(divider, middles)
	for index in range(1, rings.size()):
		if found[index] != found[0]:
			result.append(index)
	return result


# Why the parts cannot be divided along the path, or an empty string when they
# can: it needs two points, a feature of more than one part, and parts on both
# sides. A path that touches a ring is a cut of that ring, not a divide, and
# split_along_problem() is the one to ask about it.
static func divide_problem(rings: Array, path: PackedVector2Array) -> String:
	if path.size() < 2:
		return "A cut needs a start and an end."
	if rings.size() < 2:
		return "The cut runs outside the shape."
	if far_parts(rings, path).is_empty():
		return "The cut leaves every part on one side."
	return ""


# The stretch of a path inside a ring, from where it first crosses the boundary
# to where it last does, with the path's points in between. What the Split tool
# cuts a child along; empty when the path crosses the boundary fewer than twice.
static func clip_path(ring: PackedVector2Array, path: PackedVector2Array) -> PackedVector2Array:
	var plane := plane_for(ring, path)
	var flat := turned(ring, plane)
	var flat_path := turned(path, plane)
	# Each crossing as [how far along the path, where], the distance being the
	# segment's index plus the fraction of it covered.
	var crossings := []
	for k in flat_path.size() - 1:
		for i in flat.size():
			var at: Variant = Geometry2D.segment_intersects_segment(
				flat_path[k], flat_path[k + 1], flat[i], flat[(i + 1) % flat.size()])
			if at != null:
				crossings.append([k + flat_path[k].distance_to(at)
					/ flat_path[k].distance_to(flat_path[k + 1]), at])
	if crossings.size() < 2:
		return PackedVector2Array()
	crossings.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var start: float = crossings[0][0]
	var end: float = crossings[-1][0]
	var result := PackedVector2Array([_back(crossings[0][1], plane)])
	for k in range(ceili(start), floori(end) + 1):
		if k > start + 1e-6 and k < end - 1e-6:
			result.append(path[k])
	result.append(_back(crossings[-1][1], plane))
	return result


# A cut drawn across the polygon, its ends put on the ring. An end clicked
# outside goes where the drawn path first crosses the boundary, or last for the
# far end, and the points clicked before that crossing are dropped: the nearest
# point of an irregular outline can be on another edge altogether, and the cut
# from there would run outside. An end clicked inside, or on a path that never
# reaches the boundary, goes to the nearest point of it. Either way it becomes a
# vertex there, unless that point is a vertex already.
#
# Returns [the ring with the ends in it, where the first end went, where the
# last went, the points of the path between the two].
static func cut_across(ring: PackedVector2Array, path: PackedVector2Array) -> Array:
	var size := ring.size()
	var plane := plane_for(ring, path)
	var flat := turned(ring, plane)
	var flat_path := turned(path, plane)
	var backwards := flat_path.duplicate()
	backwards.reverse()
	var ends := [_cut_end(flat, flat_path), _cut_end(flat, backwards)]
	var result := PackedVector2Array()
	var at := [-1, -1]
	for i in range(size):
		for k in 2:
			if ends[k][0] == i and ends[k][1] == 0.0:
				at[k] = result.size()
		result.append(ring[i])
		# Two ends on one edge, a bite out of it, go in in the order they lie
		# along it.
		var order := [0, 1]
		if ends[1][1] < ends[0][1]:
			order = [1, 0]
		for k: int in order:
			if ends[k][0] == i and ends[k][1] > 0.0:
				at[k] = result.size()
				if plane == Basis.IDENTITY:
					result.append(ring[i].lerp(ring[(i + 1) % size], ends[k][1]))
				else:
					result.append(_back(flat[i].lerp(flat[(i + 1) % size], ends[k][1]), plane))
	var first: int = ends[0][2]
	var last: int = path.size() - 1 - int(ends[1][2])
	var between := path.slice(first, last + 1) if last >= first else PackedVector2Array()
	return [result, at[0], at[1], between]


# Where the start of the path goes on the ring, as [edge, fraction along it,
# the first point of the path kept after it]. Both are flat.
static func _cut_end(ring: PackedVector2Array, path: PackedVector2Array) -> Array:
	var size := ring.size()
	if not Geometry2D.is_point_in_polygon(path[0], ring):
		for k in path.size() - 1:
			var edge := -1
			var nearest := INF
			var along := 0.0
			for i in size:
				var hit: Variant = Geometry2D.segment_intersects_segment(
					path[k], path[k + 1], ring[i], ring[(i + 1) % size])
				if hit != null and path[k].distance_to(hit) < nearest:
					nearest = path[k].distance_to(hit)
					edge = i
					along = _along_segment(ring[i], ring[(i + 1) % size], hit)[1]
			if edge >= 0:
				if along >= 1.0:
					return [(edge + 1) % size, 0.0, k + 1]
				return [edge, along, k + 1]
	var found := _on_ring(ring, path[0])
	return [found[0], found[1], 1]


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


### The plane the checks run in
#
# The cut checks treat (latitude, longitude) as flat x and y, which holds while
# the numbers run on without a jump. A ring whose stored vertices cross ±180°
# longitude, or go round a pole, jumps by 360° somewhere along it and is a
# different shape in those numbers; so is a cut that crosses the line. Those
# are checked in a frame turned so the ring's middle sits at (0, 0), and what
# the checks make is turned back. Every other ring is used as it is, so a cut
# on it comes out exactly as it always did.


# The rotation into the frame the ring and the path are checked in: none when
# neither jumps across ±180°, and otherwise the one that brings the middle of
# the ring to (0, 0).
static func plane_for(ring: PackedVector2Array, path := PackedVector2Array()) -> Basis:
	if not _jumps(ring, true) and not _jumps(path, false):
		return Basis.IDENTITY
	var middle := Vector3.ZERO
	for vertex in ring:
		middle += Feature._latlon_to_xyz_s(vertex)
	if middle.length() < 1e-9:
		return Basis.IDENTITY
	var center := Feature._xyz_to_latlon_s(middle.normalized())
	# Round the axis to longitude 0, then down the meridian to the equator.
	return Basis(Vector3.BACK, -deg_to_rad(center.x)) \
		* Basis(Vector3.UP, deg_to_rad(center.y))


# The points in the plane, or the same points when the plane is no turn at all.
static func turned(points: PackedVector2Array, plane: Basis) -> PackedVector2Array:
	if plane == Basis.IDENTITY:
		return points
	return Feature.apply_basis(points, plane)


# A point made in the plane, back in the frame the ring was given in.
static func _back(point: Vector2, plane: Basis) -> Vector2:
	if plane == Basis.IDENTITY:
		return point
	return Feature._xyz_to_latlon_s(plane.transposed() * Feature._latlon_to_xyz_s(point))


# Whether a step between neighbouring points goes more than half way round in
# longitude, which is the numbers jumping across ±180° rather than the line.
static func _jumps(points: PackedVector2Array, closed: bool) -> bool:
	var size := points.size()
	for i in range(size if closed else size - 1):
		if absf(points[(i + 1) % size].y - points[i].y) > 180.0:
			return true
	return false


### Simplifying
#
# A freehand stroke is sampled every few pixels, which is far more vertices
# than the line needs, and the geometry budget is small (Docs/Shader.md). The
# Draw tool keeps the vertices that matter with this and lets the rest go; see
# Docs/Draw.md#freehand.


# The indices of the points a run keeps when simplified to the tolerance, in
# order, by Ramer, Douglas and Peucker: the two ends stay, and between two
# kept points the point furthest from the straight line between them is kept
# when it is further off than the tolerance, and the two halves it makes are
# looked at the same way. Both ends of a run of two or fewer are kept as they
# are. The plane is whichever the points are given in; the Draw tool passes
# window pixels, so the tolerance is what the eye would miss.
static func simplified(points: PackedVector2Array, tolerance: float) -> PackedInt32Array:
	var size := points.size()
	if size <= 2:
		var all := PackedInt32Array()
		for i in size:
			all.append(i)
		return all
	var keep := PackedByteArray()
	keep.resize(size)
	keep.fill(0)
	keep[0] = 1
	keep[size - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, size - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var from := points[span.x]
		var to := points[span.y]
		var furthest := -1
		var furthest_distance := tolerance
		for i in range(span.x + 1, span.y):
			var distance := _off_line(from, to, points[i])
			if distance > furthest_distance:
				furthest = i
				furthest_distance = distance
		if furthest < 0:
			continue
		keep[furthest] = 1
		if furthest - span.x > 1:
			stack.append(Vector2i(span.x, furthest))
		if span.y - furthest > 1:
			stack.append(Vector2i(furthest, span.y))
	var result := PackedInt32Array()
	for i in size:
		if keep[i]:
			result.append(i)
	return result


# How far a point is from the straight line through from and to, or from the
# one point when the two coincide.
static func _off_line(from: Vector2, to: Vector2, point: Vector2) -> float:
	var length := from.distance_to(to)
	if length < 1e-9:
		return from.distance_to(point)
	return absf((to - from).cross(point - from)) / length


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
		var found := _along_segment(points[i], points[(i + 1) % size], target)
		if found[0] < best[1]:
			best = [i, found[0], found[1]]
	return best


# The same for a run in which some points cannot be placed: each entry is a
# Vector2 or null, and a segment with a null end is not offered, since a
# distance to something that cannot be seen means nothing. The Vertex tool
# passes a ring with its vertices round the back of the globe as null, so the
# edges on the near side still take a vertex while the ring as a whole is
# partly hidden.
static func nearest_visible_segment(points: Array, target: Vector2, closed: bool) -> Array:
	var size := points.size()
	var last := size if closed else size - 1
	var best := [-1, INF, 0.0]
	for i in range(maxi(0, last)):
		var from: Variant = points[i]
		var to: Variant = points[(i + 1) % size]
		if from == null or to == null:
			continue
		var found := _along_segment(from, to, target)
		if found[0] < best[1]:
			best = [i, found[0], found[1]]
	return best


# How far target is from the segment, and how far along it the nearest point
# sits, from 0 to 1: [distance, t].
static func _along_segment(from: Vector2, to: Vector2, target: Vector2) -> Array:
	var along := from.direction_to(to)
	var length := from.distance_to(to)
	var t := 0.0 if length < 1e-9 else clampf((target - from).dot(along) / length, 0.0, 1.0)
	return [target.distance_to(from.lerp(to, t)), t]
