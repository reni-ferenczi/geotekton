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
#
# A span may name a second parent, which is what a ridge left by the Split tool
# rides on. Its frame is then midway between the two, the half stage rotation
# GPlates reconstructs a mid ocean ridge by; see Docs/Time.md#riding-on-two-parents.

var from: float
var to: float
var parent: String
# The second parent, empty for the ordinary single parent span.
var parent_b: String = ""


static func create(from_: float, to_: float, parent_: String,
		parent_b_: String = "") -> Coupling:
	var span := Coupling.new()
	span.from = from_
	span.to = to_
	span.parent = parent_
	span.parent_b = parent_b_
	return span


func clone() -> Coupling:
	return Coupling.create(from, to, parent, parent_b)


# The uuids the span follows: one ordinarily, two while it rides midway.
func parents() -> Array[String]:
	var result: Array[String] = [parent]
	if not parent_b.is_empty():
		result.append(parent_b)
	return result


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


# Why a parent of a span cannot be followed, or an empty string when every one
# of them can. A span with two parents needs both.
static func parent_problem(nodes: Dictionary, node: Feature, span: Coupling) -> String:
	for uuid in span.parents():
		var problem := _one_parent_problem(nodes, node, uuid)
		if not problem.is_empty():
			return problem
	return ""


# What a span rides on, as the panel and a refusal name it: the parent's title,
# or both titles when it rides midway between two.
static func parents_label(nodes: Dictionary, span: Coupling) -> String:
	var titles := PackedStringArray()
	for uuid in span.parents():
		var parent: Feature = nodes.get(uuid)
		titles.append(parent.title if parent != null else "(missing)")
	if titles.size() == 1:
		return titles[0]
	return "%s and %s, midway" % [titles[0], titles[1]]


static func _one_parent_problem(nodes: Dictionary, node: Feature, uuid: String) -> String:
	var parent: Feature = nodes.get(uuid)
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
			for uuid in span.parents():
				var parent: Feature = nodes.get(uuid)
				if parent == target:
					return true
				if parent != null:
					stack.append(parent)
	return false


# Every feature that rides on the one with `uuid` at a time, and whatever rides
# on those in turn: the couplings walked downward, the way reaches() walks them
# up. A rider of two parents counts once. The list never holds the feature
# itself, even where a broken document loops back to it.
static func riders(root: Feature, uuid: String, time: float) -> Array[Feature]:
	var on := {}
	for node: Feature in index(root).values():
		var span: Coupling = null if node.is_group else span_at(node, time)
		if span == null:
			continue
		for parent in span.parents():
			on.get_or_add(parent, []).append(node)
	var result: Array[Feature] = []
	var seen := {uuid: true}
	var queue: Array[String] = [uuid]
	while not queue.is_empty():
		for rider: Feature in on.get(queue.pop_back(), []):
			if seen.has(rider.uuid):
				continue
			seen[rider.uuid] = true
			result.append(rider)
			queue.append(rider.uuid)
	return result


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


# The frame a span puts its rider in at a time. With one parent that is the
# parent's world rotation; with two it is the slerp of theirs at one half, the
# half stage rotation, so the rider sits midway between them however far they
# have diverged.
static func _parent_basis(span: Coupling, time: float, nodes: Dictionary, cache,
		visiting: Array) -> Basis:
	var first := _one_parent_basis(span.parent, time, nodes, cache, visiting)
	if span.parent_b.is_empty():
		return first
	var second := _one_parent_basis(span.parent_b, time, nodes, cache, visiting)
	return Basis(Quaternion(first).slerp(Quaternion(second), 0.5))


# One parent's world rotation at a time. A parent that cannot be followed —
# missing, a group, a topology, or already on the chain being followed — does
# not turn, so the child's relative keyframes read as world rotations until it
# is mended.
static func _one_parent_basis(uuid: String, time: float, nodes: Dictionary, cache,
		visiting: Array) -> Basis:
	var parent: Feature = nodes.get(uuid)
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
	var result := {"from": from, "to": to, "parent": parent}
	# Only a ridge has a second parent, so an ordinary span reads as it always did.
	if not parent_b.is_empty():
		result["parent_b"] = parent_b
	return result


static func from_json(data: Variant) -> Coupling:
	return Coupling.create(float(data.get("from", 0.0)), float(data.get("to", 0.0)),
		str(data.get("parent", "")), str(data.get("parent_b", "")))


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
