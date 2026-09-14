extends VBoxContainer
class_name Features

# Which of the edit commands can be run has changed. The toolbar is updated
# here; the Edit menus carry the same commands and follow this.
signal commands_changed()


@onready var feature_tree: FeatureTree = $FeatureTree
@onready var add_group_button: Button = $PanelContainer/Buttons/AddGroup
@onready var add_feature_button: Button = $PanelContainer/Buttons/AddFeature
@onready var undo_button: Button = $PanelContainer/Buttons/Undo
@onready var redo_button: Button = $PanelContainer/Buttons/Redo
@onready var copy_button: Button = $PanelContainer/Buttons/Copy
@onready var cut_button: Button = $PanelContainer/Buttons/Cut
@onready var paste_button: Button = $PanelContainer/Buttons/Paste
@onready var duplicate_button: Button = $PanelContainer/Buttons/Duplicate
@onready var collapse_button: Button = $PanelContainer/Buttons/Collapse
@onready var expand_button: Button = $PanelContainer/Buttons/Expand
@onready var save_button: Button = $PanelContainer/Buttons/Save
@onready var load_button: Button = $PanelContainer/Buttons/Load

# The open document, owned by Application and set through attach().
var document: Document

# The feature tree of the open document.
var root: Feature:
	get:
		return document.root


# Take the document to edit and show its tree. Called once by Application.
func attach(document_: Document) -> void:
	document = document_
	document.root_replaced.connect(_on_root_replaced)
	document.state_changed.connect(update_button_availability)
	_on_root_replaced()


func _on_root_replaced(_same_document: bool = false) -> void:
	var selected := feature_tree.get_selected_node()
	reload()
	# reload() puts the selection back by pnid, which a clone keeps, so undo and
	# redo stay on the feature that was selected. A file that was just opened
	# holds none of the old ids, and then the root is the selection.
	if selected == null or not feature_tree.items.has(selected.pnid):
		feature_tree.select_root()


### Undo/Redo


func undo() -> void:
	document.undo()


func redo() -> void:
	document.redo()


func _on_undo_pressed() -> void:
	undo()


func _on_redo_pressed() -> void:
	redo()


### Reload


func reload() -> void:
	var selected := feature_tree.get_selected_node()
	feature_tree.load_root_group(root)
	feature_tree.select_node(selected)
	update_button_availability()


func update_button_availability() -> void:
	var selected := feature_tree.get_selected_node()
	var is_root_selected := selected == null or selected.is_root
	undo_button.disabled = not document.can_undo()
	redo_button.disabled = not document.can_redo()
	cut_button.disabled = is_root_selected
	duplicate_button.disabled = is_root_selected
	detect_clipboard_content()
	commands_changed.emit()


func detect_clipboard_content() -> void:
	var clipboard := DisplayServer.clipboard_get()
	paste_button.disabled = not (Document.APPLICATION in clipboard)


### Add group and feature


func _on_add_group_pressed() -> void:
	var selected := feature_tree.get_selected_node()
	if selected == null:
		selected = root
	if selected.is_group:
		add_new_group(selected)
	else:
		var parent := root.find_parent(selected)
		if parent != null:
			var index := parent.find_child(selected)
			add_new_group_at(parent, index + 1)


func _on_add_feature_pressed() -> void:
	var selected := feature_tree.get_selected_node()
	if selected == null:
		selected = root
	if selected.is_group:
		add_new_feature(selected)
	else:
		var parent := root.find_parent(selected)
		if parent != null:
			var index := parent.find_child(selected)
			add_new_feature_at(parent, index + 1)


func add_new_group(parent: Feature) -> void:
	var group := Feature.create_group()
	parent.children.append(group)
	document.record()
	reload()
	feature_tree.select_node(group)
	feature_tree.collapse(parent, false)


func add_new_group_at(parent: Feature, index: int) -> void:
	var group := Feature.create_group()
	parent.children.insert(index, group)
	document.record()
	reload()
	feature_tree.select_node(group)
	feature_tree.collapse(parent, false)


# The age a feature added now starts at: the one the timeline is showing. It
# then exists until the present, which is the direction the work runs in. A
# feature added at 0 Ma is there at the present only, which is what the rule
# says; the From box changes it. See Docs/Time.md.
func _new_time_range() -> Vector2i:
	return Vector2i(0, int(round(document.current_time)))


