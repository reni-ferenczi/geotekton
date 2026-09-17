extends TestCase

# Coupling: one feature following another over a span of the timeline. See
# Logic/coupling.gd and Docs/Time.md#coupling.

# How the parent turns: two keyframes far enough apart that every span below
# sees it moving, about all three axes.
const PARENT_YOUNG := Vector3(40, 20, 10)
const PARENT_OLD := Vector3(-50, -10, 30)

# Rotations compared as matrices; a keyframe goes through 32-bit angles.
const EPS := 1e-4


### Helpers


# A document holding a moving parent and a child standing still at 800 Ma.
func _document() -> Document:
	var document := Document.new()
	var parent := _polygon("Mountain")
	Keyframe.upsert(parent.keyframes, 0.0, PARENT_YOUNG)
	Keyframe.upsert(parent.keyframes, 1000.0, PARENT_OLD)
	document.root.children.append(parent)
	var child := _polygon("Child")
	Keyframe.upsert(child.keyframes, 800.0, Vector3(10, 5, 0))
	document.root.children.append(child)
	document.record()
	return document


func _polygon(title: String) -> Feature:
	var feature := Feature.create_feature(title)
	feature.add_ring(PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(14, 10), Vector2(5, 16), Vector2(0, 12)]),
		Feature.GeometryKind.POLYGON)
	return feature


func _named(document: Document, title: String) -> Feature:
	for node in document.root.children:
		if node.title == title:
			return node
	return null


func _world(document: Document, node: Feature, time: float) -> Basis:
	return Feature.world_basis(document.root, node, time)


# The child's pose in the parent's frame at a time.
func _relative(document: Document, parent: Feature, child: Feature, time: float) -> Basis:
	return _world(document, parent, time).transposed() * _world(document, child, time)


func _assert_basis(got: Basis, wanted: Basis, msg: String, eps: float = EPS) -> void:
	for axis in 3:
		assert_close(got[axis], wanted[axis], eps, "%s, column %d" % [msg, axis])


func _differs(a: Basis, b: Basis) -> bool:
	return not a.is_equal_approx(b)


func _times(node: Feature) -> Array:
	return node.keyframes.map(func(k: Keyframe) -> float: return k.time)


# What each keyframe stores, by time, which changes only where its frame does.
func _stored(node: Feature) -> Dictionary:
	var rotations := {}
	for keyframe in node.keyframes:
		rotations[keyframe.time] = keyframe.rotation
	return rotations


# Every keyframe still stores what it stored before, bar the one the edit writes
# at `written`. Compared as rotations rather than as angles, since _rebase()
# takes each one through a basis and back.
func _assert_stored(node: Feature, before: Dictionary, written: float, what: String) -> void:
	var after := _stored(node)
	for time in after:
		if is_equal_approx(time, written):
			continue
		if not before.has(time):
			assert_true(false, "%s at %s Ma is one it had before" % [what, time])
			continue
		_assert_basis(Feature.build_rotation_basis(after[time]),
			Feature.build_rotation_basis(before[time]), "%s at %s Ma alone" % [what, time])


# Where the node stands at each of the times, keyframe times and times between
# them alike.
func _path(document: Document, node: Feature, times: Array) -> Dictionary:
	var path := {}
	for time in times:
		path[time] = _world(document, node, time)
	return path


func _assert_path(document: Document, node: Feature, path: Dictionary, what: String) -> void:
	for time in path:
		_assert_basis(_world(document, node, time), path[time], "%s at %s Ma" % [what, time])


### The span


func test_a_span_holds_its_older_end_and_not_its_younger_one() -> void:
	var span := Coupling.create(500.0, 200.0, "")
	assert_true(span.holds(500.0), "coupled at 500 Ma")
	assert_true(span.holds(300.0), "in between")
	assert_true(not span.holds(200.0), "decoupled at 200 Ma")
	assert_true(not span.holds(600.0), "older than the span")
	var open := Coupling.create(500.0, 0.0, "")
	assert_true(open.holds(0.0), "a span that runs to the present holds the present")


### The completion gate


