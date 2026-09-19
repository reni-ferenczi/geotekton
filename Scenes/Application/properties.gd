extends PanelContainer
class_name Properties

# The Properties panel: what the feature tree has selected, laid out so it can
# be edited. A leaf feature shows its name, type, colour, enabled switch, time
# range, what its geometry holds and how many keyframes it has; a group shows
# the name, the switch and its style: how the features under it are colored.
# The root group's style is pinned, so the root shows nothing to edit. See
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

# The pointer button on the Follow row was pressed or let go. The Application
# owns the pick mode; the button only asks for it and shows whether it is on.
signal pick_parent_requested(on: bool)

# The Pick axis button was pressed. The Application owns the pick, which is the
# Pole tool's click, and writes the axis through the document.
signal pick_axis_requested()

# The pointer button on the Plate row was pressed or let go. The Application
# owns that pick as well, the same mode as the parent pick.
signal pick_plate_requested(on: bool)

# The Pick toggle of the section table was pressed or let go. The Application
# arms the Topology tool for the topology shown, and ends it.
signal pick_section_requested(on: bool)

# The Load button on the Palette row was pressed. The Application owns the file
# dialog and hands the path it gets back to load_palette().
signal palette_file_requested()

# The oldest age either end of a time range can name.
const TIME_LIMIT := int(Document.MAX_TIME)

# The two ends of the time range, read the way the work runs: from the oldest
# age towards the present. `From` is the older end, which is `time_range.y`.
const FROM_TOOLTIP := "The age the feature appears at, in millions of years ago; larger is older"
const TO_TOOLTIP := "The age it disappears at; 0 is the present"
const STEP_TOOLTIP := ("How far apart in time the track or the bands are sampled, "
	+ "in millions of years; 0 follows the timeline's Skip")
# On the group Style row. Same as parent is the one mode that decides nothing.
const STYLE_TOOLTIP := ("Same as parent colors the features the way the group above does; "
	+ "Feature colour and the others decide for themselves")

# The columns of the section table of a topology: the feature the section
# runs along, the vertices of it the section covers, counted from one, and which
# way round it is walked.
const SECTION_COLUMNS = ["Feature", "From", "To", "Way"]

# The pointer on the Follow row, which picks the parent off the planet, and on
# the section table, which picks sections.
const PICK_PARENT_ICON := "res://Assets/Icons/Pointer.svg"

# A section whose feature can no longer be found, or cannot be followed at the
# current time, is drawn in this rather than dropped, so a topology says what it
# has lost instead of quietly shrinking.
const BROKEN_SECTION_COLOR = Color(0.9, 0.45, 0.4, 1.0)

# The columns of the coupling list: the feature followed, and the older and the
# younger end of the span in Ma. A span whose parent cannot be followed is drawn
# in the same warning colour as a broken section.
const SPAN_COLUMNS = ["Parent", "From", "To"]

# How wide the panel is, whatever it happens to be showing.
const CONTENT_WIDTH := 220

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
var icon_selector: OptionButton
var style_selector: OptionButton
var palette_selector: OptionButton
var ramp_row: RampRow
var color_button: ColorPickerButton
var opacity_spin: SpinBox
var enabled_check: CheckBox
var from_spin: SpinBox
var to_spin: SpinBox
var area_label: Label
var keyframe_count: Label
var key_button: Button
var delete_key_button: Button
var sections: Tree
var reverse_button: Button
var remove_section_button: Button
var pick_section_button: Button
var closed_check: CheckBox
var topology_note: Label
var coupled_label: Label
var decouple_button: Button
var parent_selector: OptionButton
var couple_button: Button
var pick_parent_button: Button
var spans: Tree
var remove_span_button: Button
var axis_circles_check: CheckBox
var axis_lat_spin: SpinBox
var axis_lon_spin: SpinBox
var radius_spin: SpinBox
var circle_segments_spin: SpinBox
var pick_axis_button: Button
var plate_row: HBoxContainer
var plate_selector: OptionButton
var pick_plate_button: Button
var step_spin: SpinBox

