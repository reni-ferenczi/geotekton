extends TestCase

# The outline sizes are declared twice: as uniform defaults in the shader, which
# is what is drawn, and as constants in Planet, which the preferences multiply.
# Nothing makes the two agree at runtime, so this is what stops them drifting
# apart in silence.

const SHADER := "res://Scenes/Planet/planet.gdshader"


func test_the_outline_defaults_match_the_shader() -> void:
	var declared := _uniform_defaults()
	if declared.is_empty():
		return
	assert_close(declared.get("outline_dot_radius", -1.0), Planet.DEFAULT_DOT_RADIUS, 1e-9,
		"Planet.DEFAULT_DOT_RADIUS is what the shader draws a vertex marker at")
	assert_close(declared.get("outline_line_width", -1.0), Planet.DEFAULT_LINE_WIDTH, 1e-9,
		"Planet.DEFAULT_LINE_WIDTH is what the shader draws an outline line at")
	assert_close(declared.get("geometry_line_width", -1.0), Planet.GEOMETRY_LINE_WIDTH, 1e-9,
		"Planet.GEOMETRY_LINE_WIDTH is what the shader draws a feature line at")


# The float uniforms the shader declares, by name, read out of its source. The
# engine keeps the defaults on the compiled shader rather than anywhere a
# headless run can reach them, so the declaration itself is what is read.
func _uniform_defaults() -> Dictionary:
	var file := FileAccess.open(SHADER, FileAccess.READ)
	if file == null:
		fail("cannot read %s" % SHADER)
		return {}
	var pattern := RegEx.create_from_string(
		"uniform\\s+float\\s+(\\w+)\\s*=\\s*([-0-9.eE]+)\\s*;")
	var defaults := {}
	for found in pattern.search_all(file.get_as_text()):
		defaults[found.get_string(1)] = float(found.get_string(2))
	assert_true(not defaults.is_empty(), "the shader declares float uniforms")
	return defaults
