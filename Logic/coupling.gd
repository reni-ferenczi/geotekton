class_name Coupling
extends RefCounted

# One span of the timeline over which a feature rides on another. While the span
# holds, the feature's keyframes are its pose relative to the parent: its world
# rotation is the parent's world rotation composed with its own interpolation.
# Outside every span its keyframes are world rotations. See Docs/Time.md#coupling.
#
# Both ends are ages, `from` the older one, where the span starts as the time
# runs towards the present, and `to` the younger one, where it ends. The span
# holds its older end and not its younger one, so the keyframe that coupling
# writes at `from` is relative and the one decoupling writes at `to` is a world
# pose. A span that runs to the present holds the present as well, since there
# is nothing younger to decouple at.
#
# The parent is named by uuid, the way a topology section names a feature, so a
# parent that is deleted leaves the span in place and unresolved.

var from: float
var to: float
var parent: String


static func create(from_: float, to_: float, parent_: String) -> Coupling:
	var span := Coupling.new()
	span.from = from_
	span.to = to_
	span.parent = parent_
	return span


func clone() -> Coupling:
	return Coupling.create(from, to, parent)


# Whether the span is in effect at a time: its older end counts as inside, its
# younger end does not, unless that end is the present.
func holds(time: float) -> bool:
	if time > from and not is_equal_approx(time, from):
		return false
	return to <= 0.0 or (time > to and not is_equal_approx(time, to))


### Which frame a keyframe is in


# The span of the node in effect at a time, or null when its keyframes there are
# world rotations. Spans on one feature do not overlap.
static func span_at(node: Feature, time: float) -> Coupling:
	for span in node.couplings:
		if span.holds(time):
			return span
	return null


# Every node of the tree by uuid, which is what a span's parent is looked up in.
static func index(root: Feature) -> Dictionary:
	var nodes := {}
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		nodes[node.uuid] = node
		stack.append_array(node.children)
	return nodes


# Why the parent of a span cannot be followed, or an empty string when it can.
static func parent_problem(nodes: Dictionary, node: Feature, span: Coupling) -> String:
	var parent: Feature = nodes.get(span.parent)
	if parent == null:
		return "The feature it rode on is no longer in the document."
	if parent.is_group:
		return "%s is a group, and a feature rides on a feature." % parent.title
	if parent.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return "%s is a topology, which has no motion of its own." % parent.title
	if parent == node or reaches(nodes, parent, node):
		return "%s rides on %s, so the chain goes round in a circle." % [parent.title, node.title]
	return ""


# Whether following the couplings of `start`, at any time, ever reaches `target`.
# Time is left out on purpose: a coupling that could loop back at some time is
# refused outright, so a chain always has an end.
static func reaches(nodes: Dictionary, start: Feature, target: Feature) -> bool:
	var visited := {}
	var stack: Array[Feature] = [start]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if visited.has(node):
			continue
		visited[node] = true
		for span in node.couplings:
			var parent: Feature = nodes.get(span.parent)
			if parent == target:
				return true
			if parent != null:
				stack.append(parent)
	return false


### Where a coupled feature is


# The rotation that carries the node's own frame into world space at a time,
# following the chain of parents to its end. `cache`, when given, holds world
# rotations already worked out at this same time, so resolving a whole document
# at one time works each parent out once.
static func world_basis(node: Feature, time: float, nodes: Dictionary, cache = null) -> Basis:
	return _world(node, time, nodes, cache, [node])


# The rotation to store in a keyframe at a time so the node's world rotation
# there is `world`: the world rotation itself outside every span, and the pose
# relative to the parent inside one.
static func rotation_for(node: Feature, time: float, world: Basis, nodes: Dictionary) -> Vector3:
	var span := span_at(node, time)
	return Feature.decompose_rotation_degrees(_out_of_frame(span, time, world, nodes, null, [node]))


static func _world(node: Feature, time: float, nodes: Dictionary, cache, visiting: Array) -> Basis:
	if node.couplings.is_empty():
		return node.basis_at(time)
	if cache != null and cache.has(node):
		return cache[node]
	var result := _coupled(node, time, nodes, visiting)
	if cache != null:
		cache[node] = result
	return result


