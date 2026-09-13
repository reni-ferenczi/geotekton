extends TestCase

# Coupling: one feature riding on another over a span of the timeline. See
# Logic/coupling.gd and Docs/Time.md#coupling.

# How the parent turns: two keyframes far enough apart that every span below
# sees it moving, about all three axes.
const PARENT_YOUNG := Vector3(40, 20, 10)
const PARENT_OLD := Vector3(-50, -10, 30)

# Rotations compared as matrices; a keyframe goes through 32-bit angles.
const EPS := 1e-4


### Helpers


# A document holding a moving parent and a rider standing still at 800 Ma.
func _document() -> Document:
	var document := Document.new()
	var parent := _polygon("Mountain")
	Keyframe.upsert(parent.keyframes, 0.0, PARENT_YOUNG)
	Keyframe.upsert(parent.keyframes, 1000.0, PARENT_OLD)
	document.root.children.append(parent)
	var child := _polygon("Rider")
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
	var child := _named(document, "Rider")
	var still := _world(document, child, 900.0)

	assert_eq(document.couple(child, parent, 500.0), "")
	assert_eq(document.decouple(child, 200.0), "")
	assert_eq(child.couplings.size(), 1, "one span")
	assert_eq([child.couplings[0].from, child.couplings[0].to], [500.0, 200.0])
	assert_eq(child.keyframes.map(func(k: Keyframe) -> float: return k.time), [200.0, 500.0, 800.0],
		"a keyframe at each boundary and the one it had")

	for time in [2000.0, 900.0, 700.0, 520.0, 500.0]:
		_assert_basis(_world(document, child, time), still, "stands still at %s Ma" % time)

	var riding := _relative(document, parent, child, 500.0)
	for time in [480.0, 400.0, 300.0, 200.5]:
		_assert_basis(_relative(document, parent, child, time), riding,
			"rides on the parent at %s Ma" % time)
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


func test_two_children_ride_on_one_parent() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var first := _named(document, "Rider")
	var second := _polygon("Second Rider")
	# Older than the span, so it stays a world keyframe.
	Keyframe.upsert(second.keyframes, 900.0, Vector3(-70, 0, 0))
	document.root.children.append(second)
	document.record()

	assert_eq(document.couple(first, parent, 700.0), "")
	assert_eq(document.couple(second, parent, 700.0), "")
	for child in [first, second]:
		var riding := _relative(document, parent, child, 700.0)
		for time in [600.0, 300.0, 0.0]:
			_assert_basis(_relative(document, parent, child, time), riding,
				"%s rides on at %s Ma" % [child.title, time])
	assert_true(_differs(_world(document, first, 300.0), _world(document, second, 300.0)),
		"and the two keep apart")


func test_a_chain_of_three_is_followed_to_its_end() -> void:
	var document := _document()
	var top := _named(document, "Mountain")
	var middle := _named(document, "Rider")
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
			"the pebble rides on the rider at %s Ma" % time)
	_assert_basis(_relative(document, top, middle, 300.0),
		Feature.build_rotation_basis(Vector3(25, 0, 0)), "which rides on the mountain")

	var geometry := Planet.collect_geometry(document.root, 300.0)
	for node in [bottom, middle, top]:
		_assert_basis(geometry.bases[geometry.index_of[node]], _world(document, node, 300.0),
			"the geometry resolves %s the same way" % node.title)


func test_a_cycle_is_refused() -> void:
	var document := _document()
	var a := _named(document, "Mountain")
	var b := _named(document, "Rider")
	var c := _polygon("Pebble")
	document.root.children.append(c)
	document.record()

	assert_eq(document.couple(b, a, 500.0), "")
	var versions := document.applied
	assert_true(not document.couple(a, b, 300.0).is_empty(), "a rides on b while b rides on a")
	assert_eq(document.couple(c, b, 600.0), "")
	assert_true(not document.couple(a, c, 900.0).is_empty(), "round a chain of three")
	assert_true(not document.couple(a, a, 900.0).is_empty(), "a feature on itself")
	assert_eq(a.couplings.size(), 0, "the refusals changed nothing")
	assert_eq(document.applied, versions + 1, "and recorded nothing")


func test_what_cannot_be_coupled_is_refused_with_a_reason() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Rider")
	var group := Feature.create_group("Plates")
	document.root.children.append(group)
	var topology := Feature.create_feature("Boundary")
	topology.geometry_kind = Feature.GeometryKind.TOPOLOGY
	document.root.children.append(topology)
	document.record()

	assert_true(not document.couple(child, group, 500.0).is_empty(), "a group is no parent")
	assert_true(not document.couple(child, topology, 500.0).is_empty(), "nor is a topology")
	assert_true(not document.couple(topology, parent, 500.0).is_empty(), "nor does a topology ride")
	assert_true(not document.couple(child, null, 500.0).is_empty(), "nothing picked")
	assert_true(not document.decouple(child, 500.0).is_empty(), "nothing to decouple")

	parent.time_range = Vector2i(300, 2000)
	assert_true(not document.couple(child, parent, 500.0).is_empty(),
		"a parent gone before the span runs out")
	parent.time_range = Vector2i(0, 2000)

	assert_eq(document.couple(child, parent, 500.0), "")
	assert_true(not document.couple(child, parent, 300.0).is_empty(), "already riding then")
	assert_true(not document.decouple(child, 0.0).is_empty(),
		"a span running to the present is not decoupled at the present")


### Nothing on the globe moves


