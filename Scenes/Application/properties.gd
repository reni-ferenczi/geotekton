extends PanelContainer
class_name Properties

# The Properties panel: what the feature tree has selected, laid out so it can
# be edited. A leaf feature shows its name, type, colour, enabled switch, time
# range and the coordinates of its geometry; a group shows the name and the
# switch, because that is all a group has. See Docs/Properties.md.
#
# The panel never writes to a feature itself. Every edit goes through the
# document, which validates it and records one undo version, and an edit the
# document refuses is reported through `rejected` and taken back on screen.

# An edit went through: the tree row and the globe need to catch up.
signal edited()

# The colour picker is being dragged: the globe needs to catch up, but nothing
# has been recorded yet, so the tree does not.
signal previewed()

# An edit was refused, with the message saying why.
signal rejected(message: String)

# The oldest age either end of a time range can name.
const TIME_LIMIT := 10000

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
var color_button: ColorPickerButton
var enabled_check: CheckBox
var from_spin: SpinBox
var to_spin: SpinBox
var geometry_label: Label
var coordinates: Tree
var add_button: Button
var remove_button: Button

# Every row of the form, each a label and the control beside it, and whether a
# group has it too.
var _rows: Array[Dictionary] = []
# Everything below the form, which only a leaf feature has.
var _feature_boxes: Array[Control] = []


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

	color_button = ColorPickerButton.new()
	color_button.name = "Color"
	color_button.custom_minimum_size = Vector2(0, 28)
	color_button.edit_alpha = false
	# While the picker is open the colour is only previewed; closing it is what
	# makes one undo version out of however much dragging went on inside.
	color_button.color_changed.connect(_on_color_previewed)
	color_button.popup_closed.connect(_commit_color)
	_row(form, "Colour", color_button)

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

	coordinates = Tree.new()
	coordinates.name = "Coordinates"
	coordinates.columns = 3
	coordinates.column_titles_visible = true
	coordinates.hide_root = true
	coordinates.set_column_title(0, "Part")
	coordinates.set_column_title(1, "Latitude")
	coordinates.set_column_title(2, "Longitude")
	coordinates.set_column_expand(0, false)
	coordinates.set_column_custom_minimum_width(0, 64)
	coordinates.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coordinates.custom_minimum_size = Vector2(0, 160)
	coordinates.item_edited.connect(_on_coordinate_edited)
	coordinates.item_selected.connect(_update_vertex_buttons)
	coordinates.nothing_selected.connect(_update_vertex_buttons)
	box.add_child(coordinates)
	_feature_boxes.append(coordinates)

	var buttons := HBoxContainer.new()
	buttons.name = "VertexButtons"
	box.add_child(buttons)
	_feature_boxes.append(buttons)

	add_button = Button.new()
	add_button.name = "Add"
	add_button.text = "Add"
	add_button.tooltip_text = "Add a vertex after the selected one"
	add_button.pressed.connect(_on_add_pressed)
	buttons.add_child(add_button)

	remove_button = Button.new()
	remove_button.name = "Remove"
	remove_button.text = "Remove"
	remove_button.tooltip_text = "Remove the selected vertex"
	remove_button.pressed.connect(_on_remove_pressed)
	buttons.add_child(remove_button)


