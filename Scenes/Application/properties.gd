extends PanelContainer
class_name Properties

# The Properties panel: what the feature tree has selected, laid out so it can
# be edited. A leaf feature shows its name, type, colour, enabled switch, time
# range, what its geometry holds and how many keyframes it has; a group shows
# the name, the switch and its style: how the features under it are colored.
# The root group's style is edited in the View settings dialog instead. See
# Docs/Properties.md.
#
# The panel never writes to a feature itself. Every edit goes through the
# document, which validates it and records one undo version, and an edit the
# document refuses is reported through `rejected` and taken back on screen.

# An edit went through: the tree row and the globe need to catch up.
signal edited()

# The colour picker is being dragged: the globe needs to catch up, but nothing
# has been recorded yet, so the tree does not.
signal previewed()

# A color or an opacity went through. Only the colors need to reach the globe,
# which is cheaper than what `edited` asks for.
signal recolored()

# An edit was refused, with the message saying why.
signal rejected(message: String)

# The oldest age either end of a time range can name.
const TIME_LIMIT := int(Document.MAX_TIME)

# The columns of the section table of a line topology: the feature the section
# runs along, the vertices of it the section covers, counted from one, and which
# way round it is walked.
const SECTION_COLUMNS = ["Feature", "From", "To", "Way"]

# A section whose feature can no longer be found, or cannot be followed at the
# current time, is drawn in this rather than dropped, so a topology says what it
# has lost instead of quietly shrinking.
const BROKEN_SECTION_COLOR = Color(0.9, 0.45, 0.4, 1.0)

# How wide the panel is, whatever it happens to be showing.
const CONTENT_WIDTH := 280

# The open document, set by Application through attach().
var document: Document

# What is on show, null while nothing is selected.
var node: Feature = null

# True while the widgets are being filled from a feature, so the signals they
# emit on the way are not mistaken for someone editing them.
var _filling: bool = false

var placeholder: Label
var name_edit: LineEdit
var type_selector: OptionButton
var style_selector: OptionButton
var palette_selector: OptionButton
var color_button: ColorPickerButton
var opacity_spin: SpinBox
var enabled_check: CheckBox
var from_spin: SpinBox
var to_spin: SpinBox
var geometry_label: Label
var keyframe_count: Label
var key_button: Button
var delete_key_button: Button
var sections: Tree
var reverse_button: Button
var remove_section_button: Button

# Every row of the form, each a label and the control beside it, and whether a
# group and a feature have it.
var _rows: Array[Dictionary] = []
# The section table and its buttons, which only a line topology has.
var _topology_boxes: Array[Control] = []
# The keyframe row, label and all, which a feature holding vertices of its own
# has. A topology has no motion of its own, and a group carries none.
var _motion_boxes: Array[Control] = []


func _ready() -> void:
	_build()
	show_node(null)


func attach(document_: Document) -> void:
	document = document_


### Layout