# Every row of the form, each a label and the control beside it, and whether a
# group and a feature have it.
var _rows: Array[Dictionary] = []
# The caption of the Area row, which shows only for what is drawn as a polygon.
var _area_caption: Label
# The Closed switch, the section table and its buttons, which only a topology
# has.
var _topology_boxes: Array[Control] = []
# The keyframe row, label and all, which a feature holding vertices of its own
# has. A topology has no motion of its own, and a group carries none.
var _motion_boxes: Array[Control] = []
# The Coupled to and Follow rows, the Couplings heading, the span list and its
# button. Only a feature with motion has them, and a circle does not either:
# it follows nothing and carries nothing.
var _coupling_boxes: Array[Control] = []
# The Axis circles switch and the axis, radius and segment rows, which only a
# circle has.
var _circle_boxes: Array[Control] = []
# The Plate row, which only a hotspot has.
var _hotspot_boxes: Array[Control] = []
# The Step (My) row, which a hotspot and a crust both have: they are the two
# that sample over time.
var _step_boxes: Array[Control] = []


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

	type_selector = _selector("Type")
	for type_id in FeatureType.CATALOG:
		type_selector.add_item(FeatureType.label(type_id))
		type_selector.set_item_metadata(type_selector.item_count - 1, type_id)
	type_selector.item_selected.connect(_on_type_selected)
	_row(form, "Type", type_selector)

	# The glyph the feature's tree row carries. It is for whoever is looking;
	# nothing else in the program reads it.
	icon_selector = _selector("Icon")
	icon_selector.tooltip_text = "The picture on the feature's tree row"
	icon_selector.add_item("None")
	icon_selector.set_item_metadata(0, FeatureIcon.NONE)
	for icon_id in FeatureIcon.CATALOG:
		icon_selector.add_item(FeatureIcon.label(icon_id))
		icon_selector.set_item_icon(icon_selector.item_count - 1, FeatureIcon.texture(icon_id))
		icon_selector.set_item_metadata(icon_selector.item_count - 1, icon_id)
	icon_selector.item_selected.connect(_on_icon_selected)
	_row(form, "Icon", icon_selector)
	# A selector that does not fit its longest item is as tall as the item it
	# shows, and None has no picture. The row keeps the height of one that has.
	icon_selector.select(1)
	icon_selector.custom_minimum_size.y = icon_selector.get_combined_minimum_size().y
	icon_selector.select(0)

	style_selector = _selector("Style")
	style_selector.tooltip_text = STYLE_TOOLTIP
	for mode_id in Styling.MODES:
		style_selector.add_item(str(Styling.MODES[mode_id]))
		style_selector.set_item_metadata(style_selector.item_count - 1, mode_id)
	style_selector.item_selected.connect(func(_index: int) -> void: _commit_style())
	_row(form, "Style", style_selector, true, false, STYLE_TOOLTIP)

	# The color and its opacity share a row. The picker leaves the alpha alone,
	# since the box beside it is where the opacity is set. On a group they are
	# the single colour of its style and the opacity it multiplies in.
	var color_row := HBoxContainer.new()
	color_row.name = "ColorRow"
	_row(form, "Colour", color_row, true)

	color_button = Helpers.color_button("Color", Helpers.COLOR_TOOLTIP)
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

	# The palette and the button that reads one from a GMT .cpt file.
	var palette_row := HBoxContainer.new()
	palette_row.name = "PaletteRow"
	_row(form, "Palette", palette_row, true, false)

	palette_selector = _selector("Palette")
	palette_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_selector.item_selected.connect(func(_index: int) -> void: _commit_style())
	palette_row.add_child(palette_selector)

	var load_palette_button := Button.new()
	load_palette_button.name = "LoadPalette"
	load_palette_button.text = "Load..."
	load_palette_button.tooltip_text = "Read a GMT color palette table from a .cpt file"
	load_palette_button.pressed.connect(palette_file_requested.emit)
	palette_row.add_child(load_palette_button)

	# The colours the Custom palette reads and the My between two of them.
	ramp_row = RampRow.new(TIME_LIMIT)
	ramp_row.previewed.connect(_on_ramp_previewed)
	ramp_row.committed.connect(_commit_style)
	_row(form, "Ramp", ramp_row, true, false)

	enabled_check = CheckBox.new()
	enabled_check.name = "Enabled"
	enabled_check.text = "Drawn and hit tested"
	enabled_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enabled_check.toggled.connect(_on_enabled_toggled)
	_row(form, "Enabled", enabled_check, true)

	from_spin = _time_spin("From", FROM_TOOLTIP)
	_row(form, "From (Ma)", from_spin, false, true, FROM_TOOLTIP)
	to_spin = _time_spin("To", TO_TOOLTIP)
	_row(form, "To (Ma)", to_spin, false, true, TO_TOOLTIP)

	area_label = Label.new()
	area_label.name = "Area"
	# Without wrapping, the longer line would set the width of the panel.
	area_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_row(form, "Area", area_label)
	_area_caption = _rows.back()["label"]

	_build_circle(form)
	_build_hotspot(form)
	_build_step(form)
	_build_keyframes(form)
	_build_coupling(form, box)
	_build_sections(box)


# The section table of a topology: which feature each section runs along,
# which of its vertices, and which way round. The two ends are editable, so a
# section built by clicking a whole feature can be trimmed to the stretch that
# belongs to the boundary.
func _build_sections(box: VBoxContainer) -> void:
	# What a ridge or a crust is, since neither is built from the table.
	topology_note = Label.new()
	topology_note.name = "TopologyNote"
	topology_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(topology_note)

	closed_check = CheckBox.new()
	closed_check.name = "Closed"
	closed_check.text = "Closed"
	closed_check.tooltip_text = "Join the sections into one ring and fill it"
	closed_check.toggled.connect(_on_closed_toggled)
	box.add_child(closed_check)
	_topology_boxes.append(closed_check)

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

	pick_section_button = Button.new()
	pick_section_button.name = "PickSection"
	pick_section_button.toggle_mode = true
	pick_section_button.icon = load(PICK_PARENT_ICON)
	pick_section_button.tooltip_text = "Click a feature on the planet to add its part as a section"
	pick_section_button.toggled.connect(
		func(on: bool) -> void: pick_section_requested.emit(on))
	buttons.add_child(pick_section_button)


