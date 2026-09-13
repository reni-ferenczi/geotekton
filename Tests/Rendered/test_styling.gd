extends RenderedCase

# What the styles and the visibility switches put on the screen. The unit tests
# say what colour the geometry is flattened with; these say that the colour
# reaches the pixel, and that a class switched off leaves the Earth showing
# where it was.
#
# The fixture is mixed_geometry.middle-earth: a red polygon at (-3, 0), a blue
# polyline through (0, 40) and green markers at (-30, -30) and (30, -30), one
# feature of each class the switches cover.

const POLYGON := Vector2(-3.0, 0.0)
const POLYLINE := Vector2(0.0, 40.0)
const POINT := Vector2(-30.0, -30.0)

# How far a probed pixel may be from the colour asked for, per channel, in the
# sRGB values both are in. The probe is aimed straight at the place with the
# light shining from the camera, so the lit colour is the picked one and there
# is no brightness to allow for: a colour that comes out paler is a defect
# (GP-0032), not a tolerance.
const COLOR_TOLERANCE := 0.03


func test_each_feature_is_drawn_in_its_own_colour() -> void:
	await _load_styled({"draw_style": Styling.BY_FEATURE})
	await _check(POLYGON, Color.RED, "the polygon")
	await _check(POLYLINE, Color.BLUE, "the polyline")
	await _check(POINT, Color.GREEN, "the point")


func test_the_single_colour_style_paints_all_three_the_same() -> void:
	var single := Color(0.1, 0.6, 0.9, 1.0)
	await _load_styled({"draw_style": Styling.BY_SINGLE})
	app.document.root.style.color = single
	app.refresh_geometry()
	await _check(POLYGON, single, "the polygon")
	await _check(POLYLINE, single, "the polyline")
	await _check(POINT, single, "the point")


# The sample carries no feature type, so each feature has the type its geometry
# gives, until the polygon is made a Circle, which has a colour of its own.
func test_the_feature_type_style_paints_the_colour_of_the_type() -> void:
	await _load_styled({"draw_style": Styling.BY_TYPE})
	await _check(POLYGON, FeatureType.color("polygon"), "the polygon")
	await _check(POLYLINE, FeatureType.color("line"), "the line")
	await _check(POINT, FeatureType.color("points"), "the points")

	_feature_at(POLYGON).feature_type = FeatureType.CIRCLE
	app.refresh_geometry()
	await _check(POLYGON, FeatureType.color(FeatureType.CIRCLE), "the circle")


# The steps palette is five flat slices two hundred million years wide, so the
# age of each feature picks one of them outright rather than a blend.
func test_the_feature_age_style_paints_the_palette_at_each_age() -> void:
	await _load_styled({"draw_style": Styling.BY_AGE, "palette": "steps"})
	var palette := Palette.built_in("steps")
	var ages := {POLYGON: 100, POLYLINE: 300, POINT: 900}
	for at in ages:
		_feature_at(at).time_range = Vector2i(0, int(ages[at]))
	app.refresh_geometry()
	for at in ages:
		await _check(at, palette.color_at(float(ages[at])), "%s Ma old" % ages[at])


# GP-0036: the same polygon, born at 500 Ma under a 200 My ramp from red to
# blue, is red when it comes into existence and blue 200 My later. The time is
# moved the way the timeline moves it, so only the feature state is uploaded.
func test_the_age_ramp_colors_one_feature_differently_at_two_times() -> void:
	await _load_styled({"draw_style": Styling.BY_AGE, "palette": Palette.RAMP})
	var feature := _feature_at(POLYGON)
	if feature == null:
		return
	feature.time_range = Vector2i(0, 500)
	var style: GroupStyle = app.document.root.style
	style.ramp_from = Color.RED
	style.ramp_to = Color.BLUE
	style.ramp_span = 200.0
	app.refresh_geometry()
	var material: ShaderMaterial = view().planet.globe.get_surface_override_material(0)
	var geometry_data: Texture2D = material.get_shader_parameter("geometry_data")

	app.document.set_time(500.0)
	await frames(2)
	await _check(POLYGON, Color.RED, "the polygon as it comes into existence")
	app.document.set_time(300.0)
	await frames(2)
	await _check(POLYGON, Color.BLUE, "the same polygon 200 My later")
	assert_true(material.get_shader_parameter("geometry_data") == geometry_data,
		"and the geometry texture was not uploaded again")
	app.document.set_time(0.0)


# Each switch takes its own class off the screen and leaves the others where
# they were, with the Earth showing through where it was drawn.
func test_a_switch_leaves_the_earth_where_its_class_was_drawn() -> void:
	var probes := {
		Styling.POLYGONS: POLYGON,
		Styling.POLYLINES: POLYLINE,
		Styling.POINTS: POINT,
	}
	for hidden in probes:
		await _load_styled({"hidden_classes": [hidden]})
		for class_id in probes:
			var at: Vector2 = probes[class_id]
			var color := await _probe(at)
			if class_id == hidden:
				assert_eq(dominant_channel(color), "",
					"%s is gone from %s: %s" % [class_id, at, color])
			else:
				assert_true(not dominant_channel(color).is_empty(),
					"%s is still drawn at %s: %s" % [class_id, at, color])


