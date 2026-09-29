extends RefCounted
class_name DataSelection

# Which parts of a SelectableText or SelectableLines are data, and the mouse
# and key handling that keeps the selection to them (GP-0148). Data is what a
# user would copy: a number with its marks (°, %, km²), a feature or file
# name. The words around it stay plain text and cannot be selected.
#
# compose() builds the text from a format whose %s placeholders take the
# data, so "Surface area %s" makes only the area selectable. A text set
# directly, without compose(), is data as a whole.
#
# The control answers, in offsets into its text: offset_at() for a local
# point, point_at() for an offset, selection_range() as (from, to, anchor),
# and select_range() for an anchor and a caret.

const NONE := Vector2i(-1, -1)

var control: Control
var _text := ""
var _spans: Array[Vector2i] = []
# The span a left drag started in; the drag stays inside it.
var _held := NONE


func _init(owner: Control) -> void:
	control = owner
	# Select All in the right click menu, which the control does after this.
	control.get_menu().id_pressed.connect(func(_id: int) -> void: keep.call_deferred())


# The text of `format` with `values` in its %s placeholders, which are the data.
func compose(format: String, values: Array = []) -> String:
	var pieces := format.split("%s")
	_text = ""
	_spans.clear()
	for i in pieces.size():
		_text += pieces[i]
		if i < pieces.size() - 1 and i < values.size():
			var value := str(values[i])
			_spans.append(Vector2i(_text.length(), _text.length() + value.length()))
			_text += value
	return _text


# The data in the control's text, as [from, to) offsets.
func spans() -> Array[Vector2i]:
	var text: String = control.text
	if text == _text:
		return _spans
	return [Vector2i(0, text.length())]


# The span an offset is in or at the edge of, or NONE.
func span_at(offset: int) -> Vector2i:
	for span in spans():
		if span.x < span.y and span.x <= offset and offset <= span.y:
			return span
	return NONE


# Called from the control's _gui_input(), before the control handles the event.
func gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _held != NONE:
			# Pulled back to the edge of the span, so the control's own drag
			# selects no further.
			var offset: int = control.offset_at(motion.position)
			if offset < _held.x or offset > _held.y:
				motion.position = control.point_at(clampi(offset, _held.x, _held.y))
		else:
			control.mouse_default_cursor_shape = Control.CURSOR_ARROW \
				if span_at(control.offset_at(motion.position)) == NONE else Control.CURSOR_IBEAM
		return

	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		_held = span_at(control.offset_at(click.position)) if click.pressed else NONE
		if click.pressed and _held == NONE:
			# A word: nothing to select, nor to start a drag from.
			control.accept_event()
			control.deselect()
			return
	# Ctrl+A, Shift and the arrows, a double or triple click: whatever the
	# control selected, cut it back once it has.
	keep.call_deferred()


# Cuts the selection back to the data span that holds its anchor, or to the
# first span it reaches, and to nothing when it reaches none.
func keep() -> void:
	var selected: Vector3i = control.selection_range()
	if selected.x == selected.y:
		return
	var kept := NONE
	for span in spans():
		var cut := Vector2i(maxi(selected.x, span.x), mini(selected.y, span.y))
		if cut.x < cut.y and (kept == NONE or span.x <= selected.z and selected.z <= span.y):
			kept = cut
	if kept == NONE:
		control.deselect()
	elif kept != Vector2i(selected.x, selected.y):
		if selected.z == selected.y:
			control.select_range(kept.y, kept.x)
		else:
			control.select_range(kept.x, kept.y)
