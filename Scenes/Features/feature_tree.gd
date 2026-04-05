extends Tree
class_name FeatureTree

signal program_changed()
signal node_visibility_changed()
signal feature_selected(node: Feature)
signal unhandled_key_input(event: InputEvent)

@onready var empty_icon := preload("res://Assets/Icons/Generated/Empty.png")
@onready var group_icon := [preload("res://Assets/Icons/Generated/GroupDisabled.png"), preload("res://Assets/Icons/Generated/GroupEnabled.png")]
@onready var rule_icon := [preload("res://Assets/Icons/Generated/RuleDisabled.png"), preload("res://Assets/Icons/Generated/RuleEnabled.png")]

var root: Feature = null
var items: Dictionary[int, TreeItem] = {}
var editable_item: TreeItem

class PickerTarget:
	var feature: Feature
	func _init(feature_: Feature):
		feature = feature_


### Initialization


func _ready() -> void:
	pass


func load_root_group(root_group: Feature) -> void:
	clear()
	items.clear()
	self.root = root_group
	load_group(null, root, true)
	get_root().set_editable(0, false)


func load_group(parent: TreeItem, group: Feature, enabled: bool):
	var item := create_item(parent)
	assert(item != null, "ERROR: Internal error in Godot's Tree control")
	items[group.pnid] = item

	item.collapsed = group.collapsed
	item.set_metadata(0, group)
	item.set_text(0, group.title)
	item.set_icon(0, group_icon[int(group.enabled)])

	if Application.DEBUG:
		item.set_tooltip_text(0, "[%d]" % group.pnid)

	if not group.is_root:
		var disabled := not group.enabled
		item.add_button(0, empty_icon, -1, true)
		item.add_button(0, Helpers.get_rule_option_icon(Helpers.ICON_ENABLE + int(group.enabled), not group.enabled, group.enabled), 2, false, "Enable this group")
		item.add_button(0, empty_icon, -1, true)
		item.add_button(0, empty_icon, -1, true)
		item.add_button(0, empty_icon, -1, true)
		item.add_button(0, empty_icon, -1, true)
		item.add_button(0, Helpers.get_rule_option_icon(Helpers.ICON_REPEAT, group.repeat, group.enabled), 7, disabled, "Repeat until there is no change")

	for child in group.children:
		if child.is_group:
			load_group(item, child, enabled and group.enabled)
		else:
			load_feature(item, child)


func load_feature(parent: TreeItem, feature: Feature):
	var item := create_item(parent)
	assert(item != null, "ERROR: Internal error in Godot's Tree control")
	items[feature.pnid] = item

	item.set_metadata(0, feature)
	item.set_text(0, feature.title)
	item.set_icon(0, rule_icon[int(feature.enabled)])

	if Application.DEBUG:
		item.set_tooltip_text(0, "[%d]" % feature.pnid)

	var disabled := not feature.enabled
	item.add_button(0, Helpers.render_cell(feature.color).texture, 1, disabled, "Color")
	item.add_button(0, Helpers.get_rule_option_icon(Helpers.ICON_ENABLE + int(feature.enabled), not feature.enabled, feature.enabled), 2, false, "Enable this feature")
	item.add_button(0, Helpers.get_rule_option_icon(Helpers.ICON_INVERT, feature.invert, feature.enabled), 3, disabled, "Invert the match")
	item.add_button(0, Helpers.get_rule_option_icon(Helpers.ICON_SINGLE, feature.single, feature.enabled), 4, disabled, "Single match")
	item.add_button(0, Helpers.get_rule_option_icon(Helpers.ICON_WRAP, feature.wrap_, feature.enabled), 5, disabled, "Wrap around the edges")
	item.add_button(0, Helpers.get_rule_option_icon(Helpers.ICON_RESIZE + feature.resize, feature.resize != 0, feature.enabled), 6, disabled, "Keep the same size, crop or pad")
	item.add_button(0, Helpers.get_rule_option_icon(Helpers.ICON_REPEAT, feature.repeat, feature.enabled), 7, disabled, "Repeat until there is no change")


### Selection


func get_selected_node() -> Feature:
	var item := get_selected()
	if item == null:
		return null
	return item.get_metadata(0) as Feature


func select_root():
	if root != null:
		set_selected(get_root(), 0)


func select_node(node: Feature) -> void:
	if node == null or not items.has(node.pnid):
		return
	var item := items[node.pnid]
	set_selected(item, 0)

	var parent := item.get_parent()
	if parent != null and parent.collapsed:
		parent.collapsed = false


func notify_feature_selected():
	var node := get_selected_node()
	feature_selected.emit(node)


### Group collapse


func collapse_all(collapsed: bool):
	for item in items.values():
		var node = item.get_metadata(0) as Feature
		if node.is_group and not is_same(node, root):
			node.collapsed = collapsed
			item.collapsed = collapsed


func collapse(group: Feature, collapsed: bool) -> void:
	group.collapsed = collapsed
	if items.has(group.pnid):
		items[group.pnid].collapsed = collapsed


