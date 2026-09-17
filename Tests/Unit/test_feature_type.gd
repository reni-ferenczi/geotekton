extends TestCase

# The feature type catalog: what it holds, what a feature's type is before and
# after it holds a shape, and that a type survives the file and the clipboard.

const TRIANGLE := [Vector2(0, 0), Vector2(0, 10), Vector2(10, 0)]


func test_the_catalog_is_the_six_types() -> void:
	assert_eq(FeatureType.CATALOG.keys(),
		["polygon", "line", "points", "circle", "topology", "hotspot"],
		"in the order the selector lists them")


func test_every_type_names_a_kind_and_a_colour() -> void:
	for type_id in FeatureType.CATALOG:
		var entry: Dictionary = FeatureType.CATALOG[type_id]
		assert_true(not str(entry.get("name", "")).is_empty(), "%s has a name" % type_id)
		var kinds: Array = entry.get("kinds", [])
		assert_true(not kinds.is_empty(), "%s allows at least one geometry kind" % type_id)
		for kind_name in kinds:
			assert_true(Feature.KIND_VALUES.has(kind_name),
				"%s allows %s, which is a geometry kind" % [type_id, kind_name])
		assert_true(entry.get("color") is Color, "%s has a default colour" % type_id)


func test_every_geometry_kind_gives_a_type_that_holds_it() -> void:
	for kind_name in Feature.KIND_VALUES:
		var type_id := FeatureType.resolve(FeatureType.NONE, kind_name)
		assert_true(FeatureType.CATALOG.has(type_id), "a %s gives a type: %s" % [kind_name, type_id])
		assert_true(FeatureType.allows(type_id, kind_name), "which holds a %s" % kind_name)


func test_a_new_feature_is_a_polygon() -> void:
	var feature := Feature.create_feature("Somewhere")
	assert_eq(feature.feature_type, FeatureType.POLYGON, "which is what the Draw tool then draws")
	assert_eq(feature.color, Color(0.36, 0.60, 0.33), "in the Polygon colour")
	assert_eq(FeatureType.label(feature.feature_type), "Polygon", "and what the selector shows")
	feature.add_ring(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]), Feature.GeometryKind.POLYLINE)
	assert_eq(feature.feature_type, "line", "a polyline it was given anyway makes it a Line")


func test_a_feature_holding_nothing_keeps_the_type_it_was_given() -> void:
	var feature := Feature.create_feature("Ridge")
	feature.feature_type = "line"
	assert_eq(feature.feature_type, "line", "which is what says it is drawn as a polyline")
	assert_eq(FeatureType.resolve("line", ""), "line", "holding nothing keeps the stored type")
	assert_eq(FeatureType.resolve("volcano", ""), FeatureType.NONE,
		"but a type nobody has is still no type")


func test_a_carried_type_that_does_not_hold_the_geometry_gives_way() -> void:
	var feature := Feature.create_feature("Shape")
	feature.add_ring(PackedVector2Array(TRIANGLE), Feature.GeometryKind.POLYGON)
	feature.feature_type = "points"
	assert_eq(feature.feature_type, "polygon", "points cannot be a polygon")
	feature.feature_type = "volcano"
	assert_eq(feature.feature_type, "polygon", "and a type nobody has is no type")
	feature.feature_type = FeatureType.CIRCLE
	assert_eq(feature.feature_type, FeatureType.CIRCLE, "a circle can")
	feature.rings.clear()
	assert_eq(feature.feature_type, FeatureType.CIRCLE,
		"and an emptied feature keeps the type it was carrying")


func test_the_circle_survives_the_round_trip_and_the_clone() -> void:
	var original := Feature.create_feature("Caldera")
	original.add_ring(PackedVector2Array(TRIANGLE), Feature.GeometryKind.POLYGON)
	original.feature_type = FeatureType.CIRCLE
	assert_eq(original.clone().feature_type, FeatureType.CIRCLE, "a clone carries the type")
	var restored := Feature.from_json(JSON.parse_string(JSON.stringify(original.to_json())))
	assert_eq(restored.feature_type, FeatureType.CIRCLE, "the file carries the type")


func test_a_file_without_a_type_takes_it_from_the_geometry() -> void:
	var feature := Feature.create_feature("Old")
	feature.add_ring(PackedVector2Array(TRIANGLE), Feature.GeometryKind.MULTIPOINT)
	var data: Variant = feature.to_json()
	data.erase("feature_type")
	assert_eq(Feature.from_json(data).feature_type, "points",
		"a 0.2.0 feature, which carries no type at all")


func test_a_filled_circle_from_an_older_file_is_still_a_circle() -> void:
	assert_eq(FeatureType.kinds(FeatureType.CIRCLE)[0], "polyline",
		"an empty Circle is drawn as an outline")
	var filled := Feature.create_feature("Caldera")
	filled.add_ring(PackedVector2Array(TRIANGLE), Feature.GeometryKind.POLYGON)
	var data: Variant = filled.to_json()
	data["feature_type"] = FeatureType.CIRCLE
	var restored := Feature.from_json(data)
	assert_eq(restored.geometry_kind, Feature.GeometryKind.POLYGON, "it stays filled")
	assert_eq(restored.feature_type, FeatureType.CIRCLE, "and reads back as a Circle")
