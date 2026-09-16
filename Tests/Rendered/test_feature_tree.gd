extends RenderedCase

# GP-0031: renaming a row and then clicking the empty area under the rows took
# the feature panel down. Godot's Tree emits empty_clicked from inside its own
# mouse handling, where it refuses to be cleared or rebuilt, and the click also
# closed the open cell editor, so item_edited arrived in the same call. The
# handler rebuilt the tree there and then, Tree.clear() bailed out and
# create_item() came back null.


func test_clicking_under_the_rows_while_renaming_keeps_the_tree() -> void:
	await load_sample("two_cratons.middle-earth")

	var feature_tree: FeatureTree = app.features.feature_tree
	var expected := _node_count(app.document.root)

	feature_tree.select_node(app.document.root.children[0])
	await frames(2)
	feature_tree.start_editing()
	await frames(2)

	await click(_under_the_rows(feature_tree))
	# The rebuild is deferred out of the Tree's own mouse handling.
	await frames(2)

	assert_eq(feature_tree.items.size(), expected, "every row is still there")
	assert_eq(feature_tree.get_selected_node(), app.document.root, "the root is selected")


# A point inside the tree control but below its last row.
func _under_the_rows(feature_tree: FeatureTree) -> Vector2:
	var rect := feature_tree.get_global_rect()
	return Vector2(rect.position.x + 20.0, rect.end.y - 20.0)


func _node_count(node: Feature) -> int:
	var count := 1
	for child in node.children:
		count += _node_count(child)
	return count


# GP-0074: dragging a row with the mouse puts it where the drop indicator says.
# The band above a row makes a sibling before it, the band below a row a sibling
# after it, the middle of a group row puts it at the end of that group. Every
# case reads the parent and the index back from the document.

const ABOVE := 0.1
const MIDDLE := 0.5
const BELOW := 0.9


func test_a_leaf_dropped_below_its_expanded_group_leaves_the_group() -> void:
	var groups := await _build(false)
	var leaf: Feature = groups[0].children[1]
	# Below the row of a node with children, open or not, Godot reports section 2.
	await _drag_row(leaf, groups[0], BELOW, 2)
	_check_place(leaf, app.document.root, 1)
	assert_eq(groups[0].children.size(), 2, "the group kept its other two leaves")


func test_a_leaf_dropped_below_a_collapsed_group_lands_after_it() -> void:
	var groups := await _build(true)
	var leaf: Feature = groups[0].children[0]
	await _drag_row(leaf, groups[1], BELOW, 2)
	_check_place(leaf, app.document.root, 2)


func test_a_leaf_dropped_below_the_last_child_stays_in_the_group() -> void:
	var groups := await _build(false)
	var leaf: Feature = groups[0].children[0]
	var last: Feature = groups[0].children[2]
	await _drag_row(leaf, last, BELOW, 1)
	_check_place(leaf, groups[0], 2)
	assert_eq(groups[0].find_child(last), 1, "the old last child moved up by one")


func test_a_leaf_dropped_on_a_group_is_its_last_child() -> void:
	var groups := await _build(false)
	var leaf: Feature = groups[0].children[0]
	await _drag_row(leaf, groups[1], MIDDLE, 0)
	_check_place(leaf, groups[1], 1)


func test_a_leaf_dropped_below_a_sibling_lands_after_it() -> void:
	var groups := await _build(false)
	var group: Feature = groups[0]
	var first: Feature = group.children[0]
	var second: Feature = group.children[1]
	var third: Feature = group.children[2]

	await _drag_row(first, second, BELOW, 1)
	assert_eq(group.children, [second, first, third] as Array[Feature],
		"dragged down, the first leaf is after the second")

	await _drag_row(third, second, BELOW, 1)
	assert_eq(group.children, [second, third, first] as Array[Feature],
		"dragged up, the third leaf is after the second")

	await _drag_row(first, third, ABOVE, -1)
	assert_eq(group.children, [second, first, third] as Array[Feature],
		"dropped above, the first leaf is before the third")


# An empty document holding two groups, the first with three leaves and the
# second with one; `collapsed` closes the second group.
func _build(collapsed: bool) -> Array[Feature]:
	await load_sample("empty.middle-earth")
	var groups: Array[Feature] = []
	for g in 2:
		var group := Feature.create_group("Group %d" % g)
		for f in 3 if g == 0 else 1:
			group.children.append(Feature.create_feature("Leaf %d.%d" % [g, f]))
		app.document.root.children.append(group)
		groups.append(group)
	groups[1].collapsed = collapsed
	app.document.root.collapsed = false
	app.features.reload()
	await frames(2)
	return groups


# Press on the middle of the row of `dragged`, move in steps to the height
# `fraction` of the row of `target`, which must be drop section `section`, and
# release there.
func _drag_row(dragged: Feature, target: Feature, fraction: float, section: int) -> void:
	var feature_tree: FeatureTree = app.features.feature_tree
	var to_local := _row_point(target, fraction)
	# The flags are what a drag sets, so the section can be checked before it.
	feature_tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN
	assert_eq(feature_tree.get_item_at_position(to_local), feature_tree.items[target.pnid],
		"the drop point is on the row of %s" % target.title)
	assert_eq(feature_tree.get_drop_section_at_position(to_local), section,
		"the drop point is in section %d of %s" % [section, target.title])

	var from := feature_tree.get_global_transform() * _row_point(dragged, MIDDLE)
	var to := feature_tree.get_global_transform() * to_local
	Input.use_accumulated_input = false
	_move(from, 0)
	await _physics_frames(2)
	_button(true)
	await _physics_frames(2)
	for step in range(1, 6):
		_move(from.lerp(to, step / 5.0), MOUSE_BUTTON_MASK_LEFT)
		await _physics_frames(2)
	_button(false)
	await _physics_frames(2)
	# The tree is rebuilt deferred after a drop.
	await frames(3)


# A point on the title of a row, `fraction` of the way down it, in tree coordinates.
func _row_point(node: Feature, fraction: float) -> Vector2:
	var feature_tree: FeatureTree = app.features.feature_tree
	var rect := feature_tree.get_item_area_rect(feature_tree.items[node.pnid])
	return Vector2(rect.position.x + rect.size.x * 0.4, rect.position.y + rect.size.y * fraction)


# While a drag is on, the viewport finds the row under the drag from the real
# pointer rather than from the injected motion, so the pointer is moved as well.
func _move(screen: Vector2, mask: int) -> void:
	Input.warp_mouse(screen)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	motion.relative = screen - mouse
	motion.button_mask = mask
	mouse = screen
	Input.parse_input_event(motion)


func _check_place(node: Feature, parent: Feature, index: int) -> void:
	assert_eq(app.document.root.find_parent(node), parent,
		"%s is in %s" % [node.title, parent.title])
	assert_eq(parent.find_child(node), index, "%s is at index %d" % [node.title, index])