# The rows a circle is built from, under the Area row, which a circle outline
# does not show: the switch that draws it at both ends of its axis, the axis,
# which is the circle's center, the radius, how many segments it has, and the
# button that picks the axis off the planet. Each edit is one undo version.
func _build_circle(form: GridContainer) -> void:
	axis_circles_check = CheckBox.new()
	axis_circles_check.name = "AxisCircles"
	axis_circles_check.text = "Axis circles"
	axis_circles_check.tooltip_text = "Draw the circle at both poles of an axis"
	axis_circles_check.toggled.connect(func(_on: bool) -> void: _commit_circle())
	_row(form, "", axis_circles_check)
	_circle_boxes.append(_rows.back()["label"])
	_circle_boxes.append(axis_circles_check)

	var commit := func(_value: float) -> void: _commit_circle()
	axis_lat_spin = _param_spin("AxisLatitude", -90.0, 90.0, 0.01, "°", commit)
	axis_lon_spin = _param_spin("AxisLongitude", -180.0, 180.0, 0.01, "°", commit)
	radius_spin = _param_spin("Radius", 0.01, Document.MAX_CIRCLE_RADIUS, 0.01, "", commit)
	circle_segments_spin = _param_spin("Segments", Circle.MIN_SEGMENTS, Circle.MAX_SEGMENTS, 1, "",
		commit)
	for entry: Array in [["Axis latitude", axis_lat_spin], ["Axis longitude", axis_lon_spin],
			["Radius (°)", radius_spin], ["Segments", circle_segments_spin]]:
		_row(form, entry[0], entry[1])
		_circle_boxes.append(_rows.back()["label"])
		_circle_boxes.append(entry[1])

	pick_axis_button = Button.new()
	pick_axis_button.name = "PickAxis"
	pick_axis_button.text = "Pick axis"
	pick_axis_button.tooltip_text = "Click the planet to put the axis there"
	pick_axis_button.pressed.connect(pick_axis_requested.emit)
	_row(form, "", pick_axis_button)
	_circle_boxes.append(_rows.back()["label"])
	_circle_boxes.append(pick_axis_button)


# The row a hotspot takes its plate from: the picker and the pointer that
# picks the plate off the planet. The Draw tool places the hotspot itself. Each
# edit is one undo version.
func _build_hotspot(form: GridContainer) -> void:
	plate_row = HBoxContainer.new()
	plate_row.name = "PlateRow"
	_row(form, "Plate", plate_row)
	_hotspot_boxes.append(_rows.back()["label"])
	_hotspot_boxes.append(plate_row)

	plate_selector = _selector("Plate")
	plate_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate_selector.item_selected.connect(func(_index: int) -> void: _commit_hotspot())
	plate_row.add_child(plate_selector)

	pick_plate_button = Button.new()
	pick_plate_button.name = "PickPlate"
	pick_plate_button.toggle_mode = true
	pick_plate_button.icon = load(PICK_PARENT_ICON)
	pick_plate_button.tooltip_text = "Click a feature on the planet to burn through it"
	pick_plate_button.toggled.connect(
		func(on: bool) -> void: pick_plate_requested.emit(on))
	plate_row.add_child(pick_plate_button)


# How far apart in time the feature is sampled. A hotspot and a crust are the
# two that sample, and both take it here; 0 leaves them on the timeline's Skip.
# One undo version per edit, through the document. See Docs/Time.md#the-time-control.
func _build_step(form: GridContainer) -> void:
	step_spin = _param_spin("TimeStep", 0.0, Hotspot.MAX_STEP, 1.0, "",
		func(_value: float) -> void: _commit_step())
	step_spin.tooltip_text = STEP_TOOLTIP
	_row(form, "Step (My)", step_spin, false, true, STEP_TOOLTIP)
	_step_boxes.append(_rows.back()["label"])
	_step_boxes.append(step_spin)


