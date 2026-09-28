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
# The group and rule pictures, shrunk to the glyph size the way the glyphs are,
# so that a row's icon is that size wherever it is read from: the drag preview
# is built from it, and would otherwise come out at the size the picture was
# painted. Each is named after its file, which is what the port reports.
@onready var group_icon := FeatureIcon.shrunk("Icons1-Group", "Icons1-Group")
@onready var rule_icon := FeatureIcon.shrunk("Icons1-Features", "Icons1-Features")

# What a row's icon is drawn at: the size every picture above comes in.
const ICON_WIDTH := FeatureIcon.SIZE

# What a row is greyed out to while its feature is not there at the current
# time, which is when the globe leaves it out as well.
const ABSENT_COLOR := Color(0.5, 0.5, 0.5, 1.0)

# The row tint of a child: the planet's child orange, faint enough to read the
# title through.
const CHILD_TINT := Color(Planet.CHILD_COLOR, 0.25)
const PARENT_TINT := Color(Planet.PARENT_COLOR, 0.25)
const SIBLING_TINT := Color(Planet.SIBLING_COLOR, 0.25)

var root: Feature = null
var items: Dictionary[int, TreeItem] = {}
var editable_item: TreeItem

# The ridges and crusts, by pnid. They have no row: see Feature.is_sea_floor().
var sea_floor: Dictionary[int, Feature] = {}

# The selection when it is one of them, which no row can hold; null otherwise,
# when the selected row is the selection.
var selected_off_tree: Feature = null

# The time the rows are shown for. Rebuilding the tree keeps it, so a reload in
# the middle of an animation does not put the greyed out rows back.
var time: float = 0.0

# The pnids of the rows tinted as children of the selected feature, kept over a
# rebuild the same way.
var coupled: Dictionary[int, Color] = {}


### Initialization


func _ready() -> void:
	pass


# Rebuild the rows from the tree. The rows scroll only when the user scrolls
# them, so the scroll is kept across the rebuild that follows every edit, which
# clear() would otherwise send back to the top (GP-0134).
func load_root_group(root_group: Feature) -> void:
	var bar := _v_scroll()
	var kept := bar.value if bar != null else 0.0
	clear()
	items.clear()
	sea_floor.clear()
	selected_off_tree = null
	self.root = root_group
	load_group(null, root, true)
	_gather_range_ends()
	get_root().set_editable(0, false)
	if bar != null:
		bar.value = kept


# The tree's own vertical scroll bar, an internal child Tree has no setter for.
func _v_scroll() -> VScrollBar:
	for child in get_children(true):
		if child is VScrollBar:
			return child
	return null


func load_group(parent: TreeItem, group: Feature, enabled: bool):
	var item := create_item(parent)
	assert(item != null, "ERROR: Internal error in Godot's Tree control")
	items[group.pnid] = item

	item.collapsed = group.collapsed
	item.set_metadata(0, group)
	item.set_text(0, group.title)
	var folder := FeatureIcon.folder_texture(group.icon)
	item.set_icon(0, folder if folder != null else group_icon)
	item.set_icon_max_width(0, ICON_WIDTH)
	item.set_icon_modulate(0, Color.WHITE if group.enabled else ABSENT_COLOR)

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
		elif child.is_sea_floor():
			sea_floor[child.pnid] = child
		else:
			load_feature(item, child)


func load_feature(parent: TreeItem, feature: Feature):
	var item := create_item(parent)
	assert(item != null, "ERROR: Internal error in Godot's Tree control")
	items[feature.pnid] = item

	item.set_metadata(0, feature)
	item.set_text(0, feature.title)
	# The feature's own glyph when it has one, else its type's picture, else the
	# rule icon as before. Each comes in one form only, so a disabled row greys
	# it the way an absent feature is greyed rather than showing a second picture.
	var glyph := FeatureIcon.texture(feature.icon)
	if glyph == null:
		glyph = FeatureIcon.for_type(feature.feature_type)
	item.set_icon(0, glyph if glyph != null else rule_icon)
	item.set_icon_max_width(0, ICON_WIDTH)
	item.set_icon_modulate(0, Color.WHITE if feature.enabled else ABSENT_COLOR)

	if Application.DEBUG:
		item.set_tooltip_text(0, "[%d]" % feature.pnid)

	item.add_button(0, Helpers.render_cell(feature.color).texture, COLOR_BUTTON,
		not feature.enabled, Helpers.SWATCH_TOOLTIP)
	item.add_button(0, Helpers.get_rule_option_icon(Helpers.ICON_ENABLE + int(feature.enabled), not feature.enabled, feature.enabled), ENABLE_BUTTON, false, "Enable this feature")
	_apply_time(item)
	if coupled.has(feature.pnid):
		item.set_custom_bg_color(0, coupled[feature.pnid])


