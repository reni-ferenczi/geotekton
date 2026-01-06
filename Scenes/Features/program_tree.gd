extends Tree
class_name ProgramTree

signal program_changed()
signal node_visibility_changed()
signal rule_selected(node: ProgNode)
signal unhandled_key_input(event: InputEvent)

@onready var empty_icon := preload("res://Assets/Icons/Generated/Empty.png")
@onready var group_icon := [preload("res://Assets/Icons/Generated/GroupDisabled.png"), preload("res://Assets/Icons/Generated/GroupEnabled.png")]
@onready var rule_icon := [preload("res://Assets/Icons/Generated/RuleDisabled.png"), preload("res://Assets/Icons/Generated/RuleEnabled.png")]

@onready var picker := get_tree().root.get_node("/root/Application/Picker") as Picker

var root: Group = null
var items: Dictionary[int, TreeItem] = {}
var editable_item: TreeItem

class PickerTarget:
	var rule: Rule
	func _init(rule_: Rule):
		rule = rule_


### Initialization


func _ready() -> void:
	picker.connect("completed", _on_picker_completed)


func load_root_group(root_group: Group) -> void:
	clear()
	items.clear()
	self.root = root_group
	load_group(null, root, true)
	get_root().set_editable(0, false)


func load_group(parent: TreeItem, group: Group, enabled: bool):
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
		var has_permutations := not group.permutations.is_empty()
		item.add_button(0, empty_icon, -1, true)
		item.add_button(0, IconProvider.get_rule_option_icon(IconProvider.ICON_ENABLE + int(group.enabled), not group.enabled, group.enabled), 2, false, "Enable this group")
		item.add_button(0, IconProvider.get_rule_option_icon(IconProvider.ICON_PERMUTATION, true, group.enabled) if has_permutations else empty_icon, 3, disabled, "This group has permutations (edit them below)" if has_permutations else "This group has no permutations (add them below)")
		item.add_button(0, empty_icon, -1, true)
		item.add_button(0, empty_icon, -1, true)
		item.add_button(0, empty_icon, -1, true)
		item.add_button(0, IconProvider.get_rule_option_icon(IconProvider.ICON_REPEAT, group.repeat, group.enabled), 7, disabled, "Repeat until there is no change")

	for child in group.children:
		if child is Group:
			load_group(item, child, enabled and group.enabled)
		else:
			load_rule(item, child)
	

func load_rule(parent: TreeItem, rule: Rule):
	var item := create_item(parent)
	assert(item != null, "ERROR: Internal error in Godot's Tree control")
	items[rule.pnid] = item
	
	item.set_metadata(0, rule)	
	item.set_text(0, rule.title)
	item.set_icon(0, rule_icon[int(rule.enabled)])
	
	if Application.DEBUG:
		item.set_tooltip_text(0, "[%d]" % rule.pnid)
	
	var disabled := not rule.enabled
	item.add_button(0, GraphicsProvider.render_cell(32, rule.output_color, rule.output_marker).texture, 1, disabled, "Output color and marker to overwrite the target with")
	item.add_button(0, IconProvider.get_rule_option_icon(IconProvider.ICON_ENABLE + int(rule.enabled), not rule.enabled, rule.enabled), 2, false, "Enable this rule")
	item.add_button(0, IconProvider.get_rule_option_icon(IconProvider.ICON_INVERT, rule.invert, rule.enabled), 3, disabled, "Invert the match")
	item.add_button(0, IconProvider.get_rule_option_icon(IconProvider.ICON_SINGLE, rule.single, rule.enabled), 4, disabled, "Single match")
	item.add_button(0, IconProvider.get_rule_option_icon(IconProvider.ICON_WRAP, rule.wrap_, rule.enabled), 5, disabled, "Wrap around the edges")
	item.add_button(0, IconProvider.get_rule_option_icon(IconProvider.ICON_RESIZE + rule.resize, rule.resize != 0, rule.enabled), 6, disabled, "Keep the same size, crop or pad the grid")
	item.add_button(0, IconProvider.get_rule_option_icon(IconProvider.ICON_REPEAT, rule.repeat, rule.enabled), 7, disabled, "Repeat until there is no change")


### Selection


func get_selected_node() -> ProgNode:
	var item := get_selected()
	return item.get_metadata(0) as ProgNode


func select_root():
	if root != null:
		set_selected(get_root(), 0)


func select_node(node: ProgNode) -> void:
	var item := items[node.pnid]
	set_selected(item, 0)
	
	var parent := item.get_parent()
	if parent != null and parent.collapsed:
		parent.collapsed = false


func notify_rule_selected():
	var node := get_selected_node()
	rule_selected.emit(node)


