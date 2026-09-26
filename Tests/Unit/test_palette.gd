extends TestCase

# The GMT colour palette table reader in Logic/palette.gd: which lines it
# takes, what colour a value comes out as, and what it says about a line it
# cannot read.

const PALETTES := "res://Tests/Data/Palettes"

# Where the GPlates sources sit beside this project in the development
# workspace. The palettes there are GPL and this project is MIT, so they are
# read where they lie rather than copied in; see Tests/Data/README.md.
const GPLATES_CPT := "../gplates/sample-data/cpt"
const GPLATES_UNIT_TEST_CPT := "../gplates/sample-data/unit-test-data"

const BLACK := Color(0.0, 0.0, 0.0, 1.0)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const WHITE := Color(1.0, 1.0, 1.0, 1.0)
const GREY := Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 1.0)


### A continuous palette


func test_a_ramp_gives_its_end_colours_at_its_ends() -> void:
	var palette := _load("continuous.cpt")
	assert_eq(palette.errors, PackedStringArray(), "the file reads without error")
	assert_eq(palette.slices.size(), 2, "two slices")
	assert_eq(palette.low(), 0.0, "starting at zero")
	assert_eq(palette.high(), 200.0, "and ending at two hundred")
	assert_close(palette.color_at(0.0), BLACK, 1e-3, "the bottom of the first ramp")
	assert_close(palette.color_at(200.0), WHITE, 1e-3, "the top of the second")


# Halfway along a ramp is halfway between its two colours, which is what makes
# it a ramp rather than a step.
func test_a_ramp_interpolates_between_its_two_colours() -> void:
	var palette := _load("continuous.cpt")
	assert_close(palette.color_at(50.0), Color(0.5, 0.0, 0.0, 1.0), 1e-3, "halfway up the first")
	assert_close(palette.color_at(150.0), Color(1.0, 0.5, 0.5, 1.0), 1e-3, "and up the second")


# The two ramps meet at 100 without a step, so the colour at the boundary is the
# same whichever side it is approached from.
func test_a_boundary_two_ramps_share_is_the_same_colour_either_side() -> void:
	var palette := _load("continuous.cpt")
	assert_close(palette.color_at(100.0), RED, 1e-3, "at the boundary")
	assert_close(palette.color_at(99.9), RED, 2e-2, "just below it")
	assert_close(palette.color_at(100.1), RED, 2e-2, "and just above it")


func test_outside_a_palette_are_its_background_and_foreground() -> void:
	var palette := _load("continuous.cpt")
	assert_eq(palette.background, BLUE, "B is the background")
	assert_eq(palette.foreground, GREEN, "F is the foreground")
	assert_close(palette.color_at(-0.1), BLUE, 1e-3, "just below the palette")
	assert_close(palette.color_at(200.1), GREEN, 1e-3, "and just above it")


func test_a_value_that_is_not_a_number_is_the_no_data_colour() -> void:
	var palette := _load("continuous.cpt")
	assert_close(palette.no_data, GREY, 1e-2, "N is the no-data colour")
	assert_close(palette.color_at(NAN), GREY, 1e-2, "which is what NaN comes out as")


### A discrete palette


func test_a_flat_slice_is_one_colour_all_the_way_across() -> void:
	var palette := _load("discrete.cpt")
	assert_eq(palette.errors, PackedStringArray(), "the file reads without error")
	assert_eq(palette.slices.size(), 3, "three slices")
	for value in [0.0, 2.5, 5.0, 9.9, 10.0]:
		assert_close(palette.color_at(value), RED, 1e-3, "%s is in the first slice" % value)


# The boundary belongs to the slice below it, so a discrete palette steps at the
# value after the boundary rather than at the boundary itself.
func test_a_boundary_between_two_flat_slices_belongs_to_the_lower_one() -> void:
	var palette := _load("discrete.cpt")
	assert_close(palette.color_at(9.9), RED, 1e-3, "just below the boundary")
	assert_close(palette.color_at(10.0), RED, 1e-3, "at it")
	assert_close(palette.color_at(10.1), GREEN, 1e-3, "and just above it")