func test_coupling_moves_nothing_at_any_keyframe() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Rider")
	Keyframe.upsert(child.keyframes, 100.0, Vector3(-20, 0, 5))
	Keyframe.upsert(child.keyframes, 300.0, Vector3(30, -15, 0))
	var before := {}
	for time in [100.0, 300.0, 400.0, 800.0]:
		before[time] = _world(document, child, time)
	var stored := child.keyframes[1].rotation

	assert_eq(document.couple(child, parent, 400.0), "")
	for time in before:
		_assert_basis(_world(document, child, time), before[time], "where it stood at %s Ma" % time)
	assert_true(not child.keyframes[1].rotation.is_equal_approx(stored),
		"the keyframe at 300 Ma is relative to the parent now")


func test_key_holds_a_coupled_feature_where_it_stands() -> void:
	var document := _document()
	var child := _named(document, "Rider")
	assert_eq(document.couple(child, _named(document, "Mountain"), 500.0), "")
	var here := _world(document, child, 350.0)
	assert_eq(document.set_keyframe(child, 350.0,
		Feature.keyframe_rotation(document.root, child, 350.0)), "")
	_assert_basis(_world(document, child, 350.0), here, "a keyframe in the parent's frame")


func test_removing_a_span_leaves_every_keyframe_where_it_was() -> void:
	var document := _document()
	var child := _named(document, "Rider")
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
	var child := _named(document, "Rider")
	assert_eq(document.couple(child, _named(document, "Mountain"), 500.0), "")
	assert_eq(document.decouple(child, 500.0), "")
	assert_eq(child.couplings.size(), 0)


func test_a_span_coupled_before_another_ends_where_that_one_starts() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Rider")
	assert_eq(document.couple(child, parent, 300.0), "")
	assert_eq(document.couple(child, parent, 600.0), "")
	assert_eq(child.couplings.map(func(s: Coupling) -> Array: return [s.from, s.to]),
		[[300.0, 0.0], [600.0, 300.0]])


### The rule for a keyframe that is gone


func test_a_deleted_keyframe_falls_back_to_the_older_frame() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Rider")
	assert_eq(document.couple(child, parent, 500.0), "")
	assert_eq(document.decouple(child, 200.0), "")
	var riding := _relative(document, parent, child, 400.0)

	# Without the keyframe at 200 Ma the span at 500 Ma decides everything
	# younger, so the child rides on past the decoupling.
	assert_eq(document.remove_keyframe(child, 0), "")
	for time in [300.0, 100.0]:
		_assert_basis(_relative(document, parent, child, time), riding,
			"the older keyframe's frame at %s Ma" % time)

	# Without the one at 500 Ma the world keyframes either side decide, and the
	# younger one is converted into the world frame at its own time.
	document.undo()
	child = _named(document, "Rider")
	assert_eq(document.remove_keyframe(child, 1), "")
	var wanted := Feature.build_rotation_basis(Keyframe.interpolate(child.keyframes, 400.0))
	_assert_basis(_world(document, child, 400.0), wanted, "a world interpolation inside the span")


func test_a_deleted_parent_leaves_the_span_unresolved_until_undo() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Rider")
	assert_eq(document.couple(child, parent, 500.0), "")
	document.root.children.erase(parent)
	document.record()

	assert_eq(child.couplings.size(), 1, "the span stays")
	var nodes := Coupling.index(document.root)
	assert_true(not Coupling.parent_problem(nodes, child, child.couplings[0]).is_empty(),
		"and says what it lost")
	_world(document, child, 300.0)

	document.undo()
	child = _named(document, "Rider")
	nodes = Coupling.index(document.root)
	assert_eq(Coupling.parent_problem(nodes, child, child.couplings[0]), "", "undo mends it")


### Keeping the spans


func test_couplings_survive_json_clone_and_undo() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Rider")
	assert_eq(document.couple(child, parent, 500.0), "")
	assert_eq(document.decouple(child, 200.0), "")

	var read := Feature.from_json(JSON.parse_string(JSON.stringify(child.to_json())))
	assert_eq(Coupling.list_to_json(read.couplings), Coupling.list_to_json(child.couplings),
		"through the file")
	assert_eq(Coupling.list_to_json(child.clone().couplings), Coupling.list_to_json(child.couplings),
		"through a clone")
	assert_eq(read.couplings[0].parent, parent.uuid, "naming the parent by uuid")

	document.undo()
	assert_eq(_named(document, "Rider").couplings[0].to, 0.0, "undo puts the open span back")
	document.undo()
	assert_eq(_named(document, "Rider").couplings.size(), 0, "and then takes it away")
	document.redo()
	document.redo()
	assert_eq(_named(document, "Rider").couplings[0].to, 200.0, "redo brings both back")


func test_both_halves_of_a_split_keep_the_couplings() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Rider")
	var rider := _polygon("Pebble")
	document.root.children.append(rider)
	document.record()
	assert_eq(document.couple(child, parent, 500.0), "")
	assert_eq(document.couple(rider, child, 500.0), "")

	assert_eq(document.split_feature(child, 0, 0, 2), "")
	var halves := [_named(document, "Rider"), _named(document, "Rider 2")]
	for half in halves:
		assert_eq(Coupling.list_to_json(half.couplings)[0]["parent"], parent.uuid,
			"%s rides on the mountain" % half.title)
	assert_eq(rider.couplings[0].parent, halves[0].uuid, "the pebble rides on the first half")


### The graphs


func test_the_motion_times_of_a_rider_include_its_parents_inside_the_span() -> void:
	var document := _document()
	var parent := _named(document, "Mountain")
	var child := _named(document, "Rider")
	Keyframe.upsert(parent.keyframes, 350.0, Vector3.ZERO)
	assert_eq(document.couple(child, parent, 500.0), "")
	assert_eq(document.decouple(child, 200.0), "")
	assert_eq(Array(Kinematics.motion_times(document.root, child)), [200.0, 350.0, 500.0, 800.0],
		"the parent's keyframe at 350 Ma, but not those outside the span")
