extends RenderedCase

# GP-0110: the toolbar buttons of the feature panel were wired in features.tscn
# to nodes of the instanced toolbar scene, which the export drops, so a release
# build could not add a feature to a new file. The buttons are pressed here,
# not the handlers called, so the wiring is what is checked.


func test_the_first_feature_of_a_new_document_lands_in_the_tree() -> void:
	await load_sample("two_cratons.geotekt")
	app._reset_document()
	await frames(2)

	var feature_tree: FeatureTree = app.features.feature_tree
	assert_eq(feature_tree.items.size(), 1, "a new document shows the root row only")
	assert_eq(feature_tree.get_selected_node(), app.document.root, "the root is selected")

	app.features.add_feature_button.pressed.emit()
	await frames(2)

	assert_eq(app.document.root.children.size(), 1, "the feature is in the document")
	assert_eq(feature_tree.items.size(), 2, "the feature has a row")
	if not app.document.root.children.is_empty():
		assert_eq(feature_tree.get_selected_node(), app.document.root.children[0],
			"the new feature is selected")


func test_the_first_group_of_a_new_document_lands_in_the_tree() -> void:
	await load_sample("two_cratons.geotekt")
	app._reset_document()
	await frames(2)

	app.features.add_group_button.pressed.emit()
	await frames(2)

	assert_eq(app.document.root.children.size(), 1, "the group is in the document")
	assert_eq(app.features.feature_tree.items.size(), 2, "the group has a row")


func test_every_toolbar_button_of_the_feature_panel_is_wired() -> void:
	var features: Features = app.features
	for button in [features.add_group_button, features.add_feature_button,
			features.undo_button, features.redo_button, features.duplicate_button,
			features.collapse_button, features.expand_button,
			features.save_button, features.load_button]:
		assert_true(button.pressed.get_connections().size() > 0,
			"%s answers to a press" % button.name)