func test_a_child_follows_its_parent_between_coupling_and_decoupling() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	var still := _world(document, child, 900.0)

	assert_eq(document.couple(child, parent, 500.0), "")
	assert_eq(document.decouple(child, 200.0), "")
	assert_eq(child.couplings.size(), 1, "one span")
	assert_eq([child.couplings[0].from, child.couplings[0].to], [500.0, 200.0])
	assert_eq(child.keyframes.map(func(k: Keyframe) -> float: return k.time), [200.0, 500.0, 800.0],
		"a keyframe at each boundary and the one it had")

	for time in [2000.0, 900.0, 700.0, 520.0, 500.0]:
		_assert_basis(_world(document, child, time), still, "stands still at %s Ma" % time)

	var on_parent := _relative(document, parent, child, 500.0)
	for time in [480.0, 400.0, 300.0, 200.5]:
		_assert_basis(_relative(document, parent, child, time), on_parent,
			"follows the parent at %s Ma" % time)
	assert_true(_differs(_world(document, child, 300.0), still), "and so moves in the world")

	var left := _world(document, child, 200.0)
	for time in [199.0, 100.0, 0.0]:
		_assert_basis(_world(document, child, time), left, "stands still again at %s Ma" % time)

	for boundary in [500.0, 200.0]:
		var at := _world(document, child, boundary)
		_assert_basis(_world(document, child, boundary + 0.001), at,
			"continuous from the older side at %s Ma" % boundary, 1e-3)
		_assert_basis(_world(document, child, boundary - 0.001), at,
			"continuous from the younger side at %s Ma" % boundary, 1e-3)


func test_two_children_follow_one_parent() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var first := _named(document, "Child")
	var second := _polygon("Second Child")
	# Older than the span, so it stays a world keyframe.
	Keyframe.upsert(second.keyframes, 900.0, Vector3(-70, 0, 0))
	document.root.children.append(second)
	document.record()

	assert_eq(document.couple(first, parent, 700.0), "")
	assert_eq(document.couple(second, parent, 700.0), "")
	for child in [first, second]:
		var on_parent := _relative(document, parent, child, 700.0)
		for time in [600.0, 300.0, 0.0]:
			_assert_basis(_relative(document, parent, child, time), on_parent,
				"%s follows on at %s Ma" % [child.title, time])
	assert_true(_differs(_world(document, first, 300.0), _world(document, second, 300.0)),
		"and the two keep apart")


func test_a_chain_of_three_is_followed_to_its_end() -> void:
	var document := _document()
	var top := _named(document, "Mountain")
	var middle := _named(document, "Child")
	var bottom := _polygon("Pebble")
	# Put the end of the chain first in the tree, so the geometry meets it
	# before its parents.
	document.root.children.insert(0, bottom)
	document.record()

	assert_eq(document.couple(middle, top, 900.0), "")
	# The middle one moves on the top one as well.
	assert_eq(document.set_keyframe(middle, 300.0, Vector3(25, 0, 0)), "")
	assert_eq(document.couple(bottom, middle, 900.0), "")

	var on_middle := _relative(document, middle, bottom, 900.0)
	for time in [700.0, 300.0, 100.0]:
		_assert_basis(_relative(document, middle, bottom, time), on_middle,
			"the pebble follows the child at %s Ma" % time)
	_assert_basis(_relative(document, top, middle, 300.0),
		Feature.build_rotation_basis(Vector3(25, 0, 0)), "which follows the mountain")

	var geometry := Planet.collect_geometry(document.root, 300.0)
	for node in [bottom, middle, top]:
		_assert_basis(geometry.bases[geometry.index_of[node]], _world(document, node, 300.0),
			"the geometry resolves %s the same way" % node.title)


func test_a_cycle_is_refused() -> void:
	var document := _document()
	var a := _named(document, "Mountain")
	var b := _named(document, "Child")
	var c := _polygon("Pebble")
	document.root.children.append(c)
	document.record()

	assert_eq(document.couple(b, a, 500.0), "")
	var versions := document.applied
	assert_true(not document.couple(a, b, 300.0).is_empty(), "a follows b while b follows a")
	assert_eq(document.couple(c, b, 600.0), "")
	assert_true(not document.couple(a, c, 900.0).is_empty(), "round a chain of three")
	assert_true(not document.couple(a, a, 900.0).is_empty(), "a feature on itself")
	assert_eq(a.couplings.size(), 0, "the refusals changed nothing")
	assert_eq(document.applied, versions + 1, "and recorded nothing")