### Signal handlers


func _on_item_collapsed(item: TreeItem) -> void:
	var group := item.get_metadata(0) as Feature
	if group == null:
		return
	group.collapsed = item.collapsed
	node_visibility_changed.emit()


func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null:
		return null
	var node := item.get_metadata(0) as Feature
	if node == null or node.is_root:
		return null

	var preview := Button.new()
	preview.icon = item.get_icon(0)
	set_drag_preview(preview)

	return item


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if data is not TreeItem:
		return false

	var dragged_node := data.get_metadata(0) as Feature

	var over_item := get_item_at_position(at_position)
	if over_item == null:
		over_item = get_root()

	var over_node := over_item.get_metadata(0) as Feature
	if over_node == null:
		return false

	if dragged_node.is_group:
		if dragged_node.contains_node_at_any_depth(over_node):
			return false

	drop_mode_flags = DROP_MODE_ON_ITEM | DROP_MODE_INBETWEEN
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if data is not TreeItem:
		return

	var dragged_node := data.get_metadata(0) as Feature

	var over_item := get_item_at_position(at_position)
	if over_item == null:
		over_item = get_root()

	# -1: before item, 0: on item, 1: after item
	var drop_position := get_drop_section_at_position(at_position)
	if drop_position == -100:
		drop_position = 0
		over_item = get_root()

	var over_node := over_item.get_metadata(0) as Feature
	if over_node == null:
		return

	var from_parent := root.find_parent(dragged_node)
	if from_parent == null:
		return

	var from_index := from_parent.find_child(dragged_node)

	if over_node.is_group and drop_position != -1:
		from_parent.children.remove_at(from_index)
		if drop_position == 0:
			over_node.children.append(dragged_node)
		else:
			over_node.children.insert(0, dragged_node)
		collapse(over_node, false)
		program_changed.emit()
		return

	var to_parent := root.find_parent(over_node)
	if to_parent == null:
		return

	var to_index := to_parent.find_child(over_node)
	from_parent.children.remove_at(from_index)
	if drop_position == 1:
		if to_index + 1 < to_parent.child_count():
			to_parent.children.insert(to_index, dragged_node)
		else:
			to_parent.children.append(dragged_node)
	else:
		to_parent.children.insert(to_index, dragged_node)
	collapse(to_parent, false)
	program_changed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	unhandled_key_input.emit(event)


func _on_item_selected() -> void:
	if editable_item != null:
		editable_item.set_editable(0, false)
		editable_item = null
	notify_feature_selected()


func _on_item_activated() -> void:
	start_editing()

func _on_item_icon_double_clicked() -> void:
	start_editing()

func start_editing():
	var item := get_selected()
	if item == null or item.get_parent() == null:
		return
	item.set_editable(0, true)
	editable_item = item
	edit_selected(true)


func _on_button_clicked(item: TreeItem, _column: int, id: int, mouse_button_index: int) -> void:
	var node := item.get_metadata(0) as Feature
	match id:
		1:
			on_output_clicked(node, mouse_button_index)
		2:
			on_enabled_clicked(node)
		3:
			on_invert_clicked(node)
		4:
			on_single_clicked(node)
		5:
			on_wrap_clicked(node)
		6:
			on_resize_clicked(node)
		7:
			on_repeat_clicked(node)


func on_output_clicked(node: Feature, mouse_button_index):
	if not node.is_group:
		if mouse_button_index == 1:
			select_node(node)
			# TODO: Open the color picker
		else:
			node.color = Color.CHOCOLATE
			program_changed.emit()


func _on_picker_completed(target: Variant, selected_color: int, selected_marker: int) -> void:
	if not root:
		return

	var feature: Feature
	if target is PickerTarget:
		feature = target.feature
	else:
		return

	# TODO: Handle color picker result
	program_changed.emit()


func on_enabled_clicked(node: Feature):
	node.enabled = not node.enabled
	if node.is_group and not node.enabled:
		node.collapsed = true
	program_changed.emit()


func on_invert_clicked(node: Feature):
	if not node.is_group:
		node.invert = not node.invert
		program_changed.emit()


func on_single_clicked(node: Feature):
	if not node.is_group:
		node.single = not node.single
		program_changed.emit()


func on_wrap_clicked(node: Feature):
	if not node.is_group:
		node.wrap_ = not node.wrap_
		program_changed.emit()


func on_resize_clicked(node: Feature):
	if not node.is_group:
		node.resize = (node.resize + 1) % 3
		program_changed.emit()


func on_repeat_clicked(node: Feature):
	node.repeat = not node.repeat
	program_changed.emit()


func _on_item_edited() -> void:
	var item = get_edited()
	var node = item.get_metadata(0) as Feature
	node.title = item.get_text(0).strip_edges()
	if len(node.title) > 100:
		node.title = node.title.left(100) + "..."
	program_changed.emit()


func _on_empty_clicked(_click_position: Vector2, _mouse_button_index: int) -> void:
	select_root()
