extends TestCase

# The numbers planet.gdshader carries a second copy of.
#
# The shader holds the inverse of every map projection again in GLSL, because a
# fragment cannot call GDScript, and with it the Robinson tables, the extent
# that sizes the Robinson sheet, the slack the edges are tested with and the
# name of each projection. Nothing in either file makes the other follow, so
# this reads the shader source and holds the two to each other.

const SHADER_PATH := "res://Scenes/Planet/planet.gdshader"

# The kinds, by the name the shader gives each one.
const CONSTANT_FOR_KIND := {
	MapProjection.Kind.RECTANGULAR: "PROJECTION_RECTANGULAR",
	MapProjection.Kind.MERCATOR: "PROJECTION_MERCATOR",
	MapProjection.Kind.MOLLWEIDE: "PROJECTION_MOLLWEIDE",
	MapProjection.Kind.ROBINSON: "PROJECTION_ROBINSON",
	MapProjection.Kind.ORTHOGRAPHIC: "PROJECTION_ORTHOGRAPHIC",
}

var source: String = ""


func test_the_shader_numbers_every_projection_the_way_MapProjection_does() -> void:
	for kind in CONSTANT_FOR_KIND:
		assert_eq(_int_constant(CONSTANT_FOR_KIND[kind]), int(kind),
			"the shader's %s" % CONSTANT_FOR_KIND[kind])


func test_the_shader_sizes_the_robinson_sheet_the_same() -> void:
	assert_close(_float_constant("ROBINSON_EXTENT"), MapProjection.ROBINSON_EXTENT, 1e-12,
		"the shader's ROBINSON_EXTENT")
	assert_close(_float_constant("ROBINSON_STEP"), MapProjection.ROBINSON_STEP, 1e-12,
		"the shader's ROBINSON_STEP")


func test_the_shader_allows_the_same_slack_at_an_edge() -> void:
	assert_close(_float_constant("MAP_EDGE_SLACK"), MapProjection.EDGE_SLACK, 1e-15,
		"the shader's MAP_EDGE_SLACK")


# The shader writes linear light, so its orange is Planet.RIDER_COLOR linearized.
func test_the_shader_draws_riders_in_the_same_orange() -> void:
	var numbers := _constant("RIDER_COLOR").trim_prefix("vec3(").trim_suffix(")").split(",")
	var wanted := Planet.RIDER_COLOR.srgb_to_linear()
	assert_eq(numbers.size(), 3, "the shader's RIDER_COLOR has three components")
	for i in mini(numbers.size(), 3):
		assert_close(numbers[i].strip_edges().to_float(), wanted[i], 1e-5,
			"component %d of the shader's RIDER_COLOR" % i)


# The two tables are written out in the shader as float[19] literals, in the
# same order MapProjection lists them: the lengths first, the distances second.
func test_the_shader_carries_the_same_robinson_tables() -> void:
	var tables := _robinson_tables()
	if tables.size() != 2:
		fail("the shader has %d Robinson tables, not two" % tables.size())
		return
	_check_table(tables[0], MapProjection.ROBINSON_LENGTH, "the parallel lengths")
	_check_table(tables[1], MapProjection.ROBINSON_DISTANCE, "the distances from the equator")


func _check_table(actual: Array, expected: Array, what: String) -> void:
	if actual.size() != expected.size():
		fail("the shader has %d entries for %s, not %d" % [actual.size(), what, expected.size()])
		return
	for i in range(expected.size()):
		assert_close(actual[i], float(expected[i]), 1e-12,
			"entry %d of %s in the shader" % [i, what])


func _source() -> String:
	if source.is_empty():
		var file := FileAccess.open(SHADER_PATH, FileAccess.READ)
		if file == null:
			fail("cannot read %s" % SHADER_PATH)
			return ""
		source = file.get_as_text()
	return source


# The value of one `const <type> <name> = <value>;` line of the shader, as text.
func _constant(name: String) -> String:
	var regex := RegEx.create_from_string(
		"const\\s+\\w+\\s+%s\\s*=\\s*([^;]+);" % name)
	var found := regex.search(_source())
	if found == null:
		fail("the shader has no constant called %s" % name)
		return ""
	return found.get_string(1).strip_edges()


func _float_constant(name: String) -> float:
	return _constant(name).to_float()


func _int_constant(name: String) -> int:
	return _constant(name).to_int()


# The float[19] literals of robinson_at(), in the order they are written.
func _robinson_tables() -> Array:
	var tables: Array = []
	var regex := RegEx.create_from_string("float\\[19\\]\\s*\\(([^)]*)\\)")
	for found in regex.search_all(_source()):
		var numbers: Array = []
		for part in found.get_string(1).split(","):
			var text := part.strip_edges()
			if not text.is_empty():
				numbers.append(text.to_float())
		tables.append(numbers)
	return tables