func test_what_cannot_be_coupled_is_refused_with_a_reason() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	var group := Feature.create_group("Plates")
	document.root.children.append(group)
	var topology := Feature.create_feature("Boundary")
	topology.geometry_kind = Feature.GeometryKind.TOPOLOGY
	document.root.children.append(topology)
	document.record()

	assert_true(not document.couple(child, group, 500.0).is_empty(), "a group is no parent")
	assert_true(not document.couple(child, topology, 500.0).is_empty(), "nor is a topology")
	assert_true(not document.couple(topology, parent, 500.0).is_empty(), "nor does a topology follow")
	assert_true(not document.couple(child, null, 500.0).is_empty(), "nothing picked")
	assert_true(not document.decouple(child, 500.0).is_empty(), "nothing to decouple")

	parent.time_range = Vector2i(300, 2000)
	assert_true(not document.couple(child, parent, 500.0).is_empty(),
		"a parent gone before the span runs out")
	parent.time_range = Vector2i(0, 2000)

	assert_eq(document.couple(child, parent, 500.0), "")
	assert_true(not document.couple(child, parent, 300.0).is_empty(), "already following then")
	assert_true(not document.decouple(child, 0.0).is_empty(),
		"a span running to the present is not decoupled at the present")


func test_a_circle_neither_follows_nor_carries() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	var circle := _polygon("Ring")
	circle.feature_type = FeatureType.CIRCLE
	document.root.children.append(circle)
	document.record()

	assert_eq(document.couple(circle, parent, 500.0), "A circle follows nothing.")
	assert_eq(document.couple(child, circle, 500.0), "A circle carries nothing.")
	assert_true(circle.couplings.is_empty() and child.couplings.is_empty(), "nothing was coupled")


# A span a file gives a circle still resolves. One that follows a circle
# resolves too, and the panel marks it as broken with the reason.
func test_a_coupling_a_file_gives_a_circle_still_resolves() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	assert_eq(document.couple(child, parent, 500.0), "")
	var before := _world(document, child, 300.0)
	parent.feature_type = FeatureType.CIRCLE
	child.feature_type = FeatureType.CIRCLE

	_assert_basis(_world(document, child, 300.0), before, "the child still follows")
	var nodes := Coupling.index(document.root)
	assert_eq(Coupling.parent_problem(nodes, child, child.couplings[0]),
		"A circle carries nothing.")


### A coupling edit is a cut in time


# Times older than the coupling edits below, keyframe times and times strictly
# between two keyframes alike. Nothing at any of them may move.
const OLDER_THAN_THE_CUT := [400.0, 480.0, 650.0, 800.0, 900.0, 2000.0]


func test_coupling_moves_nothing_at_or_older_than_the_time_it_acts_at() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	Keyframe.upsert(child.keyframes, 100.0, Vector3(-20, 0, 5))
	Keyframe.upsert(child.keyframes, 300.0, Vector3(30, -15, 0))
	document.record()
	var before := _path(document, child, OLDER_THAN_THE_CUT)

	assert_eq(document.couple(child, parent, 400.0), "")
	_assert_path(document, child, before, "where it stood")


func test_decoupling_moves_nothing_at_or_older_than_the_time_it_acts_at() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	assert_eq(document.couple(child, parent, 900.0), "")
	# A drag inside the span, younger than the decoupling below.
	assert_eq(document.set_keyframe(child, 100.0, Vector3(5, -5, 15)), "")
	var before := _path(document, child, OLDER_THAN_THE_CUT)

	assert_eq(document.decouple(child, 400.0), "")
	_assert_path(document, child, before, "where it stood")


func test_coupling_drops_the_keyframes_the_new_span_covers() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	Keyframe.upsert(child.keyframes, 100.0, Vector3(-20, 0, 5))
	Keyframe.upsert(child.keyframes, 300.0, Vector3(30, -15, 0))
	document.record()

	assert_eq(document.couple(child, parent, 400.0), "")
	assert_eq(_times(child), [400.0, 800.0],
		"the two world keyframes inside the span are gone, the older one stays")
	var on_parent := _relative(document, parent, child, 400.0)
	for time in [399.0, 350.0, 200.0, 100.0, 0.0]:
		_assert_basis(_world(document, child, time), _world(document, parent, time) * on_parent,
			"the child is the parent times one relative pose at %s Ma" % time)


func test_decoupling_drops_the_keyframes_the_span_covered() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	assert_eq(document.couple(child, parent, 900.0), "")
	assert_eq(document.set_keyframe(child, 100.0, Vector3(5, -5, 15)), "")

	assert_eq(document.decouple(child, 400.0), "")
	assert_eq(_times(child), [400.0, 900.0], "the keyframe at 100 Ma is gone")
	var left := _world(document, child, 400.0)
	for time in [399.0, 200.0, 100.0, 0.0]:
		_assert_basis(_world(document, child, time), left,
			"and the feature holds its world pose at %s Ma" % time)

	document.undo()
	assert_eq(_times(_named(document, "Child")), [100.0, 900.0], "undo brings the keyframe back")


