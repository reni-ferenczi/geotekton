extends TestCase

# The view settings block: how the scene around the features is drawn, saved
# with the document rather than with the person looking at it.

const SCRATCH := "user://test_view_settings.geotekt"
const OLD_SAMPLE := "res://Tests/Data/two_cratons.geotekt"


func test_a_fresh_block_is_the_scene_as_it_was_always_drawn() -> void:
	var settings := ViewSettings.new()
	assert_eq(settings.background_color, ViewSettings.DEFAULT_BACKGROUND, "the background")
	assert_true(settings.star_field, "the star field is on")
	assert_eq(settings.grid_color, ViewSettings.DEFAULT_GRID_COLOR, "the grid")
	assert_eq(settings.grid_spacing, 15.0, "fifteen degrees between the lines")
	assert_eq(settings.light_direction, Vector2.ZERO, "the light shines from the camera")
	assert_eq(settings.ambient, 0.0, "and the night side is dark")
	assert_eq(settings.planet_color, ViewSettings.DEFAULT_PLANET_COLOR, "the planet is ocean blue")
	assert_eq(settings.raster_path, "", "there is no raster")
	assert_true(settings.raster_visible, "which would be shown if there were")
	assert_eq(settings.raster_opacity, 1.0, "at full opacity")
	assert_eq(settings.hidden_classes.size(), 0, "every class of geometry is drawn")
	# The colors are the root group's since 0.10.0, not the block's.
	for key in GroupStyle.VIEW_KEYS:
		assert_true(not settings.to_json().has(key), "%s is not in the block" % key)
	assert_eq(Document.new().root.style.mode, Styling.BY_FEATURE,
		"a new document draws each feature in its own colour")


# The grid is one spacing in degrees; the shader counts divisions of the
# whole planet, twice as many round the equator as from pole to pole.
func test_the_spacing_becomes_the_divisions_the_shader_counts() -> void:
	var settings := ViewSettings.new()
	assert_eq(settings.grid_split(), Vector2(24.0, 12.0), "fifteen degrees")
	settings.grid_spacing = 30.0
	assert_eq(settings.grid_split(), Vector2(12.0, 6.0), "thirty degrees")
	settings.grid_spacing = 10.0
	assert_eq(settings.grid_split(), Vector2(36.0, 18.0), "ten degrees")


func test_every_setting_round_trips_through_json() -> void:
	var settings := _edited()
	var back := ViewSettings.from_json(settings.to_json())
	assert_eq(back.background_color, settings.background_color, "the background colour")
	assert_eq(back.star_field, settings.star_field, "the star field switch")
	assert_eq(back.grid_color, settings.grid_color, "the grid color")
	assert_eq(back.grid_spacing, settings.grid_spacing, "the grid spacing")
	assert_eq(back.light_direction, settings.light_direction, "the light direction")
	assert_eq(back.ambient, settings.ambient, "the ambient level")
	assert_eq(back.planet_color, settings.planet_color, "the planet color")
	assert_eq(back.raster_path, settings.raster_path, "the raster path")
	assert_eq(back.raster_opacity, settings.raster_opacity, "the raster opacity")
	assert_eq(back.raster_visible, settings.raster_visible, "the raster switch")
	assert_eq(back.hidden_classes, settings.hidden_classes, "and the classes switched off")


func test_a_block_that_says_nothing_gets_every_default() -> void:
	var fresh := ViewSettings.new()
	for empty in [null, {}, "not a block", []]:
		var settings := ViewSettings.from_json(empty)
		assert_eq(settings.to_json(), fresh.to_json(), "%s gives the defaults" % [empty])


# A half written block is read for what it does say. Anything else takes the
# default, so a file from a version that knew fewer settings still opens.
func test_a_block_missing_a_setting_takes_the_default_for_it() -> void:
	var settings := ViewSettings.from_json({"ambient": 0.4, "star_field": false})
	assert_eq(settings.ambient, 0.4, "the setting the block carries")
	assert_true(not settings.star_field, "and the other one")
	assert_eq(settings.grid_spacing, 15.0, "the rest are the defaults")
	assert_eq(settings.background_color, ViewSettings.DEFAULT_BACKGROUND, "including the colours")


func test_a_setting_out_of_range_is_brought_back_into_it() -> void:
	var wide := ViewSettings.from_json({"grid_spacing": 500.0, "ambient": 9.0})
	assert_eq(wide.grid_spacing, ViewSettings.MAX_SPACING, "the spacing")
	assert_eq(wide.ambient, ViewSettings.MAX_AMBIENT, "the ambient level")
	var narrow := ViewSettings.from_json({"grid_spacing": 0.0, "ambient": -3.0})
	assert_eq(narrow.grid_spacing, ViewSettings.MIN_SPACING, "and the other way")
	assert_eq(narrow.ambient, ViewSettings.MIN_AMBIENT, "for both")


func test_the_settings_survive_a_save_and_a_load() -> void:
	var document := Document.new()
	document.view = _edited()
	document.view_edited()
	assert_true(document.is_dirty(), "editing the view dirties the document")

	var path := ProjectSettings.globalize_path(SCRATCH)
	assert_eq(document.save_to_file(path), "", "the document is written")
	assert_true(not document.is_dirty(), "and is clean once it is")

	var reopened := Document.new()
	assert_eq(reopened.load_from_file(path), "", "and read back")
	assert_eq(reopened.view.to_json(), document.view.to_json(), "with the whole block")
	assert_true(not reopened.is_dirty(), "and nothing to save")
	DirAccess.remove_absolute(path)


