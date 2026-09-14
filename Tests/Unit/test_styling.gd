extends TestCase

# Which class of geometry a feature belongs to, which classes are drawn, and
# what colour a feature comes out under each draw style and each group style.
# All of it without a window: the styling is resolved where the geometry is
# flattened, so what the shader is handed says everything about what is drawn.
#
# The fixture holds one feature of every class, laid out well apart from each
# other, with a distinct colour, feature type and time range on each.

const POLYGON_RING := [Vector2(-10, -10), Vector2(10, 0), Vector2(-10, 10)]
const POLYLINE_RING := [Vector2(0, 40), Vector2(20, 40)]
const POINT_RING := [Vector2(-30, -30), Vector2(30, -30)]
const CIRCLE_RING := [Vector2(50, 100), Vector2(60, 110), Vector2(50, 120)]

# What each feature of the fixture is called, by the class it belongs to.
const TITLES := {
	Styling.POLYGONS: "Shield",
	Styling.POLYLINES: "Ridge",
	Styling.POINTS: "Stations",
	Styling.CIRCLES: "Circle",
	Styling.TOPOLOGIES: "Boundary",
}

const SINGLE := Color(0.2, 0.4, 0.6, 1.0)
const OTHER_SINGLE := Color(0.7, 0.1, 0.3, 1.0)


# Root > Shield, Ridge, Stations, Circle and Boundary, which runs along Ridge.
func _build_tree() -> Feature:
	var root := Feature.create_group("Planet")
	root.is_root = true
	root.style = GroupStyle.for_root()

	var shield := Feature.create_feature(TITLES[Styling.POLYGONS], Color.RED)
	shield.feature_type = "polygon"
	shield.time_range = Vector2i(0, 100)
	shield.add_ring(PackedVector2Array(POLYGON_RING), Feature.GeometryKind.POLYGON)
	root.children.append(shield)

	var ridge := Feature.create_feature(TITLES[Styling.POLYLINES], Color.BLUE)
	ridge.feature_type = "line"
	ridge.time_range = Vector2i(0, 500)
	ridge.add_ring(PackedVector2Array(POLYLINE_RING), Feature.GeometryKind.POLYLINE)
	root.children.append(ridge)

	var stations := Feature.create_feature(TITLES[Styling.POINTS], Color.GREEN)
	stations.feature_type = "points"
	stations.time_range = Vector2i(0, 900)
	stations.add_ring(PackedVector2Array(POINT_RING), Feature.GeometryKind.MULTIPOINT)
	root.children.append(stations)

	# A polygon like the shield; what makes it a circle is its type.
	var circle := Feature.create_feature(TITLES[Styling.CIRCLES], Color.YELLOW)
	circle.feature_type = FeatureType.CIRCLE
	circle.time_range = Vector2i(0, 250)
	circle.add_ring(PackedVector2Array(CIRCLE_RING), Feature.GeometryKind.POLYGON)
	root.children.append(circle)

	var boundary := Feature.create_feature(TITLES[Styling.TOPOLOGIES], Color.MAGENTA)
	boundary.feature_type = "topology"
	boundary.geometry_kind = Feature.GeometryKind.TOPOLOGY
	boundary.time_range = Vector2i(0, 700)
	boundary.sections = [TopologySection.create(ridge.uuid, 0, 0, 1)]
	root.children.append(boundary)
	return root


func _feature(root: Feature, class_id: String) -> Feature:
	for child in root.children:
		if child.title == str(TITLES[class_id]):
			return child
	fail("the fixture holds no %s" % class_id)
	return null


### Which class a feature belongs to


func test_every_feature_of_the_fixture_lands_in_its_own_class() -> void:
	var root := _build_tree()
	for class_id in Styling.CLASSES:
		assert_eq(Styling.class_of(_feature(root, class_id)), class_id,
			"%s is a %s" % [TITLES[class_id], class_id])