func test_a_coupling_edit_keeps_every_remaining_keyframe_in_its_own_frame() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	Keyframe.upsert(child.keyframes, 100.0, Vector3(-20, 0, 5))
	Keyframe.upsert(child.keyframes, 1200.0, Vector3(0, 40, 0))
	document.record()

	# _rebase() has nothing to convert but the keyframe the edit writes itself.
	var before := _stored(child)
	assert_eq(document.couple(child, parent, 800.0), "")
	_assert_stored(child, before, 800.0, "coupling leaves the keyframe")

	before = _stored(child)
	assert_eq(document.decouple(child, 400.0), "")
	_assert_stored(child, before, 400.0, "and so does decoupling, the keyframe")


func test_a_child_of_the_edited_feature_moves_only_where_that_feature_does() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	var pebble := _polygon("Pebble")
	document.root.children.append(pebble)
	Keyframe.upsert(child.keyframes, 100.0, Vector3(-20, 0, 5))
	Keyframe.upsert(child.keyframes, 300.0, Vector3(30, -15, 0))
	document.record()
	assert_eq(document.couple(pebble, child, 1000.0), "")
	var before := _path(document, pebble, OLDER_THAN_THE_CUT)
	var younger := _world(document, pebble, 200.0)

	assert_eq(document.couple(child, parent, 400.0), "")
	_assert_path(document, pebble, before, "the pebble stays where it was")
	assert_true(_differs(_world(document, pebble, 200.0), younger),
		"and follows the child where the child's own path changed")


func test_key_holds_a_coupled_feature_where_it_stands() -> void:
	var document := _document()
	var child := _named(document, "Child")
	assert_eq(document.couple(child, _named(document, "Mountain"), 500.0), "")
	var here := _world(document, child, 350.0)
	assert_eq(document.set_keyframe(child, 350.0,
		Feature.keyframe_rotation(document.root, child, 350.0)), "")
	_assert_basis(_world(document, child, 350.0), here, "a keyframe in the parent's frame")


# Remove is the exception to the cut in time: it keeps every keyframe and
# converts it pointwise, so the path between two of them does change.
func test_removing_a_span_leaves_every_keyframe_where_it_was() -> void:
	var document := _document()
	var child := _named(document, "Child")
	assert_eq(document.couple(child, _named(document, "Mountain"), 500.0), "")
	assert_eq(document.set_keyframe(child, 300.0, Vector3(5, 5, 5)), "")
	var before: Array[Basis] = []
	for keyframe in child.keyframes:
		before.append(_world(document, child, keyframe.time))
	var versions := document.applied

	assert_eq(document.remove_coupling(child, 0), "")
	assert_eq(child.couplings.size(), 0)
	assert_eq(document.applied, versions + 1, "one version")
	for i in child.keyframes.size():
		_assert_basis(_world(document, child, child.keyframes[i].time), before[i],
			"at %s Ma" % child.keyframes[i].time)
	assert_true(not document.remove_coupling(child, 0).is_empty(), "no span left to remove")


func test_decoupling_where_the_span_starts_takes_it_away() -> void:
	var document := _document()
	var child := _named(document, "Child")
	assert_eq(document.couple(child, _named(document, "Mountain"), 500.0), "")
	assert_eq(document.decouple(child, 500.0), "")
	assert_eq(child.couplings.size(), 0)


func test_a_span_coupled_before_another_ends_where_that_one_starts() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	assert_eq(document.couple(child, parent, 300.0), "")
	assert_eq(document.couple(child, parent, 600.0), "")
	assert_eq(child.couplings.map(func(s: Coupling) -> Array: return [s.from, s.to]),
		[[300.0, 0.0], [600.0, 300.0]])


### The rule for a keyframe that is gone