# The file leaves 20 to 30 uncovered. A value there is not below the palette and
# not above it, so it is neither the background nor the foreground.
func test_a_gap_between_two_slices_is_the_no_data_colour() -> void:
	var palette := _load("discrete.cpt")
	assert_close(palette.color_at(20.0), GREEN, 1e-3, "the top of the slice below the gap")
	assert_close(palette.color_at(25.0), Color(200.0 / 255.0, 200.0 / 255.0, 200.0 / 255.0),
		1e-3, "in the gap")
	assert_close(palette.color_at(30.0), BLUE, 1e-3, "and the bottom of the slice above it")


func test_the_annotation_flag_and_the_label_are_read_past() -> void:
	# The first slice of the fixture carries both: "L" and ";Low".
	var palette := _load("discrete.cpt")
	assert_close(palette.color_at(5.0), RED, 1e-3, "the slice is still read")
	assert_eq(palette.errors, PackedStringArray(), "and neither is taken for a colour")


### A categorical palette


func test_a_categorical_palette_looks_a_key_up() -> void:
	var palette := _load("categorical.cpt")
	assert_eq(palette.errors, PackedStringArray(), "the file reads without error")
	assert_true(palette.is_categorical(), "it is categorical")
	assert_eq(palette.slices.size(), 0, "and holds no slices")
	assert_close(palette.color_for("craton"), Color.ORANGE, 1e-3, "a name")
	assert_close(palette.color_for("701"), GREEN, 1e-3, "a number used as a key")
	assert_close(palette.color_for("open circle"),
		Color(0.0, 128.0 / 255.0, 1.0), 1e-3, "a key quoted because it has a space in it")


func test_a_key_the_palette_does_not_name_is_the_no_data_colour() -> void:
	var palette := _load("categorical.cpt")
	assert_close(palette.color_for("terrane"), GREY, 1e-2, "an unknown key")
	assert_close(palette.color_at(5.0), GREY, 1e-2, "and a number, which it has no slices for")


### Lines that cannot be read


func test_a_line_that_is_not_a_palette_entry_is_reported_with_its_number() -> void:
	var palette := _load("malformed.cpt")
	assert_eq(palette.errors.size(), 2, "two lines could not be read: %s" % [palette.errors])
	if palette.errors.size() < 2:
		return
	assert_true(palette.errors[0].begins_with("line 2:"),
		"the line with no colour on it: %s" % palette.errors[0])
	assert_true(palette.errors[1].begins_with("line 4:"),
		"the B with nothing after it: %s" % palette.errors[1])


# One line the reader cannot take does not lose the rest of the file.
func test_the_lines_around_a_bad_one_are_still_read() -> void:
	var palette := _load("malformed.cpt")
	assert_eq(palette.slices.size(), 2, "both slices arrived")
	assert_close(palette.color_at(5.0), RED, 1e-3, "the one before the bad line")
	assert_close(palette.color_at(15.0), BLUE, 1e-3, "and the one after it")


func test_an_unclosed_quote_is_reported_rather_than_read_to_the_end_of_the_line() -> void:
	var palette := Palette.parse("'never closed 255 0 0")
	assert_eq(palette.errors.size(), 1, "one line could not be read")
	assert_true(palette.categories.is_empty(), "and nothing was taken from it")