func _param_spin(spin_name: String, low: float, high: float, step: float,
		suffix: String, commit: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = spin_name
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.suffix = suffix
	spin.value_changed.connect(commit)
	return spin


# The keyframe row: how many keyframes the feature has, and the two buttons that
# work at the current time. Landing on a keyframe is the timeline's job.
func _build_keyframes(form: GridContainer) -> void:
	var row := HFlowContainer.new()
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


# What the feature follows: the parent in effect at the current time with the
# Decouple button beside it, a picker of the features it could follow with the
# Couple button, and the list of its spans, each removable. See
# Docs/Properties.md#coupling.
func _build_coupling(form: GridContainer, box: VBoxContainer) -> void:
	var coupled_row := HBoxContainer.new()
	coupled_row.name = "CoupledTo"
	_row(form, "Coupled to", coupled_row)
	_coupling_boxes.append(_rows.back()["label"])
	_coupling_boxes.append(coupled_row)

	coupled_label = Label.new()
	coupled_label.name = "Parent"
	coupled_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coupled_label.clip_text = true
	coupled_row.add_child(coupled_label)

	decouple_button = Button.new()
	decouple_button.name = "Decouple"
	decouple_button.text = "Decouple"
	decouple_button.tooltip_text = "Stop following it at the current time"
	decouple_button.pressed.connect(_on_decouple_pressed)
	coupled_row.add_child(decouple_button)

	var couple_row := HFlowContainer.new()
	couple_row.name = "CoupleRow"
	_row(form, "Follow", couple_row)
	_coupling_boxes.append(_rows.back()["label"])
	_coupling_boxes.append(couple_row)

	parent_selector = _selector("ParentPicker")
	parent_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent_selector.item_selected.connect(func(_index: int) -> void: _update_coupling())
	couple_row.add_child(parent_selector)

	couple_button = Button.new()
	couple_button.name = "Couple"
	couple_button.text = "Couple"
	couple_button.tooltip_text = "Follow the picked feature from the current time"
	couple_button.pressed.connect(_on_couple_pressed)
	couple_row.add_child(couple_button)

	pick_parent_button = Button.new()
	pick_parent_button.name = "PickParent"
	pick_parent_button.toggle_mode = true
	pick_parent_button.icon = load(PICK_PARENT_ICON)
	pick_parent_button.tooltip_text = "Click a feature on the planet to follow it"
	pick_parent_button.toggled.connect(
		func(on: bool) -> void: pick_parent_requested.emit(on))
	couple_row.add_child(pick_parent_button)

	var heading := Label.new()
	heading.name = "SpanHeading"
	heading.text = "Couplings"
	box.add_child(heading)
	_coupling_boxes.append(heading)

	spans = Tree.new()
	spans.name = "Spans"
	spans.columns = SPAN_COLUMNS.size()
	spans.column_titles_visible = true
	spans.hide_root = true
	for column in SPAN_COLUMNS.size():
		spans.set_column_title(column, SPAN_COLUMNS[column])
		if column > 0:
			spans.set_column_expand(column, false)
			spans.set_column_custom_minimum_width(column, 56)
	spans.custom_minimum_size = Vector2(0, 88)
	spans.item_selected.connect(_update_coupling)
	spans.nothing_selected.connect(_update_coupling)
	box.add_child(spans)
	_coupling_boxes.append(spans)

	var buttons := HBoxContainer.new()
	buttons.name = "SpanButtons"
	box.add_child(buttons)
	_coupling_boxes.append(buttons)

	remove_span_button = Button.new()
	remove_span_button.name = "RemoveSpan"
	remove_span_button.text = "Remove"
	remove_span_button.tooltip_text = "Take the selected coupling away; every keyframe stays where it is on the globe"
	remove_span_button.pressed.connect(_on_remove_span_pressed)
	buttons.add_child(remove_span_button)


func _time_spin(spin_name: String, tooltip: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = spin_name
	spin.min_value = 0
	spin.max_value = TIME_LIMIT
	spin.step = 1
	spin.tooltip_text = tooltip
	spin.value_changed.connect(func(_value: float) -> void: _commit_time_range())
	return spin


# One labelled row of the form. A row is hidden, label and all, while what is
# selected does not have it. A tooltip is put on the label as well as on the
# control, so that pointing at either says what the row means.
func _row(form: GridContainer, text: String, control: Control, on_a_group: bool = false,
		on_a_feature: bool = true, tooltip: String = "") -> void:
	var label := Label.new()
	label.text = text
	if not tooltip.is_empty():
		label.tooltip_text = tooltip
		# A Label lets the mouse through, so its tooltip would never show.
		label.mouse_filter = Control.MOUSE_FILTER_STOP
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(label)
	form.add_child(control)
	# A row that wraps when the panel is narrow keeps the spacing of a row that
	# does not, which the theme gives HBoxContainer only.
	if control is HFlowContainer:
		control.add_theme_constant_override("h_separation",
			control.get_theme_constant("separation", "HBoxContainer"))
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
	# The pick mode belongs to the feature that asked for it, so showing another
	# one ends it rather than letting the next click pick a parent for it.
	if node_ != node and pick_parent_button != null and pick_parent_button.button_pressed:
		pick_parent_button.set_pressed_no_signal(false)
		pick_parent_requested.emit(false)
	if node_ != node and pick_plate_button != null and pick_plate_button.button_pressed:
		pick_plate_button.set_pressed_no_signal(false)
		pick_plate_requested.emit(false)
	node = node_
	var editable := node != null and not node.is_root
	var is_feature := editable and not node.is_group

	placeholder.visible = not editable
	placeholder.text = _root_sentence() if node != null and node.is_root else "Nothing is selected."
	for row in _rows:
		var shown: bool = (is_feature and row["on_a_feature"]) \
			or (editable and node.is_group and row["on_a_group"])
		(row["label"] as Control).visible = shown
		(row["control"] as Control).visible = shown
	# A topology has sections, and no motion of its own: where it is comes from
	# the features its sections run along. A group carries no motion either. A
	# feature typed Topology that holds no section yet shows the empty table, so
	# its Pick toggle can add the first one.
	var is_topology := is_feature and (node.geometry_kind == Feature.GeometryKind.TOPOLOGY
		or node.feature_type == "topology")
	# A crust is built from its half and its ridge, so it has no table, and a
	# ridge is a line between its two sections, so it cannot be closed.
	var is_crust := is_feature and node.is_crust()
	var is_midway := is_feature and node.midway
	for control in _topology_boxes:
		control.visible = is_topology and not is_crust
	closed_check.visible = is_topology and not is_crust and not is_midway
	topology_note.visible = is_crust or is_midway
	# A hotspot is fixed in the world frame, so it has no motion either.
	var is_hotspot := is_feature and node.is_hotspot()
	var has_motion := is_feature and not is_topology and not is_hotspot
	for control in _motion_boxes:
		control.visible = has_motion
	for control in _coupling_boxes:
		control.visible = has_motion and node.feature_type != FeatureType.CIRCLE
	var is_circle := is_feature and node.is_circle()
	for control in _circle_boxes:
		control.visible = is_circle
	for control in _hotspot_boxes:
		control.visible = is_hotspot
	for control in _step_boxes:
		control.visible = is_hotspot or is_crust

	if not editable:
		return

	_filling = true
	name_edit.text = node.title
	enabled_check.button_pressed = node.enabled
	if is_feature:
		type_selector.select(_type_index(node.feature_type))
		icon_selector.select(_item_index(icon_selector, node.icon))
		_show_color()
		from_spin.value = node.time_range.y
		to_spin.value = node.time_range.x
		_show_area()
		if is_circle:
			_show_circle()
		if is_hotspot:
			_show_hotspot()
		if is_hotspot or is_crust:
			step_spin.value = node.time_step
		closed_check.button_pressed = node.closed
		_fill_sections()
		_show_topology_note()
		_fill_coupling()
	else:
		_show_style()
	_filling = false
	_update_section_buttons()
	_update_keyframes()
	_update_coupling()


# The current time moved: Delete only works on a keyframe the time sits on, and
# a section can be followed at one time and broken at another. Nothing else in
# the panel depends on the time.
func show_time() -> void:
	if node == null or node.is_root:
		return
	if node.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		_refill_sections()
	_update_keyframes()
	_update_coupling()


# The planet radius preference changed: the areas the panel shows are read
# against it.
func show_radius() -> void:
	if node == null:
		return
	if node.is_root:
		placeholder.text = _root_sentence()
	elif not node.is_group:
		_show_area()


func _root_sentence() -> String:
	var radius := Config.get_planet_radius()
	return ("The %s group holds everything and has nothing to edit. The planet's radius " +
		"is %.0f km and its surface %s.") % [
		node.title, radius, Measure.format_area(Measure.planet_area(radius))]


func _type_index(type_id: String) -> int:
	for index in type_selector.item_count:
		if type_selector.get_item_metadata(index) == type_id:
			return index
	return -1


# The Area row, shown only while the feature is drawn as a polygon: the area on
# one line and its share of the planet on the next, when the share is not too
# small to write.
func _show_area() -> void:
	var shown := node.has_geometry() and node.drawn_as() == Feature.GeometryKind.POLYGON
	area_label.visible = shown
	_area_caption.visible = shown
	if not shown:
		return
	var radius := Config.get_planet_radius()
	var area := Measure.geometry_area(node, radius)
	var share := Measure.format_share(area, radius)
	area_label.text = Measure.format_area(area) + ("" if share.is_empty() else "\n" + share)


### The section table


# Every section of the topology at the current time, so the table can say which
# of them are broken. An empty list while anything but a topology is selected.
func _resolved_sections() -> Array:
	if document == null or node == null or node.is_group \
			or node.geometry_kind != Feature.GeometryKind.TOPOLOGY:
		return []
	return Topology.resolve(document.root, node, document.current_time)


func _show_topology_note() -> void:
	if node == null or node.is_group:
		return
	if node.is_crust():
		topology_note.text = Crust.describe(document.root if document != null else null, node)
	elif node.midway:
		topology_note.text = "Midway between two sections"


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


func _on_closed_toggled(on: bool) -> void:
	if _filling or node == null or on == node.closed:
		return
	var error := document.set_topology_closed(node, on)
	if not error.is_empty():
		closed_check.set_pressed_no_signal(node.closed)
		rejected.emit(error)
		return
	_show_area()
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
	_show_topology_note()
	if not node.is_group:
		_show_area()
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
	var error := document.set_keyframe(node, document.current_time,
		Feature.keyframe_rotation(document.root, node, document.current_time))
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


### Coupling


# The picker lists every feature the selected one could follow, in tree order,
# and the list holds its spans. The picked parent is kept across a refill.
func _fill_coupling() -> void:
	var picked := picked_parent()
	parent_selector.clear()
	spans.clear()
	if document == null or node == null or node.is_group:
		return
	for leaf in _leaves(document.root, []):
		if leaf == node or leaf.geometry_kind == Feature.GeometryKind.TOPOLOGY \
				or leaf.is_circle() or leaf.is_hotspot():
			continue
		parent_selector.add_item(leaf.title)
		parent_selector.set_item_metadata(parent_selector.item_count - 1, leaf.uuid)
		if leaf.uuid == picked:
			parent_selector.select(parent_selector.item_count - 1)
	if parent_selector.selected < 0 and parent_selector.item_count > 0:
		parent_selector.select(0)

	var nodes := Coupling.index(document.root)
	var root := spans.create_item()
	for index in node.couplings.size():
		var span: Coupling = node.couplings[index]
		var item := spans.create_item(root)
		item.set_metadata(0, index)
		item.set_text(0, Coupling.parents_label(nodes, span))
		item.set_text(1, String.num(span.from))
		item.set_text(2, String.num(span.to))
		var problem := Coupling.parent_problem(nodes, node, span)
		if not problem.is_empty():
			for column in SPAN_COLUMNS.size():
				item.set_custom_color(column, BROKEN_SECTION_COLOR)
				item.set_tooltip_text(column, problem)


func _leaves(group: Feature, into: Array[Feature]) -> Array[Feature]:
	for child in group.children:
		if child.is_group:
			_leaves(child, into)
		else:
			into.append(child)
	return into


# The uuid of the feature the picker shows, empty when it shows none.
func picked_parent() -> String:
	if parent_selector.selected < 0:
		return ""
	return str(parent_selector.get_item_metadata(parent_selector.selected))


# Pick a parent by title, for the scripted session.
func pick_parent(title: String) -> String:
	for index in parent_selector.item_count:
		if parent_selector.get_item_text(index) == title:
			parent_selector.select(index)
			_update_coupling()
			return ""
	return "the picker offers no %s" % title


# Pick a parent by uuid, which is what a click on the planet comes back with.
# Returns why the picker does not offer it, or an empty string once it shows it.
func pick_parent_uuid(uuid: String) -> String:
	for index in parent_selector.item_count:
		if str(parent_selector.get_item_metadata(index)) == uuid:
			parent_selector.select(index)
			_update_coupling()
			return ""
	if node != null and node.uuid == uuid:
		return "A feature cannot follow itself."
	var picked: Feature = Coupling.index(document.root).get(uuid)
	if picked != null and picked.is_circle():
		return Coupling.CIRCLE_PARENT_PROBLEM
	if picked != null and picked.is_hotspot():
		return Coupling.HOTSPOT_PARENT_PROBLEM
	return "That feature is not one of the ones to follow."


# Make the feature with that uuid the plate, which is what a click on the
# planet comes back with. Returns why it cannot be, or an empty string once it is.
func pick_plate_uuid(uuid: String) -> String:
	var problem := Hotspot.plate_problem(document.root, node, uuid)
	if not problem.is_empty():
		return problem
	for index in plate_selector.item_count:
		if str(plate_selector.get_item_metadata(index)) == uuid:
			plate_selector.select(index)
	_commit_hotspot()
	return ""


# Whether the pick mode is on, which is what the button shows. The mode itself
# is the Application's; see Docs/Properties.md#coupling.
func picking_parent() -> bool:
	return pick_parent_button.button_pressed


# Which pointer shows the pick mode as on: the Follow row's or the Plate row's.
func show_picking(parent: bool, plate: bool) -> void:
	pick_parent_button.set_pressed_no_signal(parent)
	pick_plate_button.set_pressed_no_signal(plate)


# Whether the Topology tool is armed, which is what the section Pick toggle
# shows. The tool is the Application's.
func show_section_picking(on: bool) -> void:
	pick_section_button.set_pressed_no_signal(on)


# What the feature follows at the current time, and which buttons work there.
func _update_coupling() -> void:
	var feature := document != null and node != null and not node.is_group
	var span := Coupling.span_at(node, document.current_time) if feature else null
	coupled_label.remove_theme_color_override("font_color")
	coupled_label.tooltip_text = ""
	if span == null:
		coupled_label.text = "nothing"
	else:
		var nodes := Coupling.index(document.root)
		coupled_label.text = Coupling.parents_label(nodes, span)
		var problem := Coupling.parent_problem(nodes, node, span)
		if not problem.is_empty():
			coupled_label.add_theme_color_override("font_color", BROKEN_SECTION_COLOR)
			coupled_label.tooltip_text = problem
	decouple_button.disabled = span == null
	couple_button.disabled = not feature or span != null or parent_selector.selected < 0
	pick_parent_button.disabled = not feature or parent_selector.item_count == 0
	remove_span_button.disabled = not feature or node.couplings.is_empty()


# Which span is picked in the list, the last one standing in when none is.
func selected_span() -> int:
	if node == null or node.is_group or node.couplings.is_empty():
		return -1
	var item := spans.get_selected()
	if item != null and item.get_metadata(0) != null:
		return int(item.get_metadata(0))
	return node.couplings.size() - 1


func select_span(index: int) -> void:
	var root := spans.get_root()
	if root == null or index < 0 or index >= root.get_child_count():
		return
	spans.deselect_all()
	root.get_child(index).select(0)


func _on_couple_pressed() -> void:
	if node == null or node.is_group:
		return
	var parent: Feature = Coupling.index(document.root).get(picked_parent())
	_after_coupling_edit(document.couple(node, parent, document.current_time))


func _on_decouple_pressed() -> void:
	if node == null or node.is_group:
		return
	_after_coupling_edit(document.decouple(node, document.current_time))


func _on_remove_span_pressed() -> void:
	var index := selected_span()
	if index < 0:
		return
	_after_coupling_edit(document.remove_coupling(node, index))


func _after_coupling_edit(error: String) -> void:
	if not error.is_empty():
		rejected.emit(error)
		return
	_fill_coupling()
	_update_coupling()
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
	# Circles and hotspots show rows no other type has, so the whole panel is filled
	# again rather than the color alone.
	show_node(node)
	edited.emit()


func _on_icon_selected(index: int) -> void:
	if _filling or node == null:
		return
	var error := document.set_icon(node, str(icon_selector.get_item_metadata(index)))
	if not error.is_empty():
		_filling = true
		icon_selector.select(_item_index(icon_selector, node.icon))
		_filling = false
		rejected.emit(error)
		return
	edited.emit()


# Call while _filling.
func _show_circle() -> void:
	axis_circles_check.button_pressed = node.polar
	axis_lat_spin.value = node.axis.x
	axis_lon_spin.value = node.axis.y
	radius_spin.value = node.radius
	circle_segments_spin.value = node.circle_segments


func _commit_circle() -> void:
	if _filling or node == null or not node.is_circle():
		return
	var axis := Vector2(_unrounded(axis_lat_spin, node.axis.x),
		_unrounded(axis_lon_spin, node.axis.y))
	var radius := _unrounded(radius_spin, node.radius)
	var segments := int(circle_segments_spin.value)
	var polar := axis_circles_check.button_pressed
	var same := axis == node.axis and radius == node.radius \
		and segments == node.circle_segments and polar == node.polar
	if same and node.has_geometry():
		return
	var error := document.set_circle(node, axis, radius, segments, polar)
	if not error.is_empty():
		_filling = true
		_show_circle()
		_filling = false
		rejected.emit(error)
		return
	edited.emit()


# Call while _filling. The plate list is every feature that can be the plate, in
# tree order, after None.
func _show_hotspot() -> void:
	plate_selector.clear()
	plate_selector.add_item("None")
	plate_selector.set_item_metadata(0, "")
	plate_selector.select(0)
	for leaf in _leaves(document.root, []):
		if not Hotspot.plate_problem(document.root, node, leaf.uuid).is_empty():
			continue
		plate_selector.add_item(leaf.title)
		plate_selector.set_item_metadata(plate_selector.item_count - 1, leaf.uuid)
		if leaf.uuid == node.plate_uuid:
			plate_selector.select(plate_selector.item_count - 1)
	pick_plate_button.disabled = plate_selector.item_count < 2


func _commit_hotspot() -> void:
	if _filling or node == null or not node.is_hotspot():
		return
	var plate := str(plate_selector.get_item_metadata(plate_selector.selected))
	if plate == node.plate_uuid:
		return
	var error := document.set_hotspot(node, node.hotspot, plate, node.time_step)
	if not error.is_empty():
		_filling = true
		_show_hotspot()
		_filling = false
		rejected.emit(error)
		return
	edited.emit()


# The Step (My) box, for whichever of the two carries it. A hotspot goes
# through set_hotspot(), which holds its place and plate as well, and a crust
# through set_crust_step(), the one edit it has.
func _commit_step() -> void:
	if _filling or node == null or step_spin.value == node.time_step:
		return
	var step := step_spin.value
	var error := "Only a hotspot and a crust are sampled over time."
	if node.is_hotspot():
		error = document.set_hotspot(node, node.hotspot,
			str(plate_selector.get_item_metadata(plate_selector.selected)), step)
	elif node.is_crust():
		error = document.set_crust_step(node, step)
	if not error.is_empty():
		_filling = true
		step_spin.value = node.time_step
		_filling = false
		rejected.emit(error)
		return
	edited.emit()


# A box shows a picked axis rounded to its step. The value the feature holds is
# kept while the box still shows it, so editing the radius does not move the
# axis by the rounding.
func _unrounded(spin: SpinBox, held: float) -> float:
	return held if absf(spin.value - held) <= spin.step * 0.5 else spin.value


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
	ramp_row.colors = style.ramp_colors
	ramp_row.span_spin.set_value_no_signal(style.ramp_span)
	palette_selector.clear()
	var listed := Palette.choices()
	for key in listed:
		palette_selector.add_item(str(listed[key]))
		palette_selector.set_item_metadata(palette_selector.item_count - 1, key)
	if not listed.has(style.palette):
		palette_selector.add_item(style.palette.get_file())
		palette_selector.set_item_metadata(palette_selector.item_count - 1, style.palette)
		palette_selector.set_item_tooltip(palette_selector.item_count - 1, style.palette)
	palette_selector.select(_item_index(palette_selector, style.palette))


# Give the group on show the palette read from a file, as one edit. The file
# joins the palette choices under its name, the way _show_style() lists it.
func load_palette(path: String) -> void:
	if node == null or node.is_root or not node.is_group:
		return
	if _item_index(palette_selector, path) < 0:
		palette_selector.add_item(path.get_file())
		palette_selector.set_item_metadata(palette_selector.item_count - 1, path)
	palette_selector.select(_item_index(palette_selector, path))
	_commit_style()


func _item_index(selector: OptionButton, id: String) -> int:
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == id:
			return index
	return -1


func _item_text_index(selector: OptionButton, text: String) -> int:
	for index in selector.item_count:
		if selector.get_item_text(index) == text:
			return index
	return -1


# Open the picker of the Colour row. The feature tree's swatch asks for this
# rather than carrying a picker of its own, so the colour is picked where it is
# shown and there is still only one place it is edited.
func open_color_picker() -> void:
	if node == null or node.is_root or not color_button.is_visible_in_tree():
		return
	var popup := color_button.get_popup()
	popup.reset_size()
	popup.popup(Rect2i(Vector2i(color_button.get_screen_position())
		+ Vector2i(0, int(color_button.size.y)), popup.size))


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


func _on_ramp_previewed() -> void:
	if _filling or node == null or node.is_root or not node.is_group:
		return
	node.style.ramp_colors = ramp_row.colors
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
	Helpers.remember_color(color_button.color)
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
	style.ramp_colors = ramp_row.colors
	style.ramp_span = ramp_row.span_spin.value
	var error := document.set_style(node, style)
	if not error.is_empty():
		rejected.emit(error)
		return
	Helpers.remember_color(style.color)
	recolored.emit()


func _commit_time_range() -> void:
	if _filling or node == null or node.is_group:
		return
	# From is the older end and To the younger one; the vector keeps the file's
	# order, younger first.
	var wanted := Vector2i(int(to_spin.value), int(from_spin.value))
	if wanted == node.time_range:
		return
	var error := document.set_time_range(node, wanted)
	if not error.is_empty():
		_filling = true
		from_spin.value = node.time_range.y
		to_spin.value = node.time_range.x
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
		return {"showing": "root", "placeholder": placeholder.text, "width": size.x,
			"planet_area_km2": Measure.planet_area(Config.get_planet_radius())}
	var data := {
		"showing": "group" if node.is_group else "feature",
		"width": size.x,
		"name": name_edit.text,
		"enabled": enabled_check.button_pressed,
		"color_picker_open": color_button.get_popup().visible,
		"color_presets": _presets_to_json(),
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
			"ramp_colors": ramp_row.colors.map(
				func(c: Color) -> Array: return [c.r, c.g, c.b, c.a]),
			"ramp_span": ramp_row.span_spin.value,
		}
		data["style_label"] = style_selector.get_item_text(mode) if mode >= 0 else ""
		data["tooltips"] = {"style": style_selector.tooltip_text}
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
	var chosen_icon := icon_selector.selected
	data["icon"] = str(icon_selector.get_item_metadata(chosen_icon)) if chosen_icon >= 0 else ""
	data["icons"] = range(icon_selector.item_count).map(
		func(index: int) -> String: return str(icon_selector.get_item_metadata(index)))
	data["color"] = [color_button.color.r, color_button.color.g,
		color_button.color.b, opacity_spin.value / 100.0]
	data["opacity"] = int(opacity_spin.value)
	# `time_range` keeps the file's order, younger first, whatever the two boxes
	# are labelled; `time_from` and `time_to` are what each box is showing and
	# are the fields `set_property` drives.
	data["time_range"] = [int(to_spin.value), int(from_spin.value)]
	data["time_from"] = int(from_spin.value)
	data["time_to"] = int(to_spin.value)
	data["tooltips"] = {"time_from": from_spin.tooltip_text, "time_to": to_spin.tooltip_text}
	if area_label.visible:
		data["area"] = area_label.text
	data["area_km2"] = Measure.geometry_area(node, Config.get_planet_radius())
	if keyframe_count.get_parent().visible:
		data["keyframes"] = {
			"count": keyframe_count.text.to_int(),
			"key": not key_button.disabled,
			"delete": not delete_key_button.disabled,
		}
	# A circle keeps the keyframe row but not the coupling rows, so what those
	# rows would hold is reported anyway, marked as not shown.
	if coupled_label.get_parent().visible:
		data["coupling"] = _coupling_to_json()
		data["coupling"]["hidden"] = false
	elif keyframe_count.get_parent().visible:
		data["coupling"] = _coupling_to_json()
		data["coupling"]["hidden"] = true
	data["sections"] = _sections_to_json()
	if closed_check.visible:
		data["closed"] = closed_check.button_pressed
	if sections.visible:
		data["picking_sections"] = pick_section_button.button_pressed
	if topology_note.visible:
		data["topology_note"] = topology_note.text
	if node.is_crust():
		data["crust_chunks"] = Crust.chunks(node)
		data["crust_step"] = step_spin.value
	if pick_axis_button.visible:
		data["circle"] = {
			"polar": axis_circles_check.button_pressed,
			"axis": [axis_lat_spin.value, axis_lon_spin.value],
			"radius": radius_spin.value,
			"circle_segments": int(circle_segments_spin.value),
			"pick_axis": not pick_axis_button.disabled,
		}
	if plate_row.visible:
		data["hotspot"] = {
			"position": [node.hotspot.x, node.hotspot.y] if Hotspot.placed(node) else null,
			"plate": plate_selector.get_item_text(plate_selector.selected),
			"plates": range(plate_selector.item_count).map(
				func(index: int) -> String: return plate_selector.get_item_text(index)),
			"samples": Hotspot.track(document.root, node, document.current_time,
				Config.get_skip_increment()).size(),
			"pick": not pick_plate_button.disabled,
			"picking": pick_plate_button.button_pressed,
			"time_step": step_spin.value,
		}
	return data


# The colours the Colour row's picker offers as presets, which it takes from the
# shared list whenever it opens.
func _presets_to_json() -> Array:
	var list: Array = []
	for color in color_button.get_picker().get_presets():
		list.append([color.r, color.g, color.b, color.a])
	return list


# The coupling rows and the span list as they stand, read off the widgets.
func _coupling_to_json() -> Dictionary:
	var rows: Array = []
	var root := spans.get_root()
	if root != null:
		for item in root.get_children():
			rows.append({
				"parent": item.get_text(0),
				"from": float(item.get_text(1)),
				"to": float(item.get_text(2)),
				"broken": item.get_custom_color(0) == BROKEN_SECTION_COLOR,
			})
	var couple_row := parent_selector.get_parent()
	var caption: Label = _rows.filter(
		func(row: Dictionary) -> bool: return row["control"] == couple_row)[0]["label"]
	return {
		"caption": caption.text,
		"coupled_to": coupled_label.text,
		"parents": range(parent_selector.item_count).map(
			func(index: int) -> String: return parent_selector.get_item_text(index)),
		"parent": parent_selector.get_item_text(parent_selector.selected)
			if parent_selector.selected >= 0 else "",
		"couple": not couple_button.disabled,
		"decouple": not decouple_button.disabled,
		"pick": not pick_parent_button.disabled,
		"picking": pick_parent_button.button_pressed,
		"remove": not remove_span_button.disabled,
		"spans": rows,
	}


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
		"icon":
			if node.is_group:
				return "a group has no icon; only a feature has one"
			var at := _item_index(icon_selector, str(value))
			if at < 0:
				return "the icon selector offers no %s" % value
			icon_selector.select(at)
			_on_icon_selected(at)
		"style", "palette":
			if not node.is_group:
				return "a feature has no %s; its group does" % field
			var selector := style_selector if field == "style" else palette_selector
			var at := _item_index(selector, str(value))
			if at < 0:
				return "the %s selector offers no %s" % [field, value]
			selector.select(at)
			_commit_style()
		"ramp_colors":
			if not node.is_group:
				return "a feature has no ramp_colors; its group does"
			if value is not Array or (value as Array).size() < Palette.MIN_RAMP_COLORS:
				return "a ramp takes a list of at least %d colours" % Palette.MIN_RAMP_COLORS
			ramp_row.colors = GroupStyle.colors_from(value)
			_commit_style()
		"ramp_span":
			if not node.is_group:
				return "a feature has no ramp_span; its group does"
			ramp_row.span_spin.value = float(value)
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
		"axis", "radius", "circle_segments", "polar":
			if not pick_axis_button.visible:
				return "only a circle has %s" % field
			_filling = true
			if field == "polar":
				axis_circles_check.button_pressed = bool(value)
			elif field == "axis":
				axis_lat_spin.value = float(value[0])
				axis_lon_spin.value = float(value[1])
			elif field == "radius":
				radius_spin.value = float(value)
			else:
				circle_segments_spin.value = float(value)
			_filling = false
			_commit_circle()
		"closed":
			if not closed_check.visible:
				return "only a topology built from its sections can be closed"
			closed_check.button_pressed = bool(value)
		"plate":
			if not plate_row.visible:
				return "only a hotspot has a plate"
			var at := 0 if str(value).is_empty() else _item_text_index(plate_selector, str(value))
			if at < 0:
				return "the plate selector offers no %s" % value
			plate_selector.select(at)
			_commit_hotspot()
		"time_step":
			if not step_spin.visible:
				return "only a hotspot and a crust are sampled over time"
			step_spin.value = float(value)
			_commit_step()
		_:
			return "no such property: %s" % field
	return ""