### Opacity


# GP-0033: the alpha of a feature's color is its opacity. Half lays the color
# half over the Earth, mixed in linear light the way the shader mixes it; none
# leaves the Earth showing while the feature can still be clicked.
func test_opacity_lays_the_color_over_the_earth() -> void:
	await _load_styled({"draw_style": Styling.BY_FEATURE})
	var feature := _feature_at(POLYGON)
	if feature == null:
		return
	feature.enabled = false
	app.refresh_geometry()
	var earth := await _probe(POLYGON)
	feature.enabled = true

	feature.color = Color(Color.RED, 0.5)
	app.refresh_geometry()
	var half := earth.srgb_to_linear().lerp(Color.RED.srgb_to_linear(), 0.5).linear_to_srgb()
	await _check(POLYGON, half, "the polygon at half opacity")

	feature.color = Color(Color.RED, 0.0)
	app.refresh_geometry()
	await _check(POLYGON, earth, "the polygon at no opacity")
	assert_eq(Planet.hit_test(POLYGON.x, POLYGON.y, app.geometry), feature,
		"and it is still hit tested")


# The color lives in the per feature texture, so a change of color uploads
# that and leaves the geometry texture as it was.
func test_a_color_change_uploads_only_the_feature_state() -> void:
	await _load_styled({"draw_style": Styling.BY_FEATURE})
	var feature := _feature_at(POLYGON)
	if feature == null:
		return
	var material: ShaderMaterial = view().planet.globe.get_surface_override_material(0)
	var geometry_data: Texture2D = material.get_shader_parameter("geometry_data")
	var feature_data: Texture2D = material.get_shader_parameter("feature_data")

	feature.color = Color.BLUE
	app.refresh_colors()
	assert_true(material.get_shader_parameter("geometry_data") == geometry_data,
		"the geometry texture is not uploaded again")
	assert_true(material.get_shader_parameter("feature_data") != feature_data,
		"the feature state is")
	await _check(POLYGON, Color.BLUE, "the polygon in its new color")


### Group styles


# group_styles.middle-earth: the root on the feature type style, Continental
# Crust on a single colour holding the red polygon, Cratons on own colours
# holding the blue polyline, and the green markers straight under the root.
const CRUST_COLOR := Color(0.1, 0.6, 0.9, 1.0)


func test_a_group_on_a_single_colour_beside_a_group_on_own_colours() -> void:
	await load_sample("group_styles.middle-earth")
	await _check(POLYGON, CRUST_COLOR, "the polygon in Continental Crust's single colour")
	await _check(POLYLINE, Color.BLUE, "the polyline in its own colour under Cratons")
	await _check(POINT, FeatureType.color("points"), "the markers in the root's type colour")


# A group's opacity lays everything under it over the Earth, the way a feature's
# own does.
func test_a_group_opacity_lays_its_features_over_the_earth() -> void:
	await load_sample("group_styles.middle-earth")
	var crust: Feature = app.document.root.children[0]
	crust.enabled = false
	app.refresh_geometry()
	var earth := await _probe(POLYGON)
	crust.enabled = true

	crust.style.opacity = 0.5
	app.refresh_geometry()
	var half := earth.srgb_to_linear().lerp(CRUST_COLOR.srgb_to_linear(), 0.5).linear_to_srgb()
	await _check(POLYGON, half, "the polygon at half its group's opacity")
	await _check(POLYLINE, Color.BLUE, "while the other group is untouched")


# A 0.7.0 file drawn in a single colour still is: the migration puts the style on
# the root group and the probe finds the colour the view block named.
func test_a_0_7_0_file_in_a_single_colour_opens_drawn_the_same() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"%s/%s" % [DATA_DIR, "group_styles.middle-earth"]))
	var crust: Dictionary = raw["features"]["children"][0]
	crust.erase("style")
	raw["features"].erase("style")
	raw["version"] = "0.7.0"
	raw["view"] = {"draw_style": "single", "single_color": [0.9, 0.5, 0.1, 1.0]}
	var path := ProjectSettings.globalize_path("user://test_styling_0_7_0.middle-earth")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(raw, "\t"))
	file.close()

	app.document.load_from_file(path)
	app._on_craton_hovered(NAN, NAN)
	app.refresh_geometry()
	await frames(2)
	assert_eq(app.document.root.style.mode, Styling.BY_SINGLE, "the root group carries the style")
	assert_eq(app.document.root.style.color, Color(0.9, 0.5, 0.1, 1.0), "and the colour")
	await _check(POLYGON, Color(0.9, 0.5, 0.1, 1.0), "the polygon in that colour")
	await _check(POINT, Color(0.9, 0.5, 0.1, 1.0), "and the markers")
	DirAccess.remove_absolute(path)


### The palette chooser