func _time_spin(spin_name: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = spin_name
	spin.min_value = 0
	spin.max_value = TIME_LIMIT
	spin.step = 1
	spin.value_changed.connect(func(_value: float) -> void: _commit_time_range())
	return spin


# One labelled row of the form. A row a group does not have is hidden, label and
# all, while a group or nothing is selected.
func _row(form: GridContainer, text: String, control: Control, on_a_group: bool = false) -> void:
	var label := Label.new()
	label.text = text
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(label)
	form.add_child(control)
	_rows.append({"label": label, "control": control, "on_a_group": on_a_group})


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
		var shown: bool = is_feature or (editable and row["on_a_group"])
		(row["label"] as Control).visible = shown
		(row["control"] as Control).visible = shown
	for control in _feature_boxes:
		control.visible = is_feature

	if not editable:
		return

	_filling = true
	name_edit.text = node.title
	enabled_check.button_pressed = node.enabled
	if is_feature:
		type_selector.select(_type_index(node.feature_type))
		color_button.color = node.color
		from_spin.value = node.time_range.x
		to_spin.value = node.time_range.y
		geometry_label.text = _geometry_summary(node)
		_fill_coordinates()
	_filling = false
	_update_vertex_buttons()


func _type_index(type_id: String) -> int:
	for index in type_selector.item_count:
		if type_selector.get_item_metadata(index) == type_id:
			return index
	return 0


func _geometry_summary(feature: Feature) -> String:
	if not feature.has_geometry():
		return "none yet"
	var vertices := feature.vertex_count()
	var parts := feature.rings.size()
	return "%s, %d %s in %d %s" % [
		feature.kind_name(),
		vertices, "vertex" if vertices == 1 else "vertices",
		parts, "part" if parts == 1 else "parts"]


# One row per part, with its vertices under it. The metadata of a vertex row is
# where it sits, so an edit knows which vertex of which part it changed.
func _fill_coordinates() -> void:
	coordinates.clear()
	var root := coordinates.create_item()
	for part in node.rings.size():
		var part_item := coordinates.create_item(root)
		part_item.set_text(0, "Part %d" % (part + 1))
		for column in 3:
			part_item.set_selectable(column, false)
		for index in node.rings[part].size():
			var vertex := node.rings[part][index]
			var item := coordinates.create_item(part_item)
			item.set_metadata(0, Vector2i(part, index))
			item.set_text(0, str(index + 1))
			item.set_selectable(0, false)
			for column in [1, 2]:
				item.set_editable(column, true)
			item.set_text(1, format_degrees(vertex.x))
			item.set_text(2, format_degrees(vertex.y))


static func format_degrees(value: float) -> String:
	return "%.4f" % value


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
	color_button.color = node.color
	_filling = false
	edited.emit()


# The picker sends a colour for every drag of its cursor. Showing them on the
# globe is what makes it a picker, so the feature takes them all, but only the
# one left when the picker closes reaches the undo stack.
func _on_color_previewed(color: Color) -> void:
	if _filling or node == null or node.is_group:
		return
	node.color = color
	previewed.emit()


func _commit_color() -> void:
	if _filling or node == null or node.is_group:
		return
	document.set_color(node, color_button.color)
	edited.emit()


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


func _on_coordinate_edited() -> void:
	var item := coordinates.get_edited()
	var column := coordinates.get_edited_column()
	if _filling or node == null or item == null or item.get_metadata(0) == null:
		return

	var at: Vector2i = item.get_metadata(0)
	var text := item.get_text(column).strip_edges()
	if not text.is_valid_float():
		_take_back_coordinate(at, "%s is not a number." % text)
		return

	var vertex := node.rings[at.x][at.y]
	if column == 1:
		vertex.x = float(text)
	else:
		vertex.y = float(text)
	var error := document.set_vertex(node, at.x, at.y, vertex)
	if not error.is_empty():
		_take_back_coordinate(at, error)
		return
	edited.emit()


func _on_add_pressed() -> void:
	var at := selected_vertex()
	if at.x < 0:
		return
	# The new vertex starts on top of the selected one, so it is moved into place
	# by editing it rather than by knowing where it goes in advance.
	var error := document.insert_vertex(node, at.x, at.y + 1, node.rings[at.x][at.y])
	if not error.is_empty():
		rejected.emit(error)
		return
	edited.emit()
	select_vertex(at.x, at.y + 1)


func _on_remove_pressed() -> void:
	var at := selected_vertex()
	if at.x < 0:
		return
	var error := document.remove_vertex(node, at.x, at.y)
	if not error.is_empty():
		rejected.emit(error)
		return
	edited.emit()


### The coordinate table selection


# Where the selected vertex sits, or (-1, -1) when the feature has no geometry.
# With no row picked the last vertex of the last part stands in, so the buttons
# work on a table nobody has clicked in yet.
func selected_vertex() -> Vector2i:
	if node == null or node.is_group or node.rings.is_empty():
		return Vector2i(-1, -1)
	var item := coordinates.get_selected()
	if item != null and item.get_metadata(0) != null:
		return item.get_metadata(0)
	var part := node.rings.size() - 1
	return Vector2i(part, node.rings[part].size() - 1)


func select_vertex(part: int, index: int) -> void:
	var root := coordinates.get_root()
	if root == null or part < 0 or part >= root.get_child_count():
		return
	var part_item := root.get_child(part)
	if index < 0 or index >= part_item.get_child_count():
		return
	coordinates.deselect_all()
	part_item.get_child(index).select(1)


func _update_vertex_buttons() -> void:
	var has_geometry := node != null and not node.is_group and node.has_geometry()
	add_button.disabled = not has_geometry
	remove_button.disabled = not has_geometry


# Put the table back the way the feature is and say what went wrong, after an
# edit the document would not take.
func _take_back_coordinate(at: Vector2i, message: String) -> void:
	_filling = true
	_fill_coordinates()
	_filling = false
	select_vertex(at.x, at.y)
	rejected.emit(message)


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
		return data
	data["feature_type"] = str(type_selector.get_item_metadata(type_selector.selected))
	data["type_label"] = type_selector.get_item_text(type_selector.selected)
	data["color"] = [color_button.color.r, color_button.color.g,
		color_button.color.b, color_button.color.a]
	data["time_range"] = [int(from_spin.value), int(to_spin.value)]
	data["geometry"] = geometry_label.text
	data["coordinates"] = _coordinates_to_json()
	return data


func _coordinates_to_json() -> Array:
	var parts: Array = []
	var root := coordinates.get_root()
	if root == null:
		return parts
	for part_item in root.get_children():
		var vertices: Array = []
		for item in part_item.get_children():
			vertices.append([float(item.get_text(1)), float(item.get_text(2))])
		parts.append(vertices)
	return parts


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
		"color":
			var c: Array = value
			color_button.color = Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)
			_commit_color()
		"time_from":
			from_spin.value = float(value)
		"time_to":
			to_spin.value = float(value)
		_:
			return "no such property: %s" % field
	return ""
