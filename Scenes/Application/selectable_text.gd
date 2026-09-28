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


func _input(event: InputEvent) -> void:
	release_on_click_outside(self, event)


# Let the focus go when a click lands outside the control, so a value clicked
# once does not keep the keyboard's Ctrl+C from the Edit menu.
static func release_on_click_outside(control: Control, event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and control.has_focus() \
			and not control.get_global_rect().has_point(click.position):
		control.release_focus()