func add_new_feature(parent: Feature) -> void:
	var feature := Feature.create_feature("Feature", FeatureType.NONE_COLOR, _new_time_range())
	parent.children.append(feature)
	document.record()
	reload()
	feature_tree.select_node(feature)
	feature_tree.collapse(parent, false)


func add_new_feature_at(parent: Feature, index: int) -> void:
	var feature := Feature.create_feature("Feature", FeatureType.NONE_COLOR, _new_time_range())
	parent.children.insert(index, feature)
	document.record()
	reload()
	feature_tree.select_node(feature)
	feature_tree.collapse(parent, false)


### Delete


func delete_node(node: Feature) -> void:
	if node == null or node.is_root:
		return

	var parent := root.find_parent(node)
	if parent == null:
		return

	var index := parent.find_child(node)
	parent.children.remove_at(index)
	document.record()

	# Select next sibling, previous sibling, or parent
	if index < parent.child_count():
		reload()
		feature_tree.select_node(parent.children[index])
	elif index > 0:
		reload()
		feature_tree.select_node(parent.children[index - 1])
	else:
		reload()
		feature_tree.select_node(parent)


### Duplicate


func _on_duplicate_pressed() -> void:
	var selected := feature_tree.get_selected_node()
	duplicate_node(selected)


func duplicate_node(node: Feature) -> void:
	if node == null or node.is_root:
		return

	var parent := root.find_parent(node)
	if parent == null:
		return

	var index := parent.find_child(node)
	var duplicated := node.duplicate()
	parent.children.insert(index + 1, duplicated)
	document.record()
	reload()
	feature_tree.select_node(duplicated)


### Copy / Cut / Paste


func _on_copy_pressed() -> void:
	var selected := feature_tree.get_selected_node()
	copy(selected)


func _on_cut_pressed() -> void:
	var selected := feature_tree.get_selected_node()
	if selected == null or selected.is_root:
		return
	copy(selected)
	delete_node(selected)


func _on_paste_pressed() -> void:
	var selected := feature_tree.get_selected_node()
	if selected == null:
		selected = root
	if selected.is_group:
		paste(selected)
	else:
		var parent := root.find_parent(selected)
		if parent != null:
			var index := parent.find_child(selected)
			paste(parent, index + 1)


func copy(node: Feature) -> void:
	if node == null or node.is_root:
		return
	var data: Variant = node.to_json()
	data["application"] = Document.APPLICATION
	var json := JSON.stringify(data)
	DisplayServer.clipboard_set(json)
	update_button_availability()
	# Windows can answer a read with the previous clipboard for a moment after a
	# write, which would leave Paste greyed out on what was just copied, so ask
	# again once this frame is over.
	update_button_availability.call_deferred()


func paste(parent: Feature, index: int = -1) -> void:
	var clipboard := DisplayServer.clipboard_get()
	if clipboard.is_empty():
		return

	var json = JSON.new()
	if json.parse(clipboard) != OK:
		return

	var data: Variant = json.data
	if data is not Dictionary:
		return

	if data.get("application", "") != Document.APPLICATION:
		return

	# duplicate() rather than the node as it was read: the clipboard carries the
	# ids of the feature it was copied from, and a paste is another feature.
	var node := Feature.from_json(data).duplicate()
	if index < 0:
		parent.children.append(node)
	else:
		parent.children.insert(index, node)
	document.record()

	reload()
	feature_tree.select_node(node)
	feature_tree.collapse(parent, false)


### Collapse / Expand


func _on_collapse_pressed() -> void:
	feature_tree.collapse_all(true)


func _on_expand_pressed() -> void:
	feature_tree.collapse_all(false)


### Tree signals


func _on_feature_tree_program_changed() -> void:
	document.record()
	# The tree emits this from inside its own mouse handling, where Godot's Tree
	# refuses to be cleared or have items created, so rebuilding it right here
	# leaves the panel empty. Clicking under the rows while a row is being
	# renamed is one way in: the click closes the cell editor and lands the
	# rename here, still inside the event. Wait until the control is done with it.
	reload.call_deferred()


func _on_feature_tree_feature_selected(_node: Feature) -> void:
	update_button_availability()
