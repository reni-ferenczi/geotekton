extends TextEdit
class_name SelectableLines

# SelectableText for a value that runs over more than one line: a TextEdit
# that cannot be edited, drawn without a box in the Label's font and color, as
# tall as its lines and wrapped at the width it is given (GP-0144). Only the
# data in it can be selected (GP-0148, DataSelection).

var data := DataSelection.new(self)


func _init() -> void:
	editable = false
	focus_mode = Control.FOCUS_CLICK
	wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	scroll_fit_content_height = true
	# The selection is cut back where it changes, which covers the drag as well:
	# a TextEdit drags from the pointer, not from the events.
	caret_changed.connect(data.keep)
	for style in ["normal", "read_only", "focus"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())


func _ready() -> void:
	add_theme_font_override("font", get_theme_font("font", "Label"))
	add_theme_font_size_override("font_size", get_theme_font_size("font_size", "Label"))
	add_theme_color_override("font_readonly_color", get_theme_color("font_color", "Label"))
	add_theme_constant_override("line_spacing", get_theme_constant("line_spacing", "Label"))


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
	SelectableText.release_on_click_outside(self, event)


# Offsets into the text run over the lines, one more for each line break.
func offset_at(point: Vector2) -> int:
	var at := get_line_column_at_pos(Vector2i(point))
	return _offset(at.y, at.x)


func point_at(offset: int) -> Vector2:
	var at := _line_column(offset)
	return Vector2(get_pos_at_line_column(at.y, at.x)) - Vector2(0.0, get_line_height() / 2.0)


func selection_range() -> Vector3i:
	if not has_selection():
		return Vector3i.ZERO
	return Vector3i(_offset(get_selection_from_line(), get_selection_from_column()),
		_offset(get_selection_to_line(), get_selection_to_column()),
		_offset(get_selection_origin_line(), get_selection_origin_column()))


func select_range(anchor: int, caret: int) -> void:
	var from := _line_column(anchor)
	var to := _line_column(caret)
	select(from.y, from.x, to.y, to.x)


func _offset(line: int, column: int) -> int:
	for before in line:
		column += get_line(before).length() + 1
	return column


# (column, line) of an offset.
func _line_column(offset: int) -> Vector2i:
	var line := 0
	while line < get_line_count() - 1 and offset > get_line(line).length():
		offset -= get_line(line).length() + 1
		line += 1
	return Vector2i(offset, line)