func _build() -> void:
	# The panel keeps one width whatever is selected. Its content would otherwise
	# set a minimum of its own, the split container would honour it, and the
	# planet view beside it would resize every time the selection changed.
	custom_minimum_size = Vector2(CONTENT_WIDTH, 0)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 8)
	add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Content"
	margin.add_child(box)

	placeholder = Label.new()
	placeholder.name = "Placeholder"
	placeholder.text = "Nothing is selected."
	placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(placeholder)

	var form := GridContainer.new()
	form.name = "Form"
	form.columns = 2
	box.add_child(form)

	name_edit = LineEdit.new()
	name_edit.name = "Name"
	name_edit.text_submitted.connect(func(_text: String) -> void: _commit_name())
	name_edit.focus_exited.connect(_commit_name)
	_row(form, "Name", name_edit, true)

	type_selector = OptionButton.new()
	type_selector.name = "Type"
	for type_id in FeatureType.CATALOG:
		type_selector.add_item(FeatureType.label(type_id))
		type_selector.set_item_metadata(type_selector.item_count - 1, type_id)
	type_selector.item_selected.connect(_on_type_selected)
	_row(form, "Type", type_selector)

	style_selector = _selector("Style")
	for mode_id in Styling.MODES:
		style_selector.add_item(str(Styling.MODES[mode_id]))
		style_selector.set_item_metadata(style_selector.item_count - 1, mode_id)
	style_selector.item_selected.connect(func(_index: int) -> void: _commit_style())
	_row(form, "Style", style_selector, true, false)

	# The color and its opacity share a row. The picker leaves the alpha alone,
	# since the box beside it is where the opacity is set. On a group they are
	# the single colour of its style and the opacity it multiplies in.
	var color_row := HBoxContainer.new()
	color_row.name = "ColorRow"
	_row(form, "Colour", color_row, true)

	color_button = ColorPickerButton.new()
	color_button.name = "Color"
	color_button.custom_minimum_size = Vector2(0, 28)
	color_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_button.edit_alpha = false
	# While the picker is open the colour is only previewed; closing it is what
	# makes one undo version out of however much dragging went on inside.
	color_button.color_changed.connect(_on_color_previewed)
	color_button.popup_closed.connect(_commit_color)
	color_row.add_child(color_button)

	opacity_spin = SpinBox.new()
	opacity_spin.name = "Opacity"
	opacity_spin.max_value = 100
	opacity_spin.step = 1
	opacity_spin.suffix = "%"
	opacity_spin.tooltip_text = "Opacity: 0 shows what is beneath, 100 covers it"
	opacity_spin.value_changed.connect(func(_value: float) -> void: _commit_color())
	color_row.add_child(opacity_spin)

	palette_selector = _selector("Palette")
	palette_selector.item_selected.connect(func(_index: int) -> void: _commit_style())
	_row(form, "Palette", palette_selector, true, false)

	enabled_check = CheckBox.new()
	enabled_check.name = "Enabled"
	enabled_check.text = "Drawn and hit tested"
	enabled_check.toggled.connect(_on_enabled_toggled)
	_row(form, "Enabled", enabled_check, true)

	from_spin = _time_spin("From")
	_row(form, "From (Ma)", from_spin)
	to_spin = _time_spin("To")
	_row(form, "To (Ma)", to_spin)

	geometry_label = Label.new()
	geometry_label.name = "Geometry"
	geometry_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_row(form, "Geometry", geometry_label)

	_build_keyframes(form)
	_build_sections(box)


# The section table of a line topology: which feature each section runs along,
# which of its vertices, and which way round. The two ends are editable, so a
# section built by clicking a whole feature can be trimmed to the stretch that
# belongs to the boundary.
func _build_sections(box: VBoxContainer) -> void:
	var heading := Label.new()
	heading.name = "SectionHeading"
	heading.text = "Sections"
	box.add_child(heading)
	_topology_boxes.append(heading)

	sections = Tree.new()
	sections.name = "Sections"
	sections.columns = SECTION_COLUMNS.size()
	sections.column_titles_visible = true
	sections.hide_root = true
	for column in SECTION_COLUMNS.size():
		sections.set_column_title(column, SECTION_COLUMNS[column])
		if column > 0:
			sections.set_column_expand(column, false)
			sections.set_column_custom_minimum_width(column, 48)
	sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sections.custom_minimum_size = Vector2(0, 160)
	sections.item_edited.connect(_on_section_edited)
	sections.item_selected.connect(_update_section_buttons)
	sections.nothing_selected.connect(_update_section_buttons)
	box.add_child(sections)
	_topology_boxes.append(sections)

	var buttons := HBoxContainer.new()
	buttons.name = "SectionButtons"
	box.add_child(buttons)
	_topology_boxes.append(buttons)

	reverse_button = Button.new()
	reverse_button.name = "Reverse"
	reverse_button.text = "Reverse"
	reverse_button.tooltip_text = "Walk the selected section the other way round"
	reverse_button.pressed.connect(_on_reverse_pressed)
	buttons.add_child(reverse_button)

	remove_section_button = Button.new()
	remove_section_button.name = "RemoveSection"
	remove_section_button.text = "Remove"
	remove_section_button.tooltip_text = "Take the selected section out of the topology"
	remove_section_button.pressed.connect(_on_remove_section_pressed)
	buttons.add_child(remove_section_button)


