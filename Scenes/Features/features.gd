extends VBoxContainer
class_name Features

const CLIPBOARD_MARKER := "middle-earth"
const MAX_UNDO_BUFFER_SIZE := 100

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

var root: Feature
var versions: Array[Feature] = []
var next_version: int = 0


func _ready() -> void:
	root = Feature.create_group("Planet")
	root.is_root = true
	save_version()
	feature_tree.load_root_group(root)
	feature_tree.select_root()
	update_button_availability()


### Undo/Redo


func save_version() -> void:
	# Remove any redo versions
	while len(versions) > next_version:
		versions.pop_back()
	# Record the current version
	versions.append(root.clone())
	next_version += 1
	# Remove the oldest version if the buffer is full
	while next_version > MAX_UNDO_BUFFER_SIZE:
		versions.pop_front()
		next_version -= 1


func undo() -> void:
	if next_version > 1:
		next_version -= 1
		root = versions[next_version - 1].clone()
		reload()


func redo() -> void:
	if next_version < len(versions):
		next_version += 1
		root = versions[next_version - 1].clone()
		reload()


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
	undo_button.disabled = next_version < 2
	redo_button.disabled = next_version >= len(versions)
	cut_button.disabled = is_root_selected
	duplicate_button.disabled = is_root_selected
	detect_clipboard_content()


func detect_clipboard_content() -> void:
	var clipboard := DisplayServer.clipboard_get()
	paste_button.disabled = not (CLIPBOARD_MARKER in clipboard)


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
	save_version()
	reload()
	feature_tree.select_node(group)
	feature_tree.collapse(parent, false)


func add_new_group_at(parent: Feature, index: int) -> void:
	var group := Feature.create_group()
	parent.children.insert(index, group)
	save_version()
	reload()
	feature_tree.select_node(group)
	feature_tree.collapse(parent, false)


func add_new_feature(parent: Feature) -> void:
	var feature := Feature.create_feature()
	parent.children.append(feature)
	save_version()
	reload()
	feature_tree.select_node(feature)
	feature_tree.collapse(parent, false)


func add_new_feature_at(parent: Feature, index: int) -> void:
	var feature := Feature.create_feature()
	parent.children.insert(index, feature)
	save_version()
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
	save_version()

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
	save_version()
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
	data["application"] = CLIPBOARD_MARKER
	var json := JSON.stringify(data)
	DisplayServer.clipboard_set(json)
	update_button_availability()


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

	if data.get("application", "") != CLIPBOARD_MARKER:
		return

	var node := Feature.from_json(data)
	if index < 0:
		parent.children.append(node)
	else:
		parent.children.insert(index, node)
	save_version()

	reload()
	feature_tree.select_node(node)
	feature_tree.collapse(parent, false)


### Collapse / Expand


func _on_collapse_pressed() -> void:
	feature_tree.collapse_all(true)


func _on_expand_pressed() -> void:
	feature_tree.collapse_all(false)


### Save / Load


func _on_save_pressed() -> void:
	DisplayServer.file_dialog_show(
		"Save",
		Config.get_last_directory(),
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
		PackedStringArray(["*.middle-earth ; Middle-Earth Files"]),
		_on_save_dialog_callback,
	)


func _on_save_dialog_callback(status: bool, selected_paths: PackedStringArray, _selected_filter: int) -> void:
	if not status or selected_paths.is_empty():
		return
	var path := selected_paths[0]
	if not path.ends_with(".middle-earth"):
		path += ".middle-earth"
	Config.set_last_directory_from_file(path)
	_save_to_file(path)


func _save_to_file(path: String) -> void:
	var data := {
		"application": CLIPBOARD_MARKER,
		"version": Application.VERSION,
		"features": root.to_json(),
	}
	var json := JSON.stringify(data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open file for writing: %s" % path)
		return
	file.store_string(json)


func _on_load_pressed() -> void:
	DisplayServer.file_dialog_show(
		"Open",
		Config.get_last_directory(),
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.middle-earth ; Middle-Earth Files"]),
		_on_load_dialog_callback,
	)


func _on_load_dialog_callback(status: bool, selected_paths: PackedStringArray, _selected_filter: int) -> void:
	if not status or selected_paths.is_empty():
		return
	Config.set_last_directory_from_file(selected_paths[0])
	_load_from_file(selected_paths[0])


func _load_from_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file for reading: %s" % path)
		return

	var text := file.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("Failed to parse JSON: %s" % json.get_error_message())
		return

	var data: Variant = json.data
	if data is not Dictionary:
		push_error("Invalid file format: root is not a dictionary")
		return
	if data.get("application", "") != CLIPBOARD_MARKER:
		push_error("Invalid file format: not a Middle-Earth file")
		return

	data = migrate(data)

	var loaded_root := Feature.from_json(data["features"])
	loaded_root.is_root = true
	root = loaded_root

	# Reset the undo buffer
	versions.clear()
	next_version = 0
	save_version()

	reload()
	feature_tree.select_root()


static func migrate(data: Dictionary) -> Dictionary:
	# No format migrations while the major version is 0.
	# Once version 1.0.0 is reached, add migrations here for each file format change.
	return data


### Keyboard shortcuts


func _on_feature_tree_unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed:
		return

	var key_event := event as InputEventKey

	if key_event.keycode == KEY_DELETE:
		var selected := feature_tree.get_selected_node()
		delete_node(selected)
		get_viewport().set_input_as_handled()

	elif key_event.ctrl_pressed:
		match key_event.keycode:
			KEY_Z:
				undo()
				get_viewport().set_input_as_handled()
			KEY_Y:
				redo()
				get_viewport().set_input_as_handled()
			KEY_C:
				_on_copy_pressed()
				get_viewport().set_input_as_handled()
			KEY_X:
				_on_cut_pressed()
				get_viewport().set_input_as_handled()
			KEY_V:
				_on_paste_pressed()
				get_viewport().set_input_as_handled()
			KEY_D:
				_on_duplicate_pressed()
				get_viewport().set_input_as_handled()
			KEY_S:
				_on_save_pressed()
				get_viewport().set_input_as_handled()
			KEY_O:
				_on_load_pressed()
				get_viewport().set_input_as_handled()


### Tree signals


func _on_feature_tree_program_changed() -> void:
	save_version()
	reload()


func _on_feature_tree_feature_selected(_node: Feature) -> void:
	update_button_availability()
