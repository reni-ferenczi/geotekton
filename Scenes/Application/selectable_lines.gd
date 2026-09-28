extends TextEdit
class_name SelectableLines

# SelectableText for a value that runs over more than one line: a TextEdit
# that cannot be edited, drawn without a box in the Label's font and color, as
# tall as its lines and wrapped at the width it is given (GP-0144).

func _init() -> void:
	editable = false
	focus_mode = Control.FOCUS_CLICK
	wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	scroll_fit_content_height = true
	for style in ["normal", "read_only", "focus"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())


func _ready() -> void:
	add_theme_font_override("font", get_theme_font("font", "Label"))
	add_theme_font_size_override("font_size", get_theme_font_size("font_size", "Label"))
	add_theme_color_override("font_readonly_color", get_theme_color("font_color", "Label"))
	add_theme_constant_override("line_spacing", get_theme_constant("line_spacing", "Label"))


func _input(event: InputEvent) -> void:
	SelectableText.release_on_click_outside(self, event)