# The keyframe interpolation with frames. Landing on a keyframe gives its pose in
# its own frame. Between two keyframes the span in effect at the older one
# decides the frame, and the younger one is converted into it at its own time,
# so nothing jumps where a keyframe was deleted next to a span boundary. Younger
# than the first keyframe its frame holds; older than the last the frame in
# effect at the time holds, with the last keyframe converted into it, so a
# feature coupled at its only keyframe stands still before that time.
static func _coupled(node: Feature, time: float, nodes: Dictionary, visiting: Array) -> Basis:
	var keyframes := node.keyframes
	if keyframes.is_empty():
		return Basis()
	var first: Keyframe = keyframes[0]
	if time <= first.time or is_equal_approx(time, first.time):
		return _in_frame(span_at(node, first.time), time,
			Feature.build_rotation_basis(first.rotation), nodes, visiting)
	var last: Keyframe = keyframes[keyframes.size() - 1]
	if time >= last.time or is_equal_approx(time, last.time):
		var kept := span_at(node, last.time)
		var own := span_at(node, time)
		var pose := Feature.build_rotation_basis(last.rotation)
		if own != kept:
			pose = _out_of_frame(own, last.time,
				_in_frame(kept, last.time, pose, nodes, visiting), nodes, null, visiting)
		return _in_frame(own, time, pose, nodes, visiting)

	for i in range(1, keyframes.size()):
		var older: Keyframe = keyframes[i]
		if older.time < time:
			continue
		var span := span_at(node, older.time)
		if is_equal_approx(older.time, time):
			return _in_frame(span, time, Feature.build_rotation_basis(older.rotation), nodes, visiting)
		var younger: Keyframe = keyframes[i - 1]
		var younger_rotation := younger.rotation
		var younger_span := span_at(node, younger.time)
		if younger_span != span:
			var world := _in_frame(younger_span, younger.time,
				Feature.build_rotation_basis(younger.rotation), nodes, visiting)
			younger_rotation = Feature.decompose_rotation_degrees(
				_out_of_frame(span, younger.time, world, nodes, null, visiting))
		var length := older.time - younger.time
		var pose := older.rotation if length <= 0.0 \
			else Keyframe.blend(younger_rotation, older.rotation, (time - younger.time) / length)
		return _in_frame(span, time, Feature.build_rotation_basis(pose), nodes, visiting)
	return Basis()


static func _in_frame(span: Coupling, time: float, pose: Basis, nodes: Dictionary,
		visiting: Array, cache = null) -> Basis:
	if span == null:
		return pose
	return _parent_basis(span, time, nodes, cache, visiting) * pose


static func _out_of_frame(span: Coupling, time: float, world: Basis, nodes: Dictionary,
		cache, visiting: Array) -> Basis:
	if span == null:
		return world
	return _parent_basis(span, time, nodes, cache, visiting).transposed() * world


# The parent's world rotation at a time. A parent that cannot be followed —
# missing, a group, a topology, or already on the chain being followed — does
# not turn, so the child's relative keyframes read as world rotations until it
# is mended.
static func _parent_basis(span: Coupling, time: float, nodes: Dictionary, cache,
		visiting: Array) -> Basis:
	var parent: Feature = nodes.get(span.parent)
	if parent == null or parent.is_group or visiting.has(parent) \
			or parent.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return Basis()
	visiting.append(parent)
	var result := _world(parent, time, nodes, cache, visiting)
	visiting.pop_back()
	return result


### Lists and JSON


static func clone_list(spans: Array[Coupling]) -> Array[Coupling]:
	var result: Array[Coupling] = []
	for span in spans:
		result.append(span.clone())
	return result


static func sort(spans: Array[Coupling]) -> void:
	spans.sort_custom(func(a: Coupling, b: Coupling) -> bool: return a.from < b.from)


func to_json() -> Dictionary:
	return {"from": from, "to": to, "parent": parent}


static func from_json(data: Variant) -> Coupling:
	return Coupling.create(float(data.get("from", 0.0)), float(data.get("to", 0.0)),
		str(data.get("parent", "")))


static func list_to_json(spans: Array[Coupling]) -> Array:
	var result: Array = []
	for span in spans:
		result.append(span.to_json())
	return result


# The spans a file holds, youngest first. Anything that is not an object is
# skipped rather than failing the whole file.
static func list_from_json(data: Variant) -> Array[Coupling]:
	var result: Array[Coupling] = []
	if data is not Array:
		return result
	for entry in data:
		if entry is Dictionary:
			result.append(Coupling.from_json(entry))
	sort(result)
	return result
