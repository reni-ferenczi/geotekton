extends Tree
class_name FeatureTree

signal program_changed()
signal feature_selected(node: Feature)

# The colour swatch of a row was clicked: the feature is selected by now and the
# Properties panel is asked to open its picker.
signal color_requested()

# The two buttons a row carries, by the id they answer clicks with.
const COLOR_BUTTON := 1
const ENABLE_BUTTON := 2

@onready var empty_icon := preload("res://Assets/Icons/Generated/Empty.png")
@onready var group_icon := [preload("res://Assets/Icons/Generated/GroupDisabled.png"), preload("res://Assets/Icons/Generated/GroupEnabled.png")]
@onready var rule_icon := [preload("res://Assets/Icons/Generated/RuleDisabled.png"), preload("res://Assets/Icons/Generated/RuleEnabled.png")]

# What a row is greyed out to while its feature is not there at the current
# time, which is when the globe leaves it out as well.
const ABSENT_COLOR := Color(0.5, 0.5, 0.5, 1.0)

# The row tint of a child: the planet's child orange, faint enough to read the
# title through.
const CHILD_TINT := Color(Planet.CHILD_COLOR, 0.25)

var root: Feature = null
var items: Dictionary[int, TreeItem] = {}
var editable_item: TreeItem

# The time the rows are shown for. Rebuilding the tree keeps it, so a reload in
# the middle of an animation does not put the greyed out rows back.
var time: float = 0.0

# The pnids of the rows tinted as children of the selected feature, kept over a
# rebuild the same way.
var coupled: Dictionary[int, bool] = {}


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
		# The spacer lines the enable button up with the one on a feature row,
		# which has the colour swatch in front of it.
		item.add_button(0, empty_icon, -1, true)
		item.add_button(0, Helpers.get_rule_option_icon(Helpers.ICON_ENABLE + int(group.enabled), not group.enabled, group.enabled), ENABLE_BUTTON, false, "Enable this group")

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
	# The feature's own glyph when it has one, else the rule icon as before.
	# A glyph comes in one form only, so a disabled row greys it the way an
	# absent feature is greyed rather than showing a second picture.
	var glyph := FeatureIcon.texture(feature.icon)
	item.set_icon(0, glyph if glyph != null else rule_icon[int(feature.enabled)])
	item.set_icon_modulate(0, Color.WHITE if feature.enabled or glyph == null else ABSENT_COLOR)

	if Application.DEBUG:
		item.set_tooltip_text(0, "[%d]" % feature.pnid)

	item.add_button(0, Helpers.render_cell(feature.color).texture, COLOR_BUTTON,
		not feature.enabled, Helpers.SWATCH_TOOLTIP)
	item.add_button(0, Helpers.get_rule_option_icon(Helpers.ICON_ENABLE + int(feature.enabled), not feature.enabled, feature.enabled), ENABLE_BUTTON, false, "Enable this feature")
	_apply_time(item)
	if coupled.has(feature.pnid):
		item.set_custom_bg_color(0, CHILD_TINT)


### Children of the selected feature


# Tint the rows of the given features and clear every other tint.
func mark_children(nodes: Array[Feature]) -> void:
	for pnid in coupled:
		if items.has(pnid):
			items[pnid].clear_custom_bg_color(0)
	coupled.clear()
	for node in nodes:
		coupled[node.pnid] = true
		if items.has(node.pnid):
			items[node.pnid].set_custom_bg_color(0, CHILD_TINT)


### Time


# Grey out every feature that is not there at the given time. A group is always
# there, so only the leaf rows ever change.
func refresh_time(time_: float) -> void:
	time = time_
	for item in items.values():
		_apply_time(item)