func test_a_deleted_keyframe_falls_back_to_the_older_frame() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	assert_eq(document.couple(child, parent, 500.0), "")
	assert_eq(document.decouple(child, 200.0), "")
	var on_parent := _relative(document, parent, child, 400.0)

	# Without the keyframe at 200 Ma the span at 500 Ma decides everything
	# younger, so the child follows on past the decoupling.
	assert_eq(document.remove_keyframe(child, 0), "")
	for time in [300.0, 100.0]:
		_assert_basis(_relative(document, parent, child, time), on_parent,
			"the older keyframe's frame at %s Ma" % time)

	# Without the one at 500 Ma the world keyframes either side decide, and the
	# younger one is converted into the world frame at its own time.
	document.undo()
	child = _named(document, "Child")
	assert_eq(document.remove_keyframe(child, 1), "")
	var wanted := Feature.build_rotation_basis(Keyframe.interpolate(child.keyframes, 400.0))
	_assert_basis(_world(document, child, 400.0), wanted, "a world interpolation inside the span")


func test_a_deleted_parent_leaves_the_span_unresolved_until_undo() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	assert_eq(document.couple(child, parent, 500.0), "")
	document.root.children.erase(parent)
	document.record()

	assert_eq(child.couplings.size(), 1, "the span stays")
	var nodes := Coupling.index(document.root)
	assert_true(not Coupling.parent_problem(nodes, child, child.couplings[0]).is_empty(),
		"and says what it lost")
	_world(document, child, 300.0)

	document.undo()
	child = _named(document, "Child")
	nodes = Coupling.index(document.root)
	assert_eq(Coupling.parent_problem(nodes, child, child.couplings[0]), "", "undo mends it")


### Keeping the spans


func test_couplings_survive_json_clone_and_undo() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	assert_eq(document.couple(child, parent, 500.0), "")
	assert_eq(document.decouple(child, 200.0), "")

	var read := Feature.from_json(JSON.parse_string(JSON.stringify(child.to_json())))
	assert_eq(Coupling.list_to_json(read.couplings), Coupling.list_to_json(child.couplings),
		"through the file")
	assert_eq(Coupling.list_to_json(child.clone().couplings), Coupling.list_to_json(child.couplings),
		"through a clone")
	assert_eq(read.couplings[0].parent, parent.uuid, "naming the parent by uuid")

	document.undo()
	assert_eq(_named(document, "Child").couplings[0].to, 0.0, "undo puts the open span back")
	document.undo()
	assert_eq(_named(document, "Child").couplings.size(), 0, "and then takes it away")
	document.redo()
	document.redo()
	assert_eq(_named(document, "Child").couplings[0].to, 200.0, "redo brings both back")


func test_both_halves_of_a_split_keep_the_couplings() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	var pebble := _polygon("Pebble")
	document.root.children.append(pebble)
	document.record()
	assert_eq(document.couple(child, parent, 500.0), "")
	assert_eq(document.couple(pebble, child, 500.0), "")

	assert_eq(document.split_feature(child, 0, 0, 2), "")
	var halves := [_named(document, "Child"), _named(document, "Child 2")]
	for half in halves:
		assert_eq(Coupling.list_to_json(half.couplings)[0]["parent"], parent.uuid,
			"%s follows the mountain" % half.title)
	assert_eq(pebble.couplings[0].parent, halves[0].uuid, "the pebble follows the first half")


func test_a_split_half_decoupled_between_keyframes_does_not_drift() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	assert_eq(document.couple(child, parent, 1000.0), "")
	assert_eq(document.set_keyframe(child, 800.0, Vector3(10, 5, 0)), "")
	assert_eq(document.set_keyframe(child, 100.0, Vector3(-20, 0, 5)), "")
	assert_eq(document.split_feature(child, 0, 0, 2), "")
	var first := _named(document, "Child")
	var second := _named(document, "Child 2")

	assert_eq(document.decouple(second, 400.0), "")
	# Times strictly between the halves' keyframes, which is where the rebased
	# half used to come apart from the one it was cut from.
	for time in [900.0, 700.0, 500.0, 450.0]:
		_assert_basis(_world(document, second, time), _world(document, first, time),
			"the halves are still one at %s Ma" % time)
	var left := _world(document, second, 400.0)
	for time in [399.0, 250.0, 100.0, 0.0]:
		_assert_basis(_world(document, second, time), left,
			"the decoupled half stands still at %s Ma" % time)
		assert_true(_differs(_world(document, first, time), left),
			"while the other one follows on at %s Ma" % time)


### Following two parents
#
# A span that names a second parent puts its child midway between the two: the
# slerp of their world rotations at one half, which is the half stage rotation
# GPlates reconstructs a mid ocean ridge by. See Docs/Time.md#following-two-parents.