# A circle is a polygon or a polyline; its type is what tells it apart, so a
# feature keeps its own class whichever geometry it holds.
func test_the_type_decides_a_circle_rather_than_the_geometry() -> void:
	var feature := Feature.create_feature("Circle")
	feature.add_ring(PackedVector2Array(POLYGON_RING), Feature.GeometryKind.POLYGON)
	assert_eq(Styling.class_of(feature), Styling.POLYGONS, "a polygon to begin with")
	feature.feature_type = FeatureType.CIRCLE
	assert_eq(Styling.class_of(feature), Styling.CIRCLES, "and now a circle")


### The visibility switches


# Every switch takes away its own class and leaves the other four where they
# were, which is what makes them switches rather than one blunt filter.
func test_a_switch_removes_its_own_class_and_nothing_else() -> void:
	var root := _build_tree()
	var whole := _primitives_by_class(root, ViewSettings.new())
	for class_id in Styling.CLASSES:
		assert_true(int(whole.get(class_id, 0)) > 0,
			"%s draws something to begin with" % class_id)

	for hidden in Styling.CLASSES:
		var settings := ViewSettings.new()
		settings.hide_class(hidden, true)
		var drawn := _primitives_by_class(root, settings)
		assert_eq(drawn.get(hidden, 0), 0, "%s is gone" % hidden)
		for other in Styling.CLASSES:
			if other == hidden:
				continue
			assert_eq(drawn.get(other, 0), whole[other],
				"%s is untouched while %s is off" % [other, hidden])


# A feature whose class is switched off is left out of the geometry altogether,
# so it is not hit tested either: a click goes through it to whatever is behind.
func test_a_hidden_feature_is_not_hit_tested() -> void:
	var root := _build_tree()
	var settings := ViewSettings.new()
	assert_eq(_hit(root, settings, -3.0, 0.0), TITLES[Styling.POLYGONS], "the shield is there")
	settings.hide_class(Styling.POLYGONS, true)
	assert_eq(_hit(root, settings, -3.0, 0.0), "", "and gone once polygons are off")


func test_switching_a_class_back_on_brings_it_back() -> void:
	var settings := ViewSettings.new()
	assert_true(settings.shows_class(Styling.POINTS), "everything is shown to begin with")
	settings.hide_class(Styling.POINTS, true)
	assert_true(not settings.shows_class(Styling.POINTS), "off")
	settings.hide_class(Styling.POINTS, false)
	assert_true(settings.shows_class(Styling.POINTS), "and on again")
	assert_eq(settings.hidden_classes.size(), 0, "with nothing left behind")


# A name that is not a class cannot hide anything, so a file from a later
# version that knows more of them opens showing everything this one can draw.
func test_a_name_that_is_not_a_class_is_ignored() -> void:
	var settings := ViewSettings.from_json({"hidden_classes": ["rasters", "polygons"]})
	assert_eq(Array(settings.hidden_classes), ["polygons"], "only the class it knows")


### The draw styles, set on the root group


func test_the_feature_colour_style_gives_each_feature_its_own_colour() -> void:
	var root := _styled(Styling.BY_FEATURE)
	var colors := _colors_by_class(root)
	assert_eq(colors[Styling.POLYGONS], Color.RED, "the shield")
	assert_eq(colors[Styling.POLYLINES], Color.BLUE, "the ridge")
	assert_eq(colors[Styling.POINTS], Color.GREEN, "the stations")
	assert_eq(colors[Styling.TOPOLOGIES], Color.MAGENTA, "the boundary")


func test_the_single_colour_style_gives_every_feature_the_same_one() -> void:
	var root := _styled(Styling.BY_SINGLE)
	root.style.color = SINGLE
	var colors := _colors_by_class(root)
	for class_id in Styling.CLASSES:
		assert_eq(colors[class_id], SINGLE, "%s is the one colour" % class_id)