func _apply_time(item: TreeItem) -> void:
	var node := item.get_metadata(0) as Feature
	if node == null or node.exists_at(time):
		item.clear_custom_color(0)
	else:
		item.set_custom_color(0, ABSENT_COLOR)


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

	# Expand all ancestor groups before selecting
	var ancestor := item.get_parent()
	while ancestor != null:
		if ancestor.collapsed:
			ancestor.collapsed = false
		ancestor = ancestor.get_parent()

	# Deselect current item first to force the Tree to update visually
	deselect_all()
	item.select(0)
	scroll_to_item(item, true)


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


func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null:
		return null
	var node := item.get_metadata(0) as Feature
	if node == null or node.is_root:
		return null

	# The Tree clears the flags when a drop ends, so they are set again for
	# every drag, here, before the pointer first moves over a row.
	drop_mode_flags = DROP_MODE_ON_ITEM | DROP_MODE_INBETWEEN

	var preview := Button.new()
	preview.icon = item.get_icon(0)
	set_drag_preview(preview)

	return item


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if data is not TreeItem:
		return false

	var dragged_node := data.get_metadata(0) as Feature
	var over_node := _node_at(at_position)
	if over_node == null:
		return false

	# A group cannot go into itself or anything under it.
	return not (dragged_node.is_group and dragged_node.contains_node_at_any_depth(over_node))


# Where a drop puts the dragged node, by the part of the row it lands on:
# - the band above a row: before that row, as its sibling;
# - the band below a row: after that row, as its sibling, whether the row is a
#   leaf, a collapsed group or an expanded group;
# - the middle of a group row: into that group, at the end;
# - the middle of a leaf row: after that leaf;
# - empty space, or anywhere on the root row: at the end of the root.
func _drop_data(at_position: Vector2, data: Variant) -> void:
	if data is not TreeItem:
		return

	var dragged_node := data.get_metadata(0) as Feature
	var over_node := _node_at(at_position)
	if over_node == null or over_node == dragged_node:
		return

	var from_parent := root.find_parent(dragged_node)
	if from_parent == null:
		return

	# -1: the band above the row, 0: its middle, 1: the band below it, and 2 the
	# same band on a row that has children, which Godot means as "first child"
	# and this tree takes as "after the row", like 1.
	var section := get_drop_section_at_position(at_position)
	var into := over_node.is_root or (over_node.is_group and section == 0)
	var to_parent := over_node if into else root.find_parent(over_node)
	if to_parent == null:
		return

	# The index is taken after the removal, so "after" is after the row even
	# when the dragged node sat above it in the same group.
	from_parent.children.erase(dragged_node)
	var to_index := to_parent.child_count()
	if not into:
		to_index = to_parent.find_child(over_node) + (0 if section == -1 else 1)
	to_parent.children.insert(to_index, dragged_node)
	collapse(to_parent, false)
	program_changed.emit()


# The node of the row under a point, the root when the point is below the rows.
func _node_at(at_position: Vector2) -> Feature:
	var item := get_item_at_position(at_position)
	if item == null:
		return root
	return item.get_metadata(0) as Feature


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
		COLOR_BUTTON:
			on_output_clicked(node, mouse_button_index)
		ENABLE_BUTTON:
			on_enabled_clicked(node)


func on_output_clicked(node: Feature, mouse_button_index):
	if not node.is_group:
		if mouse_button_index == MOUSE_BUTTON_LEFT:
			# The colour is picked in the Properties panel, which follows the
			# selection, so the swatch gets the feature selected and then asks
			# the panel to open the picker where the colour is already shown.
			select_node(node)
			color_requested.emit()
		else:
			node.color = FeatureType.color(node.feature_type)
			program_changed.emit()


func on_enabled_clicked(node: Feature):
	node.enabled = not node.enabled
	if node.is_group and not node.enabled:
		node.collapsed = true
	program_changed.emit()


func _on_item_edited() -> void:
	var item = get_edited()
	var node = item.get_metadata(0) as Feature
	node.title = Feature.clamp_title(item.get_text(0))
	program_changed.emit()


func _on_empty_clicked(_click_position: Vector2, _mouse_button_index: int) -> void:
	select_root()