# Two features standing still at 500 Ma and turning as told by the present, with
# a child of both of them over that span.
func _midway(west: Vector3, east: Vector3) -> Document:
	var document := Document.new()
	var names := {"West": west, "East": east}
	for title in names:
		var half := _polygon(title)
		Keyframe.upsert(half.keyframes, 500.0, Vector3.ZERO)
		Keyframe.upsert(half.keyframes, 0.0, names[title])
		document.root.children.append(half)
	var ridge := _polygon("Ridge")
	Keyframe.upsert(ridge.keyframes, 500.0, Vector3.ZERO)
	ridge.couplings.append(Coupling.create(500.0, 0.0,
		_named(document, "West").uuid, _named(document, "East").uuid))
	document.root.children.append(ridge)
	document.record()
	return document


func test_a_two_parent_span_turns_by_half_of_what_one_parent_does() -> void:
	var document := _midway(Vector3.ZERO, Vector3(60, 0, 0))
	var ridge := _named(document, "Ridge")
	_assert_basis(_world(document, ridge, 500.0), Basis(),
		"on the cut where the span starts")
	_assert_basis(_world(document, ridge, 0.0),
		Feature.build_rotation_basis(Vector3(30, 0, 0)),
		"half of the 60 degrees the one parent turned")


func test_a_two_parent_span_follows_parents_that_turn_alike() -> void:
	var document := _midway(Vector3(60, 0, 0), Vector3(60, 0, 0))
	var ridge := _named(document, "Ridge")
	for time in [400.0, 200.0, 0.0]:
		_assert_basis(_world(document, ridge, time), _world(document, _named(document, "West"), time),
			"the ridge turns with both of them at %s Ma" % time)


func test_a_cycle_through_the_second_parent_is_refused() -> void:
	var document := _midway(Vector3.ZERO, Vector3(60, 0, 0))
	var east := _named(document, "East")
	var ridge := _named(document, "Ridge")
	assert_true(not document.couple(east, ridge, 900.0).is_empty(),
		"a parent of the ridge cannot follow the ridge")
	assert_eq(east.couplings.size(), 0, "and the refusal changed nothing")

	# A hand written file naming the ridge itself as the second parent.
	ridge.couplings[0].parent_b = ridge.uuid
	assert_true(not Coupling.parent_problem(
		Coupling.index(document.root), ridge, ridge.couplings[0]).is_empty(),
		"and a span that names the ridge itself says so")


func test_a_span_keeps_its_second_parent_through_json() -> void:
	var document := _midway(Vector3.ZERO, Vector3(60, 0, 0))
	var ridge := _named(document, "Ridge")
	var plain := _named(document, "West")
	plain.couplings.append(Coupling.create(900.0, 600.0, ridge.uuid))

	for node in [ridge, plain]:
		var read := Feature.from_json(JSON.parse_string(JSON.stringify(node.to_json())))
		assert_eq(Coupling.list_to_json(read.couplings), Coupling.list_to_json(node.couplings),
			"%s reads back the way it was written" % node.title)
		assert_eq(read.couplings[0].parent_b, node.couplings[0].parent_b,
			"%s keeps the second parent it had" % node.title)
	assert_true(ridge.couplings[0].to_json().has("parent_b"),
		"the ridge's span writes a second parent")
	assert_true(not plain.couplings[0].to_json().has("parent_b"),
		"and an ordinary span writes no key for one")


func test_the_motion_times_of_a_ridge_count_both_parents() -> void:
	var document := _midway(Vector3.ZERO, Vector3(60, 0, 0))
	Keyframe.upsert(_named(document, "West").keyframes, 350.0, Vector3.ZERO)
	Keyframe.upsert(_named(document, "East").keyframes, 120.0, Vector3(30, 0, 0))
	assert_eq(Array(Kinematics.motion_times(document.root, _named(document, "Ridge"))),
		[0.0, 120.0, 350.0, 500.0], "either parent turning moves the midpoint")


### The ridge a split leaves


# How near two world vertices count as the same point, in degrees.
const ON_THE_EDGE := 1e-3


func _nearest(points: PackedVector2Array, target: Vector2) -> float:
	var best := INF
	for point in points:
		best = minf(best, point.distance_to(target))
	return best


func _world_ring(document: Document, node: Feature, time: float) -> PackedVector2Array:
	return Feature.apply_basis(node.rings[0], Feature.world_basis(document.root, node, time))