# At the present a feature's age is the older end of its time range: all the
# time since it came into being.
func test_the_feature_age_style_reads_the_palette_at_the_age_so_far() -> void:
	var root := _styled(Styling.BY_AGE)
	root.style.palette = "rainbow"
	var palette := Palette.built_in("rainbow")
	var colors := _colors_by_class(root)
	assert_eq(colors[Styling.POLYGONS], palette.color_at(100.0), "the shield, 100 My old")
	assert_eq(colors[Styling.POLYLINES], palette.color_at(500.0), "the ridge, 500")
	assert_eq(colors[Styling.POINTS], palette.color_at(900.0), "the stations, 900")
	assert_eq(colors[Styling.TOPOLOGIES], palette.color_at(700.0), "the boundary, 700")
	var stations := _feature(root, Styling.POINTS)
	assert_eq(Styling.age_of(stations), 900.0, "the older end of the range, not the younger")
	assert_eq(Styling.age_of(stations, 600.0), 300.0, "and 300 My old at 600 Ma")
	assert_eq(Styling.age_of(stations, 950.0), 0.0, "never below zero before it exists")


### The custom ramp


const RAMP_FROM := Color(0.8, 0.4, 0.1, 1.0)
const RAMP_TO := Color(0.2, 0.6, 0.9, 1.0)
const RAMP_LAST := Color(0.0, 0.5, 0.0, 1.0)


# GP-0036: a feature born at 500 Ma under a 200 My ramp is color A at 500,
# halfway at 400, and color B at 300 and every time after, down to the present.
# Read off the colors the geometry uploads, moved only by resolve(), which is
# what a step of an animation calls.
func test_the_ramp_moves_from_a_to_b_over_its_span_and_holds() -> void:
	var root := _nested()
	root.style.mode = Styling.BY_AGE
	root.style.palette = Palette.RAMP
	root.style.ramp_colors = [RAMP_FROM, RAMP_TO]
	root.style.ramp_span = 200.0
	var leaf: Feature = root.children[0].children[0].children[0]
	leaf.time_range = Vector2i(0, 500)

	var geometry := Planet.collect_geometry(root, 500.0, Styling.of(ViewSettings.new(), root))
	var halfway := RAMP_FROM.lerp(RAMP_TO, 0.5)
	for step in [[500.0, RAMP_FROM, "A when it comes into existence"],
			[400.0, halfway, "halfway 100 My later"],
			[300.0, RAMP_TO, "B at the end of the span"],
			[0.0, RAMP_TO, "and still B at the present"],
			[500.0, RAMP_FROM, "and A again back at 500"]]:
		geometry.resolve(root, step[0])
		assert_close(geometry.colors[0], step[1], 1e-5, "%s (%s Ma)" % [step[2], step[0]])


# The ramp is a palette of one slice per pair of colours, so the chooser's strip
# previews it the same way as any other.
func test_the_ramp_is_a_palette_of_one_slice_per_pair() -> void:
	var ramp := Palette.ramp([RAMP_FROM, RAMP_TO], 200.0)
	assert_eq(ramp.source, Palette.RAMP, "named by its key")
	assert_eq(ramp.color_at(-10.0), RAMP_FROM, "A below zero")
	assert_close(ramp.color_at(50.0), RAMP_FROM.lerp(RAMP_TO, 0.25), 1e-5, "a quarter along")
	assert_eq(ramp.color_at(1000.0), RAMP_TO, "B past the span")
	assert_true(Palette.choices().has(Palette.RAMP), "and it is listed with the built in palettes")