# A view setting is an edit like any other since GP-0042: it records one
# version, and one that changes nothing records none.
func test_a_view_setting_is_one_step_of_the_undo_stack() -> void:
	var document := Document.new()
	var depth := document.applied
	document.view.ambient = 0.5
	document.view_edited()
	assert_eq(document.applied, depth + 1, "one undo version was recorded")
	assert_true(document.can_undo(), "and it can be undone")
	document.view_edited()
	assert_eq(document.applied, depth + 1, "saying it again with nothing changed records nothing")


# Every file written before 0.6.0 carries no view block, and opens looking the
# way it always did: the defaults, with the built in Earth that was under every
# file before 0.17.0 as its raster.
func test_a_file_written_before_the_block_existed_gets_the_defaults() -> void:
	var document := Document.new()
	assert_eq(document.load_from_file(ProjectSettings.globalize_path(OLD_SAMPLE)), "",
		"the older sample opens")
	var expected := ViewSettings.new()
	expected.raster_path = ViewSettings.BUILT_IN_EARTH
	assert_eq(document.view.to_json(), expected.to_json(),
		"with the scene as it was drawn then")


### The raster path


# An image beside the project, or under it, is stored relative, so the two can
# be moved together. Anything else is stored as it stands.
func test_an_image_beside_the_project_is_stored_relative() -> void:
	assert_eq(Document.relative_raster("C:/maps/world/earth.png", "C:/maps/world/atlas.geotekt"),
		"earth.png", "beside the project")
	assert_eq(Document.relative_raster("C:/maps/world/art/earth.png", "C:/maps/world/atlas.geotekt"),
		"art/earth.png", "in a folder under it")
	assert_eq(Document.relative_raster("C:/pictures/earth.png", "C:/maps/world/atlas.geotekt"),
		"C:/pictures/earth.png", "somewhere else entirely")
	assert_eq(Document.relative_raster("C:/maps/world/earth.png", ""),
		"C:/maps/world/earth.png", "a document with no path of its own")


func test_a_relative_image_is_found_beside_the_project_wherever_it_is() -> void:
	var document := Document.new()
	document.view.raster_path = "art/earth.png"
	document.path = "C:/maps/world/atlas.geotekt"
	assert_eq(document.resolve_raster(), "C:/maps/world/art/earth.png", "where it was saved")
	document.path = "D:/moved/atlas.geotekt"
	assert_eq(document.resolve_raster(), "D:/moved/art/earth.png", "and after the folder moved")


# Whichever way the path was given, saving stores it relative to the file being
# written when the image sits beside it, so Save As into the image's own folder
# is what makes it relative rather than how it was picked.
func test_saving_beside_the_image_stores_the_path_relative() -> void:
	var folder := ProjectSettings.globalize_path("user://")
	var image := folder.path_join("test_view_settings_image.png")
	var written := Image.create(4, 4, false, Image.FORMAT_RGB8)
	written.fill(Color.RED)
	assert_eq(written.save_png(image), OK, "the fixture image is written")

	var document := Document.new()
	document.view.raster_path = image
	document.view_edited()
	var path := folder.path_join("test_view_settings_relative.geotekt")
	assert_eq(document.save_to_file(path), "", "the document is written beside it")
	assert_eq(document.view.raster_path, "test_view_settings_image.png",
		"and the path it stored is relative to it")
	assert_eq(document.resolve_raster(), image, "which resolves back to the image")

	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(image)


func test_an_absolute_image_is_left_where_it_points() -> void:
	var document := Document.new()
	document.path = "C:/maps/world/atlas.geotekt"
	document.view.raster_path = "C:/pictures/earth.png"
	assert_eq(document.resolve_raster(), "C:/pictures/earth.png", "an absolute path")
	document.view.raster_path = ""
	assert_eq(document.resolve_raster(), "", "and no image at all")


# An image the application ships is neither beside the project nor anywhere on
# the disk, so it is stored and found by its res:// path, however the document
# is saved.
func test_the_built_in_earth_is_stored_and_found_as_it_is() -> void:
	var earth := ViewSettings.BUILT_IN_EARTH
	assert_eq(Document.relative_raster(earth, "C:/maps/world/atlas.geotekt"), earth,
		"stored as it is")
	var document := Document.new()
	document.path = "C:/maps/world/atlas.geotekt"
	document.view.raster_path = earth
	assert_eq(document.resolve_raster(), earth, "and found as it is")


# The planet is never see-through: an alpha given with its color is dropped,
# whether it is set or read from a file.
func test_the_planet_color_is_always_opaque() -> void:
	var settings := ViewSettings.new()
	settings.planet_color = Color(0.2, 0.4, 0.6, 0.2)
	assert_eq(settings.planet_color, Color(0.2, 0.4, 0.6, 1.0), "set with an alpha")
	var read := ViewSettings.from_json({"planet_color": [0.2, 0.4, 0.6, 0.2]})
	assert_eq(read.planet_color, Color(0.2, 0.4, 0.6, 1.0), "and read with one")
	assert_eq(ViewSettings.from_json({}).planet_color, ViewSettings.DEFAULT_PLANET_COLOR,
		"and a block without one takes the default")


func _edited() -> ViewSettings:
	var settings := ViewSettings.new()
	settings.background_color = Color(0.1, 0.2, 0.3, 1.0)
	settings.star_field = false
	settings.grid_color = Color(0.9, 0.4, 0.1, 0.5)
	settings.grid_spacing = 30.0
	settings.light_direction = Vector2(25.0, -40.0)
	settings.ambient = 0.35
	settings.planet_color = Color(0.3, 0.5, 0.2)
	settings.raster_path = "art/earth.png"
	settings.raster_opacity = 0.5
	settings.raster_visible = false
	settings.hide_class(Styling.POINTS, true)
	settings.hide_class(Styling.TOPOLOGIES, true)
	return settings