func test_a_split_with_a_ridge_leaves_three_features_in_one_version() -> void:
	var document := Document.new()
	var craton := _polygon("Shield")
	Keyframe.upsert(craton.keyframes, 400.0, Vector3(20, 35, 10))
	document.root.children.append(craton)
	document.current_time = 400.0
	document.record()
	var versions := document.applied

	assert_eq(document.split_feature_along(craton, 0,
		PackedVector2Array([Vector2(5, -1), Vector2(6, 8), Vector2(5, 20)]), true), "")
	assert_eq(document.applied, versions + 1, "the split and the ridge are one version")
	assert_eq(document.root.children.map(func(n: Feature) -> String: return n.title),
		["Shield", "Shield 2", "Shield ridge"], "the halves and the ridge behind them")

	var ridge := _named(document, "Shield ridge")
	assert_true(ridge.midway and ridge.geometry_kind == Feature.GeometryKind.TOPOLOGY,
		"the ridge is a midway topology")
	assert_eq(ridge.drawn_as(), Feature.GeometryKind.POLYLINE, "drawn as a line")
	assert_eq(ridge.time_range, Vector2i(0, 400), "there from the split time to the present")
	assert_eq(ridge.couplings.size(), 0, "following nothing")
	assert_eq(ridge.sections.map(func(section: TopologySection) -> String:
			return section.feature_uuid),
		[_named(document, "Shield").uuid, _named(document, "Shield 2").uuid],
		"between the two halves")

	# Every vertex of the ridge is a vertex of both halves at the split time,
	# which is what "on the shared edge" means.
	var on_ridge := _world_ring(document, ridge, 400.0)
	assert_eq(on_ridge.size(), 3, "the cut's three points")
	for title in ["Shield", "Shield 2"]:
		var half := _world_ring(document, _named(document, title), 400.0)
		for vertex in on_ridge:
			assert_true(_nearest(half, vertex) < ON_THE_EDGE,
				"%s holds the ridge vertex %s" % [title, vertex])

	document.undo()
	assert_eq(document.root.children.size(), 1, "undo puts the one craton back")


func test_a_ridge_stays_midway_while_one_half_turns() -> void:
	var document := Document.new()
	var craton := _polygon("Shield")
	document.root.children.append(craton)
	document.current_time = 300.0
	document.record()
	assert_eq(document.split_feature_along(craton, 0,
		PackedVector2Array([Vector2(5, -1), Vector2(6, 8), Vector2(5, 20)]), true), "")
	var first := _named(document, "Shield")
	var second := _named(document, "Shield 2")
	var ridge := _named(document, "Shield ridge")
	assert_eq(document.set_keyframe(second, 300.0, Vector3.ZERO), "")
	assert_eq(document.set_keyframe(second, 0.0, Vector3(40, 0, 0)), "")

	# The one half turned forty degrees and the ridge turned twenty.
	var turned := Feature.apply_basis(first.rings[0].slice(0, 3),
		Feature.build_rotation_basis(Vector3(20, 0, 0)))
	var on_ridge := Ridge.ring_at(document.root, ridge, 0.0)
	assert_eq(on_ridge.size(), 3, "a vertex for each of the cut's")
	for i in on_ridge.size():
		assert_true(on_ridge[i].distance_to(turned[i]) < ON_THE_EDGE,
			"the ridge turns by half of what the half that moved did: %s" % on_ridge[i])

	document.root.children.erase(second)
	document.record()
	assert_true(not str(Topology.resolve(document.root, ridge, 0.0)[1]["problem"]).is_empty(),
		"deleting a half leaves the ridge's section broken")
	document.undo()
	ridge = _named(document, "Shield ridge")
	assert_eq(Ridge.ring_at(document.root, ridge, 0.0).size(), 3, "and undo mends it")


### The graphs


func test_the_motion_times_of_a_child_include_its_parents_inside_the_span() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Child")
	Keyframe.upsert(parent.keyframes, 350.0, Vector3.ZERO)
	assert_eq(document.couple(child, parent, 500.0), "")
	assert_eq(document.decouple(child, 200.0), "")
	assert_eq(Array(Kinematics.motion_times(document.root, child)), [200.0, 350.0, 500.0, 800.0],
		"the parent's keyframe at 350 Ma, but not those outside the span")


### The children of a feature


# A root holding one polygon per title, with no keyframes: children_of() reads the
# spans alone.
func _children_tree(titles: Array) -> Dictionary:
	var root := Feature.create_group("Root")
	var nodes := {"root": root}
	for title in titles:
		var node := _polygon(title)
		root.children.append(node)
		nodes[title] = node
	return nodes