# A ramp of three colours reaches the middle one at the end of the first span
# and holds at the last past the end of the second.
func test_a_three_colour_ramp_spans_each_pair_in_turn() -> void:
	var ramp := Palette.ramp([RAMP_FROM, RAMP_TO, RAMP_LAST], 200.0)
	assert_eq(ramp.slices.size(), 2, "one slice per pair")
	assert_eq(ramp.color_at(0.0), RAMP_FROM, "the first colour at age zero")
	assert_close(ramp.color_at(200.0), RAMP_TO, 1e-5, "the middle colour at one span")
	assert_close(ramp.color_at(300.0), RAMP_TO.lerp(RAMP_LAST, 0.5), 1e-5, "halfway to the last")
	assert_eq(ramp.color_at(400.0), RAMP_LAST, "the last colour at two spans")
	assert_eq(ramp.color_at(1000.0), RAMP_LAST, "and held there past the end")


# A new style ramps black to white, which is what the palette chooser starts on.
func test_a_new_style_ramps_black_to_white() -> void:
	var style := GroupStyle.new()
	assert_eq(style.palette, Palette.RAMP, "the custom ramp is the default palette")
	assert_eq(style.ramp_colors, [Color.BLACK, Color.WHITE], "black to white")
	assert_eq(style.ramp_span, 300.0, "over 300 My")
	assert_eq(style.ramp().color_at(150.0), Color(0.5, 0.5, 0.5, 1.0), "grey halfway along")


# A ramp needs two ends, so a style that names fewer takes the default one.
func test_a_ramp_of_fewer_than_two_colours_is_the_default_ramp() -> void:
	assert_eq(GroupStyle.from_json({"ramp_colors": [[1.0, 0.0, 0.0, 1.0]]}).ramp_colors,
		[Color.BLACK, Color.WHITE], "one colour is no ramp")
	assert_eq(GroupStyle.from_json({"ramp_colors": "red"}).ramp_colors,
		[Color.BLACK, Color.WHITE], "and neither is something that is not a list")


# A style that names no ramp never recolors on a step of an animation.
func test_only_an_age_style_asks_for_colors_every_step() -> void:
	var root := _nested()
	assert_true(not Styling.of(ViewSettings.new(), root).by_age, "own colours do not")
	root.children[0].style.mode = Styling.BY_AGE
	assert_true(Styling.of(ViewSettings.new(), root).by_age, "an age style under the root does")


func test_the_feature_type_style_gives_the_colour_of_the_type() -> void:
	var colors := _colors_by_class(_styled(Styling.BY_TYPE))
	assert_eq(colors[Styling.POLYGONS], FeatureType.color("polygon"), "the shield is a polygon")
	assert_eq(colors[Styling.POLYLINES], FeatureType.color("line"), "the ridge is a line")
	assert_eq(colors[Styling.POINTS], FeatureType.color("points"), "the stations are points")
	assert_eq(colors[Styling.CIRCLES], FeatureType.color(FeatureType.CIRCLE), "the circle")


# A document that names no style is drawn the way every document was before
# there were any: each feature in the colour it carries.
func test_a_document_that_names_no_style_draws_the_feature_colours() -> void:
	var root := _build_tree()
	assert_eq(root.style.mode, Styling.BY_FEATURE, "the style a fresh root has")
	assert_eq(_colors_by_class(root)[Styling.POLYGONS], Color.RED, "the shield")
	# The same again with no styling handed over at all, which is what a caller
	# that knows nothing about styles gets.
	var bare := Planet.collect_geometry(root, 0.0)
	for index in bare.features.size():
		var feature: Feature = bare.features[index]
		assert_eq(bare.colors[index], feature.color, "%s without any styling" % feature.title)


func test_a_style_name_from_nowhere_falls_back_to_the_feature_colour() -> void:
	assert_eq(Styling.normalize_style("by_plate_id"), Styling.BY_FEATURE, "an unknown style")
	assert_eq(Styling.normalize_style(""), Styling.BY_FEATURE, "and none at all")
	for style_id in Styling.STYLES:
		assert_eq(Styling.normalize_style(style_id), style_id, "%s is its own" % style_id)


### Group styles