### Group collapse


func collapse_all(collapsed: bool):
	for item in items.values():
		var node = item.get_metadata(0) as ProgNode
		if node is Group and not is_same(node, root):
			node.collapsed = collapsed
			item.collapsed = collapsed


func collapse(group: Group, collapsed: bool) -> void:
	group.collapsed = collapsed
	items[group.pnid].collapsed = collapsed


### Signal handlers


func _on_item_collapsed(item: TreeItem) -> void:
	var group := item.get_metadata(0) as Group
	if group == null:
		# It caused a crash while randomly clicking on the tree
		return
	group.collapsed = item.collapsed
	node_visibility_changed.emit()


func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null:
		return null
		
	var preview := Button.new()
	preview.icon = item.get_icon(0)
	set_drag_preview(preview)
	
	return item


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if data is not TreeItem:
		return false
		
	var dragged_node := data.get_metadata(0) as ProgNode
		
	var over_item := get_item_at_position(at_position)
	if over_item == null:
		over_item = get_root()
	
	var over_node := over_item.get_metadata(0) as ProgNode
	if over_node == null:
		return false
		
	if dragged_node is Group:
		if dragged_node.contains_node_at_any_depth(over_node):
			return false
		
	drop_mode_flags = DROP_MODE_ON_ITEM | DROP_MODE_INBETWEEN
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if data is not TreeItem:
		return
		
	var dragged_node := data.get_metadata(0) as ProgNode
		
	var over_item := get_item_at_position(at_position)
	if over_item == null:
		over_item = get_root()
		
	# -1: before item, 0: on item, 1: after item
	var drop_position := get_drop_section_at_position(at_position)
	if drop_position == -100:
		drop_position = 0
		over_item = get_root()
		
	var over_node := over_item.get_metadata(0) as ProgNode
	if over_node == null:
		return
		
	var from_parent := root.find_parent(dragged_node)
	if from_parent == null:
		return

	var from_index := from_parent.find_child(dragged_node)

	if over_node is Group and drop_position != -1:
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
	notify_rule_selected()


func _on_item_activated() -> void:
	start_editing()

func _on_item_icon_double_clicked() -> void:
	start_editing()

func start_editing():
	var item := get_selected()
	if item.get_parent() == null:
		return
	item.set_editable(0, true)
	editable_item = item	
	edit_selected(true)


func _on_button_clicked(item: TreeItem, _column: int, id: int, mouse_button_index: int) -> void:
	var node := item.get_metadata(0) as ProgNode
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


func on_output_clicked(node: ProgNode, mouse_button_index):
	if node is Rule:
		if mouse_button_index == 1:
			select_node(node)
			picker.prepare_picking_cell(PickerTarget.new(node), true)
			var item := items[node.pnid]
			var button_rect := get_item_area_rect(item, 0, 0)
			picker.open_popup(self, button_rect.position + button_rect.size)
			
		else:
			if node.output_marker == 0xff or Input.is_key_pressed(KEY_CTRL):
				node.output_color = 0xf
			else:
				node.output_marker = 0xff
			program_changed.emit()


func _on_picker_completed(target: Variant, selected_color: int, selected_marker: int) -> void:
	if not root:
		return
		
	var rule: Rule
	if target is PickerTarget:
		rule = target.rule
	else:
		return
	
	if selected_color == 0xb:
		rule.output_marker = selected_marker
		program_changed.emit()
	else:
		rule.output_color = selected_color
		program_changed.emit()
	

func on_enabled_clicked(node: ProgNode):
	node.enabled = not node.enabled
	if node is Group and not node.enabled:
		node.collapsed = true
	program_changed.emit()
	

func on_invert_clicked(node: ProgNode):
	if node is Rule:
		node.invert = not node.invert
		program_changed.emit()


func on_single_clicked(node: ProgNode):
	if node is Rule:
		node.single = not node.single
		program_changed.emit()


func on_wrap_clicked(node: ProgNode):
	if node is Rule:
		node.wrap_ = not node.wrap_
		program_changed.emit()


func on_resize_clicked(node: ProgNode):
	if node is Rule:
		node.resize = (node.resize + 1) % 3
		program_changed.emit()


func on_repeat_clicked(node: ProgNode):
	node.repeat = not node.repeat
	program_changed.emit()


func _on_item_edited() -> void:
	var item = get_edited()
	var node = item.get_metadata(0) as ProgNode
	node.title = item.get_text(0).strip_edges()
	if len(node.title) > 100:
		node.title = node.title.left(100) + "..."
	program_changed.emit()


func _on_empty_clicked(_click_position: Vector2, _mouse_button_index: int) -> void:
	select_root()