func _titles(nodes: Array[Feature]) -> Array:
	var titles := nodes.map(func(node: Feature) -> String: return node.title)
	titles.sort()
	return titles


func test_the_children_of_a_chain_are_everything_below_it() -> void:
	var nodes := _children_tree(["Top", "Middle", "Bottom"])
	nodes["Middle"].couplings.append(Coupling.create(500.0, 0.0, nodes["Top"].uuid))
	nodes["Bottom"].couplings.append(Coupling.create(500.0, 0.0, nodes["Middle"].uuid))
	var root: Feature = nodes["root"]
	assert_eq(_titles(Coupling.children_of(root, nodes["Top"].uuid, 300.0)), ["Bottom", "Middle"])
	assert_eq(_titles(Coupling.children_of(root, nodes["Middle"].uuid, 300.0)), ["Bottom"])
	assert_eq(_titles(Coupling.children_of(root, nodes["Bottom"].uuid, 300.0)), [])


func test_the_children_of_a_fork_are_both_branches() -> void:
	var nodes := _children_tree(["Stem", "Left", "Right", "Leaf"])
	for branch in ["Left", "Right"]:
		nodes[branch].couplings.append(Coupling.create(500.0, 0.0, nodes["Stem"].uuid))
	nodes["Leaf"].couplings.append(Coupling.create(500.0, 0.0, nodes["Left"].uuid))
	assert_eq(_titles(Coupling.children_of(nodes["root"], nodes["Stem"].uuid, 100.0)),
		["Leaf", "Left", "Right"])


func test_a_ridge_is_a_child_of_each_of_its_parents_once() -> void:
	var nodes := _children_tree(["West", "East", "Ridge", "Seamount"])
	nodes["Ridge"].couplings.append(
		Coupling.create(500.0, 0.0, nodes["West"].uuid, nodes["East"].uuid))
	nodes["Seamount"].couplings.append(Coupling.create(500.0, 0.0, nodes["Ridge"].uuid))
	for side in ["West", "East"]:
		assert_eq(_titles(Coupling.children_of(nodes["root"], nodes[side].uuid, 100.0)),
			["Ridge", "Seamount"], "the children of %s" % side)


func test_a_span_counts_only_while_it_holds() -> void:
	var nodes := _children_tree(["Parent", "Child"])
	nodes["Child"].couplings.append(Coupling.create(500.0, 200.0, nodes["Parent"].uuid))
	var root: Feature = nodes["root"]
	var uuid: String = nodes["Parent"].uuid
	assert_eq(_titles(Coupling.children_of(root, uuid, 600.0)), [], "older than the span")
	assert_eq(_titles(Coupling.children_of(root, uuid, 500.0)), ["Child"], "where it starts")
	assert_eq(_titles(Coupling.children_of(root, uuid, 200.0)), [], "where it ends")
	assert_eq(_titles(Coupling.children_of(root, uuid, 100.0)), [], "younger than the span")


func test_children_stop_at_a_loop() -> void:
	var nodes := _children_tree(["One", "Two"])
	nodes["One"].couplings.append(Coupling.create(500.0, 0.0, nodes["Two"].uuid))
	nodes["Two"].couplings.append(Coupling.create(500.0, 0.0, nodes["One"].uuid))
	assert_eq(_titles(Coupling.children_of(nodes["root"], nodes["One"].uuid, 100.0)), ["Two"])


# A selected group stands for its leaves: their children together, with the
# leaves themselves left out even where one follows another.
func test_the_children_of_a_group_are_those_of_its_leaves() -> void:
	var nodes := _children_tree(["West", "East", "Island", "Seamount", "Outside"])
	var root: Feature = nodes["root"]
	var plates := Feature.create_group("Plates")
	for title in ["West", "East", "Island"]:
		root.children.erase(nodes[title])
		plates.children.append(nodes[title])
	root.children.append(plates)
	nodes["Island"].couplings.append(Coupling.create(500.0, 0.0, nodes["West"].uuid))
	nodes["Seamount"].couplings.append(Coupling.create(500.0, 0.0, nodes["East"].uuid))
	nodes["Outside"].couplings.append(Coupling.create(500.0, 0.0, nodes["Island"].uuid))
	assert_eq(_titles(Coupling.children_of(root, plates.uuid, 100.0)), ["Outside", "Seamount"],
		"the children of the group")
	assert_eq(_titles(Coupling.children_of(root, root.uuid, 100.0)), [],
		"the root holds every leaf, so nothing is left to follow it")
