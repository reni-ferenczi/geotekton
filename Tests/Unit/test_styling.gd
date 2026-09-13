extends TestCase

# Which class of geometry a feature belongs to, which classes are drawn, and
# what colour a feature comes out under each draw style. All of it without a
# window: the styling is resolved where the geometry is flattened, so what the
# shader is handed says everything about what is drawn.
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


# Root > Shield, Ridge, Stations, Circle and Boundary, which runs along Ridge.
func _build_tree() -> Feature:
	var root := Feature.create_group("Planet")
	root.is_root = true

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


### The draw styles


func test_the_feature_colour_style_gives_each_feature_its_own_colour() -> void:
	var root := _build_tree()
	var colors := _colors_by_class(root, _styled(Styling.BY_FEATURE))
	assert_eq(colors[Styling.POLYGONS], Color.RED, "the shield")
	assert_eq(colors[Styling.POLYLINES], Color.BLUE, "the ridge")
	assert_eq(colors[Styling.POINTS], Color.GREEN, "the stations")
	assert_eq(colors[Styling.TOPOLOGIES], Color.MAGENTA, "the boundary")


func test_the_single_colour_style_gives_every_feature_the_same_one() -> void:
	var root := _build_tree()
	var settings := _styled(Styling.BY_SINGLE)
	settings.single_color = Color(0.2, 0.4, 0.6, 1.0)
	var colors := _colors_by_class(root, settings)
	for class_id in Styling.CLASSES:
		assert_eq(colors[class_id], settings.single_color, "%s is the one colour" % class_id)


# A feature's age is the older end of its time range: when it came into being.
func test_the_feature_age_style_reads_the_palette_at_the_start_of_the_range() -> void:
	var root := _build_tree()
	var settings := _styled(Styling.BY_AGE)
	settings.palette = "steps"
	var palette := Palette.built_in("steps")
	var colors := _colors_by_class(root, settings)
	assert_eq(colors[Styling.POLYGONS], palette.color_at(100.0), "the shield, 100 Ma old")
	assert_eq(colors[Styling.POLYLINES], palette.color_at(500.0), "the ridge, 500")
	assert_eq(colors[Styling.POINTS], palette.color_at(900.0), "the stations, 900")
	assert_eq(colors[Styling.TOPOLOGIES], palette.color_at(700.0), "the boundary, 700")
	assert_eq(Styling.age_of(_feature(root, Styling.POINTS)), 900.0,
		"which is the older end of the range, not the younger")


func test_the_feature_type_style_gives_the_colour_of_the_type() -> void:
	var root := _build_tree()
	var colors := _colors_by_class(root, _styled(Styling.BY_TYPE))
	assert_eq(colors[Styling.POLYGONS], FeatureType.color("polygon"), "the shield is a polygon")
	assert_eq(colors[Styling.POLYLINES], FeatureType.color("line"), "the ridge is a line")
	assert_eq(colors[Styling.POINTS], FeatureType.color("points"), "the stations are points")
	assert_eq(colors[Styling.CIRCLES], FeatureType.color(FeatureType.CIRCLE), "the circle")


# A document that names no style is drawn the way every document was before
# there were any: each feature in the colour it carries.
func test_a_document_that_names_no_style_draws_the_feature_colours() -> void:
	var root := _build_tree()
	var settings := ViewSettings.new()
	assert_eq(settings.draw_style, Styling.BY_FEATURE, "the style a fresh block has")
	assert_eq(_colors_by_class(root, settings)[Styling.POLYGONS], Color.RED, "the shield")
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


### Helpers


func _styled(style_id: String) -> ViewSettings:
	var settings := ViewSettings.new()
	settings.draw_style = style_id
	return settings


# How many primitives each class contributes to the flattened geometry.
func _primitives_by_class(root: Feature, settings: ViewSettings) -> Dictionary:
	var counts := {}
	var geometry := Planet.collect_geometry(root, 0.0, Styling.of(settings))
	for primitive in geometry.primitives:
		var class_id := Styling.class_of(primitive["feature"] as Feature)
		counts[class_id] = int(counts.get(class_id, 0)) + 1
	return counts


# The colour each class is drawn in, read off the colours the geometry carries
# for the shader.
func _colors_by_class(root: Feature, settings: ViewSettings) -> Dictionary:
	var colors := {}
	var geometry := Planet.collect_geometry(root, 0.0, Styling.of(settings))
	for index in geometry.features.size():
		colors[Styling.class_of(geometry.features[index])] = geometry.colors[index]
	return colors


# The title of the feature covering a point, empty when nothing is there.
func _hit(root: Feature, settings: ViewSettings, lat: float, lon: float) -> String:
	var geometry := Planet.collect_geometry(root, 0.0, Styling.of(settings))
	var feature := Planet.hit_test(lat, lon, geometry)
	return "" if feature == null else feature.title