# Root > Outer > Inner > Leaf, every group on inherit and at full opacity.
func _nested() -> Feature:
	var root := Feature.create_group("Planet")
	root.is_root = true
	root.style = GroupStyle.for_root()
	var outer := Feature.create_group("Outer")
	var inner := Feature.create_group("Inner")
	var leaf := Feature.create_feature("Leaf", Color(1.0, 0.0, 0.0, 0.8))
	leaf.add_ring(PackedVector2Array(POLYGON_RING), Feature.GeometryKind.POLYGON)
	root.children.append(outer)
	outer.children.append(inner)
	inner.children.append(leaf)
	return root


func _leaf_color(root: Feature) -> Color:
	var leaf: Feature = root.children[0].children[0].children[0]
	return Styling.of(ViewSettings.new(), root).color_of(leaf)


func test_a_new_group_inherits() -> void:
	assert_eq(Feature.create_group().style.mode, Styling.INHERIT, "a group leaves it to the one above")
	assert_eq(Feature.create_group().style.opacity, 1.0, "at full opacity")
	assert_true(Feature.create_feature().style == null, "and a leaf has no style")


func test_a_root_style_reaches_through_two_levels_of_inherit() -> void:
	var root := _nested()
	root.style.mode = Styling.BY_SINGLE
	root.style.color = SINGLE
	assert_eq(_leaf_color(root), SINGLE, "the root's single colour, past Outer and Inner")


func test_the_nearest_group_not_on_inherit_decides() -> void:
	var root := _nested()
	root.style.mode = Styling.BY_SINGLE
	root.style.color = SINGLE
	var outer: Feature = root.children[0]
	var inner: Feature = outer.children[0]
	outer.style.mode = Styling.BY_TYPE
	assert_eq(_leaf_color(root), FeatureType.color("polygon"), "Outer's type colour over the root")
	inner.style.mode = Styling.BY_SINGLE
	inner.style.color = OTHER_SINGLE
	assert_eq(_leaf_color(root), OTHER_SINGLE, "and Inner's own over both")
	inner.style.mode = Styling.BY_FEATURE
	assert_eq(_leaf_color(root), Color(1.0, 0.0, 0.0, 0.8), "Inner on own colours gives the leaf's")


func test_the_root_style_is_the_default() -> void:
	var root := _nested()
	assert_eq(_leaf_color(root), Color(1.0, 0.0, 0.0, 0.8), "a fresh root draws the leaf's own colour")
	# A root has nothing above it, so a root on inherit is the same default.
	root.style.mode = Styling.INHERIT
	assert_eq(_leaf_color(root), Color(1.0, 0.0, 0.0, 0.8), "and so does a root on inherit")
	root.style.mode = Styling.BY_TYPE
	assert_eq(_leaf_color(root), FeatureType.color("polygon"), "while the root decides for all")


# Every group's opacity multiplies in, whether it decides the colour or not.
func test_the_opacity_of_every_group_above_multiplies_down() -> void:
	var root := _nested()
	var outer: Feature = root.children[0]
	var inner: Feature = outer.children[0]
	root.style.opacity = 0.5
	outer.style.opacity = 0.5
	assert_close(_leaf_color(root).a, 0.8 * 0.25, 1e-6, "the leaf's own alpha times both")
	inner.style.mode = Styling.BY_SINGLE
	inner.style.color = SINGLE
	inner.style.opacity = 0.8
	var color := _leaf_color(root)
	assert_close(color.a, 0.5 * 0.5 * 0.8, 1e-6, "the single colour times all three")
	assert_eq(Color(color, 1.0), SINGLE, "and the colour itself is untouched")


func test_a_feature_outside_the_tree_keeps_its_own_colour() -> void:
	var root := _nested()
	root.style.mode = Styling.BY_SINGLE
	var stray := Feature.create_feature("Stray", Color.GREEN)
	assert_eq(Styling.of(ViewSettings.new(), root).color_of(stray), Color.GREEN, "not under the root")


