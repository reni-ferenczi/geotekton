extends LineEdit
class_name SelectableText

# A value that reads like a Label but can be selected with the mouse and copied
# with Ctrl+C or the right click menu (GP-0144). It is a LineEdit that cannot
# be edited, drawn without a box, in the Label's font and color, so it looks as
# the Label did.
#
# A read-only field does not count as typing (Application._typing()), so Space
# and the tool keys still reach the application while it holds the focus. A
# click anywhere else lets the focus go, so Ctrl+C goes back to the Edit menu.
#
# Only the data in it can be selected, not the words around it: show_data() says
# which is which (GP-0148, DataSelection).

var data := DataSelection.new(self)
# The text shaped as the field draws it, to tell which character is where.
var _line := TextLine.new()


func _init() -> void:
	editable = false
	flat = true
	# No width of its own, as a clipped Label has none; a field that should fit
	# its text sets expand_to_text_length.
	add_theme_constant_override("minimum_character_width", 0)
	focus_mode = Control.FOCUS_CLICK
	mouse_default_cursor_shape = Control.CURSOR_IBEAM
	for style in ["normal", "read_only", "focus"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())


func _ready() -> void:
	add_theme_font_override("font", get_theme_font("font", "Label"))
	if not has_theme_font_size_override("font_size"):
		add_theme_font_size_override("font_size", get_theme_font_size("font_size", "Label"))
	if not has_theme_color_override("font_uneditable_color"):
		reset_color()


# The color the text is drawn in, which a read-only LineEdit takes from
# font_uneditable_color rather than font_color.
func set_color(color: Color) -> void:
	add_theme_color_override("font_uneditable_color", color)


# Back to the Label's color.
func reset_color() -> void:
	set_color(get_theme_color("font_color", "Label"))


# The text of `format` with `values` in its %s placeholders; only the values
# can be selected.
func show_data(format: String, values: Array = []) -> void:
	# Setting the text, even to what it already is, drops the caret and the
	# selection, and the panel refills its fields whenever anything moves, so
	# a selection only lasted until the next refresh (GP-0153).
	var composed := data.compose(format, values)
	if composed != text:
		text = composed


func _gui_input(event: InputEvent) -> void:
	data.gui_input(event)


func _input(event: InputEvent) -> void:
	release_on_click_outside(self, event)


# The caret offset nearest a local point. Plain left aligned text drawn from
# x 0, shifted by the scroll, as the field draws it.
func offset_at(point: Vector2) -> int:
	_line.clear()
	_line.add_string(text, get_theme_font("font"), get_theme_font_size("font_size"))
	return _line.hit_test(point.x - get_scroll_offset())


func point_at(offset: int) -> Vector2:
	var width := get_theme_font("font").get_string_size(text.left(offset),
		HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x
	return Vector2(width + get_scroll_offset(), size.y / 2.0)


func selection_range() -> Vector3i:
	if not has_selection():
		return Vector3i.ZERO
	var from := get_selection_from_column()
	var to := get_selection_to_column()
	return Vector3i(from, to, to if caret_column == from else from)


func select_range(anchor: int, caret: int) -> void:
	select(mini(anchor, caret), maxi(anchor, caret))
	caret_column = caret


# Let the focus go when a click lands outside the control, so a value clicked
# once does not keep the keyboard's Ctrl+C from the Edit menu.
static func release_on_click_outside(control: Control, event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and control.has_focus() \
			and not control.get_global_rect().has_point(click.position):
		control.release_focus()