### Children of the selected feature


# Tint the rows of the given features, each in the tint its relation to the
# selected feature has (Planet.Relation), and clear every other tint.
func mark_related(related: Dictionary) -> void:
	for pnid in coupled:
		if items.has(pnid):
			items[pnid].clear_custom_bg_color(0)
	coupled.clear()
	for node: Feature in related:
		var tint: Color = {Planet.Relation.PARENT: PARENT_TINT,
			Planet.Relation.SIBLING: SIBLING_TINT}.get(related[node], CHILD_TINT)
		coupled[node.pnid] = tint
		if items.has(node.pnid):
			items[node.pnid].set_custom_bg_color(0, tint)


### Time


# Grey out every feature that is not there at the given time. A group is always
# there, so only the leaf rows ever change, and only where the time passes one
# end of a feature's time range: a step of an animation that passes none leaves
# every row as it was, and the thousands of rows of a large document are not
# walked for it (GP-0030).
func refresh_time(time_: float) -> void:
	var passed := _range_ends.is_empty() or _ends_between(time, time_)
	time = time_
	if not passed:
		return
	for item in items.values():
		_apply_time(item)


# Whether an end of some row's time range lies between two times, both
# included, which is where a row can change.
func _ends_between(a: float, b: float) -> bool:
	var at := _range_ends.bsearch(minf(a, b))
	return at < _range_ends.size() and _range_ends[at] <= maxf(a, b)


# Every end of every row's time range, sorted, worked out when the rows are
# built. Empty until then, which refresh_time() takes as "walk every row".
var _range_ends := PackedFloat64Array()


func _gather_range_ends() -> void:
	var ends := {}
	for item in items.values():
		var node := item.get_metadata(0) as Feature
		if node != null and not node.is_group:
			ends[float(node.time_range.x)] = true
			ends[float(node.time_range.y)] = true
	_range_ends = PackedFloat64Array(ends.keys())
	_range_ends.sort()


# Grey the row out while its feature is not there. A row is only touched when
# that changes: on every frame of an animation a document of thousands of rows
# would otherwise set every one of them again (GP-0030).
func _apply_time(item: TreeItem) -> void:
	var node := item.get_metadata(0) as Feature
	var absent := node != null and not node.exists_at(time)
	if absent == (item.get_custom_color(0) == ABSENT_COLOR):
		return
	if absent:
		item.set_custom_color(0, ABSENT_COLOR)
	else:
		item.clear_custom_color(0)


### Selection


func get_selected_node() -> Feature:
	if selected_off_tree != null:
		return selected_off_tree
	var item := get_selected()
	if item == null:
		return null
	return item.get_metadata(0) as Feature


# Whether the node is one the tree can select: a row, or a ridge or crust.
func holds_node(pnid: int) -> bool:
	return items.has(pnid) or sea_floor.has(pnid)


func select_root():
	if root != null:
		selected_off_tree = null
		set_selected(get_root(), 0)


# Select a node by its pnid, so a node of a tree that has since been cloned, by
# an undo or a reload, finds the one standing in for it. A ridge or crust is
# selected with no row selected, and the selection is announced here, since no
# row does it. A row chosen somewhere other than the tree, a click on the planet
# say, is scrolled into view when it is out of it; `scroll` false keeps the tree
# where it is, which is what a rebuild wants.
func select_node(node: Feature, scroll := true) -> void:
	if node == null:
		return
	if sea_floor.has(node.pnid):
		selected_off_tree = sea_floor[node.pnid]
		deselect_all()
		notify_feature_selected()
		return
	if not items.has(node.pnid):
		return
	selected_off_tree = null
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
	if scroll:
		scroll_to_item(item, false)


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
	selected_off_tree = null
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