func test_a_style_round_trips_through_the_file() -> void:
	var root := _nested()
	var outer: Feature = root.children[0]
	outer.style.mode = Styling.BY_AGE
	outer.style.color = OTHER_SINGLE
	outer.style.opacity = 0.25
	outer.style.palette = "C:/palettes/ages.cpt"
	outer.style.ramp_colors = [SINGLE, OTHER_SINGLE, SINGLE]
	outer.style.ramp_span = 450.0
	var back := Feature.from_json(root.to_json())
	assert_eq(back.children[0].style.to_json(), outer.style.to_json(), "the group's whole style")
	assert_eq(back.style.to_json(), root.style.to_json(), "and the root's")
	assert_true(not (back.children[0].children[0].children[0].to_json() as Dictionary).has("style"),
		"a leaf writes none")


func test_a_style_the_file_garbles_reads_as_inherit_in_range() -> void:
	var style := GroupStyle.from_json({"mode": "by_plate_id", "opacity": 3.0, "color": "red"})
	assert_eq(style.mode, Styling.INHERIT, "an unknown mode inherits")
	assert_eq(style.opacity, 1.0, "the opacity is brought back into range")
	assert_eq(style.color, Styling.DEFAULT_SINGLE, "and a colour that is not one is the default")
	assert_eq(GroupStyle.from_json({"ramp_span": 0.0}).ramp_span, 1.0, "a ramp spans at least 1 My")
	assert_eq(GroupStyle.from_json(null).to_json(), GroupStyle.new().to_json(), "no style at all")


func test_a_clone_carries_its_own_copy_of_the_style() -> void:
	var root := _nested()
	var copy := root.clone()
	copy.children[0].style.mode = Styling.BY_TYPE
	assert_eq(root.children[0].style.mode, Styling.INHERIT, "editing the copy leaves the original")


func test_a_style_edit_is_one_step_of_the_undo_stack() -> void:
	var document := Document.new()
	var group := Feature.create_group("Crust")
	document.root.children.append(group)
	document.record()
	var depth := document.applied

	var style := GroupStyle.new()
	style.mode = Styling.BY_SINGLE
	style.opacity = 0.5
	assert_eq(document.set_style(group, style), "", "a group takes a style")
	assert_eq(document.applied, depth + 1, "in one undo version")
	style.opacity = 0.1
	assert_eq(group.style.opacity, 0.5, "and keeps its own copy of it")

	document.undo()
	assert_eq(document.root.children[0].style.mode, Styling.INHERIT, "undo takes it back")
	var leaf := Feature.create_feature("Leaf")
	assert_true(not document.set_style(leaf, style).is_empty(), "a leaf is refused")


### Helpers


func _styled(mode: String) -> Feature:
	var root := _build_tree()
	root.style.mode = mode
	return root


# How many primitives each class contributes to the flattened geometry.
func _primitives_by_class(root: Feature, settings: ViewSettings) -> Dictionary:
	var counts := {}
	var geometry := Planet.collect_geometry(root, 0.0, Styling.of(settings, root))
	for primitive in geometry.primitives:
		var class_id := Styling.class_of(primitive["feature"] as Feature)
		counts[class_id] = int(counts.get(class_id, 0)) + 1
	return counts


# The color each class is drawn in, read off the colors the geometry carries
# for the shader.
func _colors_by_class(root: Feature) -> Dictionary:
	var colors := {}
	var geometry := Planet.collect_geometry(root, 0.0, Styling.of(ViewSettings.new(), root))
	for index in geometry.features.size():
		colors[Styling.class_of(geometry.features[index])] = geometry.colors[index]
	return colors


# The title of the feature covering a point, empty when nothing is there.
func _hit(root: Feature, settings: ViewSettings, lat: float, lon: float) -> String:
	var geometry := Planet.collect_geometry(root, 0.0, Styling.of(settings, root))
	var feature := Planet.hit_test(lat, lon, geometry)
	return "" if feature == null else feature.title