# The keyframe row: how many keyframes the feature has, and the two buttons that
# work at the current time. Landing on a keyframe is the timeline's job.
func _build_keyframes(form: GridContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "Keyframes"
	_row(form, "Keyframes", row)
	_motion_boxes.append(_rows.back()["label"])
	_motion_boxes.append(row)

	keyframe_count = Label.new()
	keyframe_count.name = "Count"
	keyframe_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Without clipping the text sets a minimum width, and the row is then wider
	# than CONTENT_WIDTH, which pushes the planet view aside.
	keyframe_count.clip_text = true
	row.add_child(keyframe_count)

	key_button = Button.new()
	key_button.name = "Key"
	key_button.text = "Key"
	key_button.tooltip_text = "Hold where this is now as a keyframe at the current time"
	key_button.pressed.connect(_on_key_pressed)
	row.add_child(key_button)

	delete_key_button = Button.new()
	delete_key_button.name = "DeleteKey"
	delete_key_button.text = "Delete"
	delete_key_button.tooltip_text = "Delete the keyframe at the current time"
	delete_key_button.pressed.connect(_on_delete_key_pressed)
	row.add_child(delete_key_button)


func _time_spin(spin_name: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = spin_name
	spin.min_value = 0
	spin.max_value = TIME_LIMIT
	spin.step = 1
	spin.value_changed.connect(func(_value: float) -> void: _commit_time_range())
	return spin


# One labelled row of the form. A row is hidden, label and all, while what is
# selected does not have it.
func _row(form: GridContainer, text: String, control: Control, on_a_group: bool = false,
		on_a_feature: bool = true) -> void:
	var label := Label.new()
	label.text = text
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(label)
	form.add_child(control)
	_rows.append({"label": label, "control": control, "on_a_group": on_a_group,
		"on_a_feature": on_a_feature})


# A selector whose longest item does not set the width of the panel: a palette
# file can have a long name.
func _selector(selector_name: String) -> OptionButton:
	var selector := OptionButton.new()
	selector.name = selector_name
	selector.fit_to_longest_item = false
	selector.clip_text = true
	return selector


### Filling the panel


# Show a feature, a group, or nothing at all. The root group is nothing to edit:
# it has no name of its own to change and no switch, the same as on its tree row.
func show_node(node_: Feature) -> void:
	node = node_
	var editable := node != null and not node.is_root
	var is_feature := editable and not node.is_group

	placeholder.visible = not editable
	if node != null and node.is_root:
		placeholder.text = "The %s group holds everything and has nothing to edit." % node.title
	else:
		placeholder.text = "Nothing is selected."
	for row in _rows:
		var shown: bool = (is_feature and row["on_a_feature"]) \
			or (editable and node.is_group and row["on_a_group"])
		(row["label"] as Control).visible = shown
		(row["control"] as Control).visible = shown
	# A topology has sections, and no motion of its own: where it is comes from
	# the features its sections run along. A group carries no motion either.
	var is_topology := is_feature and node.geometry_kind == Feature.GeometryKind.TOPOLOGY
	for control in _topology_boxes:
		control.visible = is_topology
	for control in _motion_boxes:
		control.visible = is_feature and not is_topology

	if not editable:
		return

	_filling = true
	name_edit.text = node.title
	enabled_check.button_pressed = node.enabled
	if is_feature:
		type_selector.select(_type_index(node.feature_type))
		_show_color()
		from_spin.value = node.time_range.x
		to_spin.value = node.time_range.y
		geometry_label.text = _geometry_summary(node)
		_fill_sections()
	else:
		_show_style()
	_filling = false
	_update_section_buttons()
	_update_keyframes()


# The current time moved: Delete only works on a keyframe the time sits on, and
# a section can be followed at one time and broken at another. Nothing else in
# the panel depends on the time.
func show_time() -> void:
	if node == null or node.is_root:
		return
	if node.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		_refill_sections()
	_update_keyframes()


func _type_index(type_id: String) -> int:
	for index in type_selector.item_count:
		if type_selector.get_item_metadata(index) == type_id:
			return index
	return -1


func _geometry_summary(feature: Feature) -> String:
	if not feature.has_geometry():
		return "none yet"
	if feature.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		var count := feature.sections.size()
		var broken := 0
		for entry in _resolved_sections():
			if not str(entry["problem"]).is_empty():
				broken += 1
		return "topology, %d section%s%s" % [count, "" if count == 1 else "s",
			"" if broken == 0 else ", %d broken" % broken]
	var vertices := feature.vertex_count()
	var parts := feature.rings.size()
	return "%s, %d %s in %d %s" % [
		feature.kind_name(),
		vertices, "vertex" if vertices == 1 else "vertices",
		parts, "part" if parts == 1 else "parts"]


### The section table


# Every section of the topology at the current time, so the table can say which
# of them are broken. An empty list while anything but a topology is selected.
func _resolved_sections() -> Array:
	if document == null or node == null or node.is_group \
			or node.geometry_kind != Feature.GeometryKind.TOPOLOGY:
		return []
	return Topology.resolve(document.root, node, document.current_time)


func _fill_sections() -> void:
	sections.clear()
	if node == null or node.is_group \
			or node.geometry_kind != Feature.GeometryKind.TOPOLOGY:
		return
	var root := sections.create_item()
	var resolved := _resolved_sections()
	for index in node.sections.size():
		var section: TopologySection = node.sections[index]
		var problem := str(resolved[index]["problem"]) if index < resolved.size() else ""
		var title := str(resolved[index]["title"]) if index < resolved.size() else ""

		var item := sections.create_item(root)
		item.set_metadata(0, index)
		item.set_text(0, title if not title.is_empty() else "(missing)")
		item.set_text(1, str(section.from_index + 1))
		item.set_text(2, str(section.to_index + 1))
		item.set_text(3, "back" if section.reversed else "on")
		for column in [1, 2]:
			item.set_editable(column, true)
		if not problem.is_empty():
			for column in SECTION_COLUMNS.size():
				item.set_custom_color(column, BROKEN_SECTION_COLOR)
				item.set_tooltip_text(column, problem)


func _on_section_edited() -> void:
	var item := sections.get_edited()
	var column := sections.get_edited_column()
	if _filling or node == null or item == null or item.get_metadata(0) == null:
		return

	var index := int(item.get_metadata(0))
	var text := item.get_text(column).strip_edges()
	if not text.is_valid_int():
		_take_back_section("%s is not a vertex number." % text)
		return

	# The table counts vertices from one.
	var section: TopologySection = node.sections[index]
	var from_index := section.from_index
	var to_index := section.to_index
	if column == 1:
		from_index = int(text) - 1
	else:
		to_index = int(text) - 1
	var error := document.set_section_range(node, index, from_index, to_index)
	if not error.is_empty():
		_take_back_section(error)
		return
	_refill_sections()
	edited.emit()


func _on_reverse_pressed() -> void:
	var index := selected_section()
	if index < 0:
		return
	var error := document.reverse_section(node, index)
	if not error.is_empty():
		rejected.emit(error)
		return
	_refill_sections()
	select_section(index)
	edited.emit()


func _on_remove_section_pressed() -> void:
	var index := selected_section()
	if index < 0:
		return
	var error := document.remove_section(node, index)
	if not error.is_empty():
		rejected.emit(error)
		return
	_refill_sections()
	edited.emit()


# Which section is picked, or -1 when the table is empty or none is. With no row
# picked the last section stands in.
func selected_section() -> int:
	if node == null or node.is_group or node.sections.is_empty():
		return -1
	var item := sections.get_selected()
	if item != null and item.get_metadata(0) != null:
		return int(item.get_metadata(0))
	return node.sections.size() - 1


func select_section(index: int) -> void:
	var root := sections.get_root()
	if root == null or index < 0 or index >= root.get_child_count():
		return
	sections.deselect_all()
	root.get_child(index).select(0)


func _update_section_buttons() -> void:
	var has_sections := node != null and not node.is_group and not node.sections.is_empty()
	reverse_button.disabled = not has_sections
	remove_section_button.disabled = not has_sections


func _refill_sections() -> void:
	_filling = true
	_fill_sections()
	if not node.is_group:
		geometry_label.text = _geometry_summary(node)
	_filling = false
	_update_section_buttons()


# Put the table back the way the topology is and say what went wrong, after an
# edit the document would not take.
func _take_back_section(message: String) -> void:
	_refill_sections()
	rejected.emit(message)


### The keyframe row


# Which keyframe the current time sits on, or -1 when it is between keyframes.
func _keyframe_here() -> int:
	if document == null or node == null or node.is_group:
		return -1
	return Keyframe.index_at(node.keyframes, document.current_time)


func _update_keyframes() -> void:
	var feature := node != null and not node.is_group
	var count := node.keyframes.size() if feature else 0
	keyframe_count.text = "%d keyframe%s" % [count, "" if count == 1 else "s"]
	key_button.disabled = not feature
	delete_key_button.disabled = _keyframe_here() < 0


# Hold where the node is now as a keyframe at the current time. This is how a
# keyframe is made without dragging: the rotation it records is the one the
# keyframes around the current time already give, so nothing on the globe moves.
func _on_key_pressed() -> void:
	if node == null or node.is_group:
		return
	var error := document.set_keyframe(
		node, document.current_time, node.rotation_at(document.current_time))
	if not error.is_empty():
		rejected.emit(error)
		return
	_update_keyframes()
	edited.emit()


func _on_delete_key_pressed() -> void:
	var index := _keyframe_here()
	if index < 0:
		return
	var error := document.remove_keyframe(node, index)
	if not error.is_empty():
		rejected.emit(error)
		return
	_update_keyframes()
	edited.emit()


### Editing


func _commit_name() -> void:
	if _filling or node == null or node.is_root or name_edit.text == node.title:
		return
	document.rename(node, name_edit.text)
	name_edit.text = node.title
	edited.emit()


func _on_enabled_toggled(pressed: bool) -> void:
	if _filling or node == null or node.is_root or pressed == node.enabled:
		return
	document.set_enabled(node, pressed)
	edited.emit()


func _on_type_selected(index: int) -> void:
	if _filling or node == null:
		return
	var error := document.set_feature_type(node, str(type_selector.get_item_metadata(index)))
	if not error.is_empty():
		_filling = true
		type_selector.select(_type_index(node.feature_type))
		_filling = false
		rejected.emit(error)
		return
	_filling = true
	_show_color()
	_filling = false
	edited.emit()


# The color on the button and the opacity in percent beside it. Call while
# _filling, so the box does not take its own new value for an edit.
func _show_color() -> void:
	color_button.color = node.color
	opacity_spin.value = roundf(node.color.a * 100.0)


# A group's style: the mode, the single colour and the opacity in the color row,
# and the palette, which lists the built in ones and the file the style names
# when it names one. Call while _filling.
func _show_style() -> void:
	var style := node.style
	style_selector.select(_item_index(style_selector, style.mode))
	color_button.color = Color(style.color, 1.0)
	opacity_spin.value = roundf(style.opacity * 100.0)
	palette_selector.clear()
	for key in Palette.BUILT_IN:
		palette_selector.add_item(str(Palette.BUILT_IN[key]["name"]))
		palette_selector.set_item_metadata(palette_selector.item_count - 1, key)
	if not Palette.BUILT_IN.has(style.palette):
		palette_selector.add_item(style.palette.get_file())
		palette_selector.set_item_metadata(palette_selector.item_count - 1, style.palette)
		palette_selector.set_item_tooltip(palette_selector.item_count - 1, style.palette)
	palette_selector.select(_item_index(palette_selector, style.palette))


func _item_index(selector: OptionButton, id: String) -> int:
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == id:
			return index
	return -1


# The picker sends a colour for every drag of its cursor. Showing them on the
# globe is what makes it a picker, so the feature or the group takes them all,
# but only the one left when the picker closes reaches the undo stack.
func _on_color_previewed(color: Color) -> void:
	if _filling or node == null or node.is_root:
		return
	if node.is_group:
		node.style.color = Color(color, node.style.color.a)
	else:
		node.color = Color(color, opacity_spin.value / 100.0)
	previewed.emit()


# The picked color at the opacity the box holds. A change of either is one
# edit, one undo version.
func _commit_color() -> void:
	if _filling or node == null or node.is_root:
		return
	if node.is_group:
		_commit_style()
		return
	document.set_color(node, Color(color_button.color, opacity_spin.value / 100.0))
	recolored.emit()


# The whole style off the group rows, as one edit. The single colour keeps the
# alpha it has, since the opacity box is where a group is made see-through.
func _commit_style() -> void:
	if _filling or node == null or node.is_root or not node.is_group:
		return
	var style := GroupStyle.new()
	style.mode = str(style_selector.get_item_metadata(style_selector.selected))
	style.color = Color(color_button.color, node.style.color.a)
	style.opacity = opacity_spin.value / 100.0
	style.palette = str(palette_selector.get_item_metadata(palette_selector.selected))
	var error := document.set_style(node, style)
	if not error.is_empty():
		rejected.emit(error)
		return
	recolored.emit()


func _commit_time_range() -> void:
	if _filling or node == null or node.is_group:
		return
	var wanted := Vector2i(int(from_spin.value), int(to_spin.value))
	if wanted == node.time_range:
		return
	var error := document.set_time_range(node, wanted)
	if not error.is_empty():
		_filling = true
		from_spin.value = node.time_range.x
		to_spin.value = node.time_range.y
		_filling = false
		rejected.emit(error)
		return
	edited.emit()


### The automation port


# What the panel is showing, read off the widgets rather than off the feature.
func to_json() -> Dictionary:
	if node == null:
		return {"showing": "nothing", "width": size.x}
	if node.is_root:
		return {"showing": "root", "placeholder": placeholder.text, "width": size.x}
	var data := {
		"showing": "group" if node.is_group else "feature",
		"width": size.x,
		"name": name_edit.text,
		"enabled": enabled_check.button_pressed,
	}
	if node.is_group:
		var mode := style_selector.selected
		var chosen := palette_selector.selected
		data["style"] = {
			"mode": str(style_selector.get_item_metadata(mode)) if mode >= 0 else "",
			"color": [color_button.color.r, color_button.color.g, color_button.color.b,
				node.style.color.a],
			"opacity": int(opacity_spin.value),
			"palette": str(palette_selector.get_item_metadata(chosen)) if chosen >= 0 else "",
		}
		data["styles"] = range(style_selector.item_count).map(
			func(index: int) -> String: return str(style_selector.get_item_metadata(index)))
		data["palettes"] = range(palette_selector.item_count).map(
			func(index: int) -> String: return str(palette_selector.get_item_metadata(index)))
		return data
	var picked := type_selector.selected
	data["feature_type"] = str(type_selector.get_item_metadata(picked)) if picked >= 0 else ""
	data["type_label"] = type_selector.get_item_text(picked) if picked >= 0 else ""
	data["types"] = range(type_selector.item_count).map(
		func(index: int) -> String: return str(type_selector.get_item_metadata(index)))
	data["color"] = [color_button.color.r, color_button.color.g,
		color_button.color.b, opacity_spin.value / 100.0]
	data["opacity"] = int(opacity_spin.value)
	data["time_range"] = [int(from_spin.value), int(to_spin.value)]
	data["geometry"] = geometry_label.text
	if keyframe_count.get_parent().visible:
		data["keyframes"] = {
			"count": keyframe_count.text.to_int(),
			"key": not key_button.disabled,
			"delete": not delete_key_button.disabled,
		}
	data["sections"] = _sections_to_json()
	return data


# The section table as it stands, read off the rows rather than off the feature,
# so a run checks what the panel is showing.
func _sections_to_json() -> Array:
	var rows: Array = []
	var root := sections.get_root()
	if root == null:
		return rows
	for item in root.get_children():
		rows.append({
			"feature": item.get_text(0),
			"from": int(item.get_text(1)),
			"to": int(item.get_text(2)),
			"way": item.get_text(3),
			"broken": item.get_custom_color(0) == BROKEN_SECTION_COLOR,
		})
	return rows


# Drive one field the way a person would, for the scripted session.
func set_field(field: String, value: Variant) -> String:
	if node == null or node.is_root:
		return "nothing that can be edited is selected"
	match field:
		"name":
			name_edit.text = str(value)
			_commit_name()
		"enabled":
			enabled_check.button_pressed = bool(value)
			_on_enabled_toggled(bool(value))
		"feature_type":
			var index := _type_index(str(value))
			type_selector.select(index)
			_on_type_selected(index)
		"style", "palette":
			if not node.is_group:
				return "a feature has no %s; its group does" % field
			var selector := style_selector if field == "style" else palette_selector
			var at := _item_index(selector, str(value))
			if at < 0:
				return "the %s selector offers no %s" % [field, value]
			selector.select(at)
			_commit_style()
		"color":
			var c: Array = value
			_filling = true
			color_button.color = Color(c[0], c[1], c[2])
			opacity_spin.value = roundf((c[3] if c.size() > 3 else 1.0) * 100.0)
			_filling = false
			_commit_color()
		"opacity":
			opacity_spin.value = float(value)
		"time_from":
			from_spin.value = float(value)
		"time_to":
			to_spin.value = float(value)
		_:
			return "no such property: %s" % field
	return ""
