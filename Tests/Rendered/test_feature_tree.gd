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