# GMT writes a few colours as `light` or `dark` in front of a name, and not all
# of them are in Godot's table. A name Godot does know is always its own colour.
func test_a_light_or_dark_name_godot_does_not_know_is_worked_out_from_the_one_it_does() -> void:
	var palette := Palette.parse("a lightred
b lightyellow
c red
d darkred")
	assert_eq(palette.errors, PackedStringArray(), "every name reads")
	assert_close(palette.color_for("c"), RED, 1e-3, "a name Godot knows")
	assert_close(palette.color_for("a"), Color(1.0, 0.5, 0.5), 1e-3,
		"one it does not, half way from red to white")
	assert_close(palette.color_for("b"), Color.LIGHT_YELLOW, 1e-3,
		"and a light name Godot has of its own, which keeps Godot's colour")
	assert_close(palette.color_for("d"), Color.DARK_RED, 1e-3, "the same the other way")


func test_a_file_that_is_not_there_comes_back_saying_so() -> void:
	var palette := Palette.load_from(
		ProjectSettings.globalize_path("%s/no_such_palette.cpt" % PALETTES))
	assert_eq(palette.errors.size(), 1, "the reason it could not be read")
	assert_true(palette.is_empty(), "and an empty palette to carry on with")


### The built in palettes


func test_every_built_in_palette_reads_without_error() -> void:
	for key in Palette.BUILT_IN:
		var palette := Palette.built_in(str(key))
		assert_eq(palette.errors, PackedStringArray(), "%s reads cleanly" % key)
		assert_true(not palette.is_empty(), "%s holds something" % key)
		assert_eq(palette.source, key, "%s says where it came from" % key)
		assert_eq(palette.name, str(Palette.BUILT_IN[key]["name"]), "%s is named" % key)


# Rainbow and Blue are the tables the chooser offers without a file, and Custom
# is the ramp the style carries itself.
func test_the_chooser_offers_the_custom_ramp_rainbow_and_blue() -> void:
	assert_eq(Palette.choices(), {Palette.RAMP: "Custom", "rainbow": "Rainbow", "blue": "Blue"},
		"the three palettes offered without a file")
	assert_close(Palette.built_in("rainbow").color_at(0.0), RED, 1e-3, "rainbow starts red")
	assert_close(Palette.built_in("rainbow").color_at(400.0), GREEN, 1e-3, "and is green at 400")
	assert_eq(Palette.built_in("no such palette").source, "rainbow",
		"a key no version knows falls back to a table that is there")


func test_a_palette_is_resolved_from_a_built_in_name_or_a_path() -> void:
	assert_eq(Palette.resolve("rainbow").source, "rainbow", "a built in name")
	assert_eq(Palette.resolve("").source, Palette.DEFAULT, "nothing named")
	assert_eq(Palette.resolve("").color_at(150.0), Color(0.5, 0.5, 0.5, 1.0),
		"which is the default ramp, black to white over 300 My")
	var path := ProjectSettings.globalize_path("%s/continuous.cpt" % PALETTES)
	var loaded := Palette.resolve(path)
	assert_eq(loaded.source, path, "a path")
	assert_eq(loaded.name, "continuous.cpt", "named after the file")


# The strip the chooser previews a palette with runs from one end of it to the
# other, whether the palette ramps or steps.
func test_a_palette_is_sampled_across_its_whole_range() -> void:
	var strip := Palette.ramp([WHITE, BLACK], 1000.0).sample(5)
	assert_eq(strip.size(), 5, "five samples")
	if strip.size() < 5:
		return
	assert_close(strip[0], WHITE, 1e-3, "starting at the bottom of the palette")
	assert_close(strip[4], BLACK, 1e-3, "and ending at its top")
	assert_close(strip[2], Color(0.5, 0.5, 0.5), 1e-3, "with the middle in between")


### The palettes GPlates ships
#
# The GPlates sources are a sibling checkout in the development workspace rather
# than part of this project, so the check runs when they are there and says so
# when they are not. Every syntax the files below use also appears in the
# fixtures under Tests/Data/Palettes, which are checked whatever else is on the
# machine.


func test_the_palettes_gplates_ships_are_read_without_error() -> void:
	var checked := 0
	for folder in [GPLATES_CPT, GPLATES_UNIT_TEST_CPT]:
		var path := ProjectSettings.globalize_path("res://").path_join(folder).simplify_path()
		var directory := DirAccess.open(path)
		if directory == null:
			print("  the GPlates sample data is not at %s, skipping it" % path)
			continue
		for file_name in directory.get_files():
			if not file_name.ends_with(".cpt"):
				continue
			var palette := Palette.load_from(path.path_join(file_name))
			assert_eq(palette.errors, PackedStringArray(), "%s reads cleanly" % file_name)
			assert_true(not palette.is_empty(), "%s holds something" % file_name)
			checked += 1
	if checked > 0:
		print("  read %d GPlates palettes" % checked)


func _load(file_name: String) -> Palette:
	return Palette.load_from(
		ProjectSettings.globalize_path("%s/%s" % [PALETTES, file_name]))
