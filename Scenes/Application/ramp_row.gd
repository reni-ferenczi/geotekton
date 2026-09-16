class_name RampRow
extends HFlowContainer

# The custom palette's colours and the span between two of them: one picker per
# colour, a + that adds another and a − on every colour past the second, with
# the span beside them. The Properties panel edits a group's ramp and the View
# settings dialog the root's, and both put one of these in, so the two cannot
# drift apart. See Docs/Styling.md.

# A colour is being dragged in a picker: show it on the globe, record nothing.
signal previewed

# A picker closed, a colour was added or taken away, or the span moved: one edit
# and one undo version.
signal committed

# The span box says what My it counts in, either in its suffix or in the
# sentence, depending on which of the two rows this is.
const SPAN_TOOLTIP := "How old a feature is%s when it reaches the next colour"

var span_spin: SpinBox

var _colors: Array[Color] = []
var _pickers: HFlowContainer
var _rebuild_pending := false

# The colours of the ramp, oldest last. Fewer than two is no ramp at all, so
# anything shorter comes back as the default one.
var colors: Array[Color]:
	get:
		return _colors.duplicate()
	set(value):
		_colors = value.duplicate() if value.size() >= Palette.MIN_RAMP_COLORS \
			else Palette.DEFAULT_RAMP_COLORS.duplicate()
		_rebuild()


func _init(max_span: float, span_suffix: String = "") -> void:
	name = "RampRow"

	# A flow rather than a box, so stops the row is too narrow for go on to
	# further lines instead of pushing the + and the span off the panel.
	_pickers = HFlowContainer.new()
	_pickers.name = "RampColors"
	_pickers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_pickers)

	span_spin = SpinBox.new()
	span_spin.name = "RampSpan"
	span_spin.min_value = 1
	span_spin.max_value = max_span
	span_spin.step = 1
	span_spin.suffix = span_suffix
	# The box keeps its own height beside the first line when the stops wrap.
	# The row is a flow as well, so a panel too narrow for the stops and the box
	# side by side puts the box on a line of its own.
	span_spin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	span_spin.tooltip_text = SPAN_TOOLTIP % ("" if not span_suffix.is_empty() else ", in My,")
	span_spin.value_changed.connect(func(_value: float) -> void: committed.emit())
	add_child(span_spin)

	colors = Palette.DEFAULT_RAMP_COLORS.duplicate()


# The pickers as the colours stand. Rebuilt rather than added to, so the − on
# each colour past the second is where it belongs however many there are.
#
# Rebuilt a frame later rather than at once. What asks for a rebuild is a
# signal of one of the widgets about to be replaced: a + or − being pressed, or
# a picker's popup closing, which commits the style and has the panel set the
# colours again. Freeing that widget while the viewport is still delivering the
# event to it crashes the engine.
func _rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild_now.call_deferred()


func _rebuild_now() -> void:
	_rebuild_pending = false
	for child in _pickers.get_children():
		_pickers.remove_child(child)
		child.queue_free()

	for i in _colors.size():
		# A colour and its − wrap as one, so the − never opens a line on its own.
		var stop := HBoxContainer.new()
		stop.name = "RampStop%d" % i
		var picker := Helpers.color_button("RampColor%d" % i, Helpers.COLOR_TOOLTIP)
		picker.custom_minimum_size = Vector2(40, 28)
		picker.edit_alpha = false
		picker.color = _colors[i]
		picker.color_changed.connect(func(color: Color) -> void:
			_colors[i] = color
			previewed.emit())
		picker.popup_closed.connect(func() -> void: committed.emit())
		stop.add_child(picker)
		if i >= Palette.MIN_RAMP_COLORS:
			stop.add_child(_button("DropRampColor%d" % i, "−",
				"Take this colour out of the ramp",
				func() -> void: _colors.remove_at(i)))
		_pickers.add_child(stop)

	_pickers.add_child(_button("AddRampColor", "+", "Add another colour to the ramp",
		func() -> void: _colors.append(_colors[-1])))


# A button that changes the list of colours, asks for the rebuild and reports
# the edit. The rebuild replaces the button itself, a frame later.
func _button(button_name: String, text_: String, tooltip: String, change: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text_
	button.tooltip_text = tooltip
	button.pressed.connect(func() -> void:
		change.call()
		_rebuild()
		committed.emit())
	return button
