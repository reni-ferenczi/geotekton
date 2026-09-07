extends TestCase

# The feature type catalog: what it holds, and that a feature carries its type
# through the file and the clipboard.


func test_every_type_names_a_kind_and_a_colour() -> void:
	assert_true(FeatureType.CATALOG.has(FeatureType.UNCLASSIFIED),
		"the catalog holds the type a feature has before anyone picks one")
	for type_id in FeatureType.CATALOG:
		var entry: Dictionary = FeatureType.CATALOG[type_id]
		assert_true(not str(entry.get("name", "")).is_empty(), "%s has a name" % type_id)
		var kinds: Array = entry.get("kinds", [])
		assert_true(not kinds.is_empty(), "%s allows at least one geometry kind" % type_id)
		for kind_name in kinds:
			assert_true(Feature.KIND_VALUES.has(kind_name),
				"%s allows %s, which is a geometry kind" % [type_id, kind_name])
		assert_true(entry.get("color") is Color, "%s has a default colour" % type_id)


func test_the_catalog_covers_every_geometry_kind() -> void:
	for kind_name in Feature.KIND_VALUES:
		var found := false
		for type_id in FeatureType.CATALOG:
			if type_id != FeatureType.UNCLASSIFIED and FeatureType.allows(type_id, kind_name):
				found = true
		assert_true(found, "some type other than unclassified allows a %s" % kind_name)


func test_the_unclassified_type_allows_everything() -> void:
	for kind_name in Feature.KIND_VALUES:
		assert_true(FeatureType.allows(FeatureType.UNCLASSIFIED, kind_name),
			"an unclassified feature may be a %s" % kind_name)


func test_an_unknown_type_reads_back_as_unclassified() -> void:
	assert_eq(FeatureType.normalize("gpml:Volcano"), FeatureType.UNCLASSIFIED)
	assert_eq(FeatureType.normalize("craton"), "craton", "a known id is left alone")
	assert_eq(FeatureType.label("gpml:Volcano"), FeatureType.label(FeatureType.UNCLASSIFIED))


func test_a_new_feature_is_unclassified_in_that_types_colour() -> void:
	var feature := Feature.create_feature("Somewhere")
	assert_eq(feature.feature_type, FeatureType.UNCLASSIFIED)
	assert_eq(feature.color, FeatureType.color(FeatureType.UNCLASSIFIED))


func test_the_type_survives_the_round_trip_and_the_clone() -> void:
	var original := Feature.create_feature("Gondwana")
	original.feature_type = "craton"
	assert_eq(original.clone().feature_type, "craton", "a clone carries the type")
	var restored := Feature.from_json(JSON.parse_string(JSON.stringify(original.to_json())))
	assert_eq(restored.feature_type, "craton", "the file carries the type")


func test_a_file_without_a_type_loads_as_unclassified() -> void:
	var data: Variant = Feature.create_feature("Old").to_json()
	data.erase("feature_type")
	assert_eq(Feature.from_json(data).feature_type, FeatureType.UNCLASSIFIED,
		"a 0.2.0 feature, which carries no type at all")