# The chooser lists every built in palette and previews the chosen one across
# its whole range, so what is about to be drawn with is visible before anything
# is drawn with it. Read off the strip itself rather than looked at.
func test_the_chooser_lists_and_previews_the_built_in_palettes() -> void:
	await load_sample("empty.middle-earth")
	app.show_view_settings()
	var choice: OptionButton = app.view_fields["palette"]
	var listed: Array = []
	for index in choice.item_count:
		listed.append(str(choice.get_item_metadata(index)))
	assert_eq(listed, Palette.choices().keys(), "the ramp and every built in palette are offered")

	for key in Palette.BUILT_IN:
		Application.select_option(choice, str(key))
		app._on_view_field_changed()
		_check_preview(Palette.built_in(str(key)), "the built in %s" % key)

	# The ramp previews the root style's own two colours over its span.
	app.view_fields["ramp_from"].color = Color.RED
	app.view_fields["ramp_to"].color = Color.BLUE
	Application.select_option(choice, Palette.RAMP)
	app._on_view_field_changed()
	assert_eq(app.document.root.style.ramp_from, Color.RED, "the dialog's ramp is the root's")
	_check_preview(Palette.ramp(Color.RED, Color.BLUE, app.document.root.style.ramp_span), "the ramp")
	app.view_dialog.hide()


# A palette read from a file joins the list under its file name and previews the
# same way, which is the whole of what loading one comes to.
func test_a_palette_read_from_a_file_joins_the_list_and_previews() -> void:
	await load_sample("empty.middle-earth")
	var path := ProjectSettings.globalize_path("res://Tests/Data/Palettes/continuous.cpt")
	app.document.root.style.palette = path
	app.apply_view_settings()
	app.show_view_settings()

	var choice: OptionButton = app.view_fields["palette"]
	assert_eq(choice.item_count, Palette.choices().size() + 1, "one entry more than built in")
	assert_eq(Application.option_value(choice), path, "and it is the one chosen")
	assert_eq(choice.get_item_text(choice.selected), "continuous.cpt", "under its file name")
	_check_preview(Palette.load_from(path), "the palette read from the file")
	app.view_dialog.hide()


# A palette with a line the reader could not take still previews what it did
# read, with the reason underneath it rather than nowhere.
func test_a_malformed_palette_says_which_lines_it_could_not_read() -> void:
	await load_sample("empty.middle-earth")
	app.document.root.style.palette = ProjectSettings.globalize_path(
		"res://Tests/Data/Palettes/malformed.cpt")
	app.apply_view_settings()
	app.show_view_settings()
	assert_true(app.palette_warning.text.contains("line 2"), "the first bad line is named")
	assert_true(app.palette_warning.text.contains("line 4"), "and so is the second")
	assert_true(app.palette_preview.texture != null, "what did read is still previewed")
	app.view_dialog.hide()


# The strip is the palette from one end of its range to the other.
func _check_preview(expected: Palette, what: String) -> void:
	var texture: Texture2D = app.palette_preview.texture
	assert_true(texture != null, "%s is previewed" % what)
	if texture == null:
		return
	var strip: Image = texture.get_image()
	assert_eq(strip.get_width(), Application.PALETTE_PREVIEW_STEPS, "%s across the strip" % what)
	var wanted := expected.sample(Application.PALETTE_PREVIEW_STEPS)
	for x in [0, strip.get_width() / 2, strip.get_width() - 1]:
		assert_close(strip.get_pixel(x, 0), wanted[x], 1.0 / 255.0,
			"%s at step %d of the strip" % [what, x])


### Helpers


# Load the fixture and give the document the styling the case is about: the
# switches in the view block and the style on the root group.
func _load_styled(block: Dictionary) -> void:
	await load_sample("mixed_geometry.middle-earth")
	var settings := ViewSettings.new()
	for class_id in block.get("hidden_classes", []):
		settings.hide_class(str(class_id), true)
	app.document.view = settings
	var style := GroupStyle.for_root()
	style.mode = Styling.normalize_style(str(block.get("draw_style", Styling.BY_FEATURE)))
	style.palette = str(block.get("palette", Palette.DEFAULT))
	app.document.root.style = style
	app.apply_view_settings()
	app.refresh_geometry()
	await frames(2)


# The feature covering a point, so a case can edit the one it is about to probe
# without naming it twice.
func _feature_at(at: Vector2) -> Feature:
	var feature := Planet.hit_test(at.x, at.y, app.geometry)
	if feature == null:
		fail("nothing is drawn at %s" % at)
	return feature


func _probe(at: Vector2) -> Color:
	await look_at_latlon(at.x, at.y)
	var screen: Variant = view().latlon_to_screen(at.x, at.y)
	assert_true(screen != null, "lat/lon %s must be visible" % at)
	if screen == null:
		return Color.BLACK
	return await probe(screen)


func _check(at: Vector2, expected: Color, what: String) -> void:
	var color := await _probe(at)
	var difference := _difference(color, expected)
	assert_true(difference <= COLOR_TOLERANCE,
		"%s at %s reads %s, not %s (off by %.3f)" % [what, at, color, expected, difference])


# How far a probed pixel is from the colour it was meant to be: the largest
# channel difference, both colours as the sRGB values the window and the
# picker hold them in.
func _difference(probed: Color, expected: Color) -> float:
	return maxf(maxf(absf(probed.r - expected.r), absf(probed.g - expected.g)),
		absf(probed.b - expected.b))
