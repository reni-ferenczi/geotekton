extends TestCase

# Document.migrate brings an older file up to the format this version writes.
# 0.2.0 turned the flat triangle list of each leaf into the outline those
# triangles cover and dropped the five rule editor switches; 0.4.0 turned the
# one rotation a leaf carried into the keyframe at time zero; 0.8.0 folded the
# keyframes of groups into the leaves under them; 0.9.0 cut eight feature types
# down to five; 0.10.0 moved the draw style onto the root group; 0.13.0 made the
# group style's ramp a list of colours. The samples in
# Tests/Data are still written in 0.1.0, so they run through every step.

const DATA_DIR := "res://Tests/Data"
const OLD_SAMPLES := ["triangle.middle-earth", "two_cratons.middle-earth", "empty.middle-earth"]

# Two triangles sharing an edge, so their outline is one quad, and one triangle
# far away from them, so the feature ends up with two rings.
const TWO_RINGS := [
	[0.0, 0.0], [0.0, 20.0], [20.0, 20.0],
	[0.0, 0.0], [20.0, 20.0], [20.0, 0.0],
	[-40.0, -40.0], [-40.0, -20.0], [-20.0, -20.0],
]


func test_the_samples_keep_the_edges_their_triangles_left_on_the_boundary() -> void:
	for file_name in OLD_SAMPLES:
		var raw := _read("%s/%s" % [DATA_DIR, file_name])
		if raw.is_empty():
			continue
		assert_eq(str(raw.get("version", "")), "0.1.0", "%s is a 0.1.0 file" % file_name)

		var before: Array = []
		_collect_leaves(raw["features"], before)
		var migrated := Document.migrate(raw.duplicate(true))
		assert_eq(str(migrated["version"]), "0.26.0", "%s is migrated to 0.26.0" % file_name)

		var after: Array = []
		_collect_leaves(migrated["features"], after)
		assert_eq(after.size(), before.size(), "%s keeps every leaf" % file_name)

		for i in range(mini(before.size(), after.size())):
			var label := "%s leaf %d" % [file_name, i]
			var triangles: Array = before[i].get("vertices", [])
			assert_eq(after[i].get("geometry_kind", ""), "polygon", "%s is a polygon" % label)
			assert_eq(_boundary_edges(triangles), _ring_edges(after[i]["rings"]),
				"%s recovers the outline of its triangles" % label)

			# The outline covers the same area: triangulating it again gives the
			# same number of triangles the file held.
			var feature := Feature.from_json(after[i])
			assert_eq(feature.triangles.size(), triangles.size(),
				"%s triangulates back to the same triangle count" % label)


func test_a_feature_of_two_separate_polygons_becomes_two_rings() -> void:
	var leaf := _migrate_leaf({"type": "Feature", "title": "Islands", "vertices": TWO_RINGS})
	var rings: Array = leaf["rings"]
	assert_eq(rings.size(), 2, "one ring per polygon")
	var sizes := [rings[0].size(), rings[1].size()]
	sizes.sort()
	assert_eq(sizes, [3, 4], "a triangle and the quad the two shared triangles cover")
	assert_eq(_boundary_edges(TWO_RINGS), _ring_edges(rings),
		"both outlines are the edges used by a single triangle")


func test_the_rule_editor_switches_are_dropped() -> void:
	var leaf := _migrate_leaf({
		"type": "Feature", "title": "Old", "vertices": [],
		"invert": true, "single": true, "wrap": true, "resize": 2, "repeat": true,
	})
	for key in ["invert", "single", "wrap", "resize", "repeat"]:
		assert_true(not leaf.has(key), "the %s switch is dropped" % key)


func test_a_group_is_migrated_through_its_children() -> void:
	var migrated := Document.migrate({"version": "0.1.0", "features": {
		"type": "Group", "title": "Planet", "repeat": true, "children": [
			{"type": "Feature", "title": "Craton", "vertices": TWO_RINGS.slice(0, 3)},
		],
	}})
	var group: Dictionary = migrated["features"]
	assert_true(not group.has("repeat"), "the switch is dropped on a group too")
	assert_eq(group["children"][0]["rings"].size(), 1, "the child is migrated as well")


func test_the_oldest_files_called_the_rotation_a_position() -> void:
	var leaf := _migrate_leaf({
		"type": "Feature", "title": "Old", "vertices": [], "position": [10.0, 20.0, 30.0]})
	assert_eq(_only_keyframe(leaf).get("rotation", []), [10.0, 20.0, 30.0],
		"the position becomes the rotation of the keyframe at time zero")
	assert_true(not leaf.has("position"), "and the old key is gone")


func test_the_one_rotation_of_a_0_3_0_leaf_becomes_the_keyframe_at_time_zero() -> void:
	var leaf := _migrate_0_3_0({
		"type": "Feature", "title": "Craton", "geometry_kind": "polygon",
		"rings": [[[0.0, 0.0], [0.0, 10.0], [10.0, 10.0]]], "rotation": [60.0, 0.0, 0.0],
	})
	assert_true(not leaf.has("rotation"), "the single rotation is gone")
	var keyframe := _only_keyframe(leaf)
	assert_eq(keyframe.get("time", -1.0), 0.0, "the keyframe is at the present")
	assert_eq(keyframe.get("rotation", []), [60.0, 0.0, 0.0], "and holds what the file said")

	# A feature that came in this way behaves as it did before the phase: one
	# keyframe holds its rotation whatever time it is asked about.
	var feature := Feature.from_json(leaf)
	for time in [0.0, 500.0, 2000.0]:
		assert_close(feature.rotation_at(time), Vector3(60, 0, 0), 1e-6,
			"one keyframe holds at %s Ma" % time)


func test_a_group_arrives_without_keyframes() -> void:
	var group := _migrate_0_3_0({
		"type": "Group", "title": "Planet", "children": [
			{"type": "Feature", "title": "Craton", "rings": [], "rotation": [1.0, 2.0, 3.0]},
		],
	})
	assert_eq(group.get("keyframes", []), [], "a group had no rotation to carry over")
	assert_eq(_only_keyframe(group["children"][0]).get("rotation", []), [1.0, 2.0, 3.0],
		"but the leaf under it did")


func test_a_leaf_at_0_4_0_under_no_moving_group_is_left_alone() -> void:
	var data := {"version": "0.4.0", "features": {
		"type": "Feature", "title": "New", "geometry_kind": "polyline",
		"rings": [[[0.0, 0.0], [0.0, 10.0]]],
		"keyframes": [{"time": 0.0, "rotation": [0.0, 0.0, 0.0]}],
	}}
	var migrated := Document.migrate(data.duplicate(true))
	var expected: Dictionary = data["features"].duplicate(true)
	expected["feature_type"] = FeatureType.NONE
	assert_eq(migrated["features"], expected, "the leaf is as it was, its type left to its geometry")
	assert_eq(migrated["version"], "0.26.0", "at the current version")


### 0.7.0 to 0.8.0: groups stop carrying motion


func test_a_moving_group_is_folded_into_its_leaves() -> void:
	# The group turns 30 degrees about the poles and the terrane 20 of its own,
	# both by 100 Ma, which up to 0.7.0 put the terrane at 50 degrees then.
	var migrated := Document.migrate({"version": "0.7.0", "features": {
		"type": "Group", "title": "Planet", "children": [{
			"type": "Group", "title": "Craton",
			"keyframes": [
				{"time": 0.0, "rotation": [0.0, 0.0, 0.0]},
				{"time": 100.0, "rotation": [30.0, 0.0, 0.0]}],
			"children": [{
				"type": "Feature", "title": "Terrane", "rings": [],
				"keyframes": [
					{"time": 0.0, "rotation": [0.0, 0.0, 0.0]},
					{"time": 100.0, "rotation": [20.0, 0.0, 0.0]}],
			}],
		}],
	}})
	var craton: Dictionary = migrated["features"]["children"][0]
	assert_true(not craton.has("keyframes"), "the group's keyframes are gone")
	var terrane: Dictionary = craton["children"][0]
	var times: Array = []
	for keyframe in terrane["keyframes"]:
		times.append(keyframe["time"])
	assert_eq(times, [0.0, 100.0], "the terrane keeps its keyframe times")
	assert_close(Vector3(terrane["keyframes"][1]["rotation"][0], 0.0, 0.0), Vector3(50, 0, 0), 1e-6,
		"and holds where the group had put it at 100 Ma: %s" % [terrane["keyframes"][1]])


func test_a_still_leaf_takes_its_moving_group_s_keyframes() -> void:
	var migrated := Document.migrate({"version": "0.7.0", "features": {
		"type": "Group", "title": "Planet",
		"keyframes": [{"time": 200.0, "rotation": [0.0, 45.0, 0.0]}],
		"children": [{"type": "Feature", "title": "Leaf", "rings": [], "keyframes": []}],
	}})
	var leaf: Dictionary = migrated["features"]["children"][0]
	assert_eq(leaf["keyframes"].size(), 1, "one keyframe, from the root's one")
	assert_close(leaf["keyframes"][0]["time"], 200.0, 1e-9)
	var rotation: Array = leaf["keyframes"][0]["rotation"]
	assert_close(Vector3(rotation[0], rotation[1], rotation[2]), Vector3(0, 45, 0), 1e-6,
		"and it is the root's rotation")
	assert_true(not migrated["features"].has("keyframes"), "the root has none any more")


func test_a_leaf_under_a_still_group_is_left_alone() -> void:
	var leaf := {"type": "Feature", "title": "Alone", "rings": [],
		"keyframes": [{"time": 0.0, "rotation": [1.0, 2.0, 3.0]}]}
	var migrated := Document.migrate({"version": "0.7.0", "features": {
		"type": "Group", "title": "Planet", "keyframes": [], "children": [leaf.duplicate(true)],
	}})
	assert_eq(migrated["features"]["children"][0], leaf.merged({"feature_type": FeatureType.NONE}),
		"nothing above it moved, so it is as it was, its type left to its geometry")


### 0.8.0 to 0.9.0: five feature types


# The old type, the kind the feature holds, and the type it opens as.
const OLD_TYPES := [
	["craton", "polygon", "polygon"],
	["terrane", "polygon", "polygon"],
	["coastline", "polygon", "polygon"],
	["coastline", "polyline", "line"],
	["ridge", "polyline", "line"],
	["marker", "multipoint", "points"],
	["small_circle", "polygon", "circle"],
	["small_circle", "polyline", "circle"],
	["unclassified", "polygon", "polygon"],
	["unclassified", "polyline", "line"],
	["unclassified", "multipoint", "points"],
	["volcano", "polygon", "polygon"],
]


func test_a_0_7_0_file_opens_each_old_type_as_one_of_the_five() -> void:
	var children: Array = []
	for entry in OLD_TYPES:
		children.append({"type": "Feature", "title": "%s as %s" % [entry[0], entry[1]],
			"uuid": "uuid-%d" % children.size(), "feature_type": entry[0],
			"geometry_kind": entry[1], "rings": [[[0.0, 0.0], [0.0, 10.0], [10.0, 0.0]]]})
	children.append({"type": "Feature", "title": "Boundary", "feature_type": "topology",
		"geometry_kind": "topology",
		"sections": [{"feature": "uuid-4", "part": 0, "from": 0, "to": 2, "reversed": false}]})
	children.append({"type": "Feature", "title": "Empty", "feature_type": "craton", "rings": []})

	var migrated := Document.migrate({"version": "0.7.0",
		"features": {"type": "Group", "title": "Planet", "children": children},
		"view": {"hidden_classes": ["small_circles", "points"]}})
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var root := Feature.from_json(migrated["features"])
	for i in OLD_TYPES.size():
		assert_eq(root.children[i].feature_type, OLD_TYPES[i][2], root.children[i].title)
	assert_eq(root.children[-2].feature_type, "topology", "a topology stays one")
	assert_eq(root.children[-1].feature_type, "polygon",
		"a feature holding nothing keeps the type the migration gave it")
	assert_eq(Array(ViewSettings.from_json(migrated["view"]).hidden_classes), ["circles", "points"],
		"and the circles are still switched off")


# Every sample opens with the type its geometry gives, whichever format it is in
# and whatever type it names; none of them holds a circle.
func test_every_sample_opens_with_one_of_the_five() -> void:
	var names := DirAccess.get_files_at(DATA_DIR)
	var opened := 0
	for file_name in names:
		if not file_name.ends_with(".middle-earth"):
			continue
		var document := Document.new()
		var error := document.load_from_file("%s/%s" % [DATA_DIR, file_name])
		assert_eq(error, "", "%s opens" % file_name)
		opened += 1
		var stack: Array[Feature] = [document.root]
		while not stack.is_empty():
			var node: Feature = stack.pop_back()
			stack.append_array(node.children)
			if node.is_group:
				continue
			assert_eq(node.feature_type, FeatureType.resolve(FeatureType.NONE, node.kind_name()),
				"%s in %s" % [node.title, file_name])
			assert_true(FeatureType.CATALOG.has(node.feature_type), "which is in the catalog")
	assert_true(opened >= 7, "every sample was opened: %d" % opened)


### 0.9.0 to 0.10.0: the draw style becomes the root group's


# The three styling keys of a 0.7.0 view block land on the root group. A
# document opened from it pins the root's style after that (GP-0066), which
# Tests/Unit/test_styling.gd checks.
func test_a_0_7_0_draw_style_becomes_the_style_of_the_root_group() -> void:
	var migrated := Document.migrate({"version": "0.7.0",
		"features": {"type": "Group", "title": "Planet", "children": []},
		"view": {"draw_style": "single", "single_color": [0.1, 0.6, 0.9, 0.75],
			"palette": "rainbow", "ambient": 0.25}})
	for key in GroupStyle.VIEW_KEYS:
		assert_true(not migrated["view"].has(key), "%s has left the view block" % key)
	assert_eq(migrated["view"]["ambient"], 0.25, "and the rest of the block stays")
	var root := Feature.from_json(migrated["features"])
	assert_eq(root.style.mode, Styling.BY_SINGLE, "the root carries the style")
	assert_eq(root.style.color, Color(0.1, 0.6, 0.9, 0.75), "the single colour, alpha and all")
	assert_eq(root.style.palette, "rainbow", "the palette")
	assert_eq(root.style.opacity, 1.0, "at full opacity, so it draws the same")


# A block that named no style leaves the root on the default, and so does a
# style that no version knew, which is what the view block did with one.
func test_a_block_without_a_style_leaves_the_root_on_its_own_colours() -> void:
	var path := ProjectSettings.globalize_path("user://test_migration_0_9_0.middle-earth")
	for view in [{}, {"draw_style": "by_plate_id"}]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"application": "middle-earth", "version": "0.9.0",
			"features": {"type": "Group", "is_group": true, "title": "Planet", "children": []},
			"view": view}))
		file.close()
		var document := Document.new()
		assert_eq(document.load_from_file(path), "", "a 0.9.0 file opens")
		assert_eq(document.root.style.mode, Styling.BY_FEATURE, "on own colours from %s" % [view])
	DirAccess.remove_absolute(path)


# 0.9.0 already has the five types, so the step before is not run on it again:
# mapped twice, every type would be lost.
func test_a_0_9_0_file_keeps_its_types() -> void:
	var migrated := Document.migrate({"version": "0.9.0", "features": {
		"type": "Group", "title": "Planet", "children": [
			{"type": "Feature", "title": "Ring", "feature_type": "circle", "rings": []}]}})
	assert_eq(migrated["features"]["children"][0]["feature_type"], "circle", "the circle stays one")
	assert_eq(migrated["version"], "0.26.0", "at the current version")


### 0.12.0 to 0.13.0: the ramp's two ends become a list of colours


# A style with both ends of the old two colour ramp keeps them as the two stops
# of the new list, and the two keys go.
func test_a_0_12_0_ramp_becomes_a_list_of_its_two_ends() -> void:
	var brown := [0.55, 0.35, 0.2, 1.0]
	var grey := [0.6, 0.6, 0.6, 1.0]
	var style := {"mode": "age", "palette": "ramp", "ramp_span": 450.0,
		"ramp_from": brown, "ramp_to": grey}
	var migrated := Document.migrate({"version": "0.12.0",
		"features": {"type": "Group", "is_group": true, "title": "Planet", "style": style,
			"children": []}})
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var written: Dictionary = migrated["features"]["style"]
	assert_eq(written.get("ramp_colors"), [brown, grey], "the two ends are the two stops")
	assert_true(not written.has("ramp_from") and not written.has("ramp_to"), "and the keys are gone")
	var root := Feature.from_json(migrated["features"])
	assert_eq(root.style.ramp_colors,
		[Color(0.55, 0.35, 0.2, 1.0), Color(0.6, 0.6, 0.6, 1.0)], "read back as colours")
	assert_eq(root.style.ramp_span, 450.0, "over the span it named")


# A style that named no ramp at all takes the new default, black to white.
func test_a_0_12_0_style_without_a_ramp_takes_the_new_default() -> void:
	var style := {"mode": "age", "color": [0.9, 0.9, 0.9, 1.0], "opacity": 0.5, "palette": "rainbow"}
	var migrated := Document.migrate({"version": "0.10.0",
		"features": {"type": "Group", "is_group": true, "title": "Planet", "style": style.duplicate(),
			"children": []}})
	assert_eq(migrated["features"]["style"], style, "the style is left as it was")
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var root := Feature.from_json(migrated["features"])
	assert_eq(root.style.palette, "rainbow", "the palette it named")
	assert_eq(root.style.ramp_colors, Palette.DEFAULT_RAMP_COLORS, "and the default ramp")
	assert_eq(root.style.ramp_span, Palette.DEFAULT_RAMP_SPAN, "over its default span")


# The three built in tables 0.13.0 dropped: a style that named one of them has
# nothing left to read, so it takes the custom ramp that replaced them.
func test_a_style_naming_a_dropped_built_in_takes_the_custom_ramp() -> void:
	for gone in Document.PALETTES_BEFORE_0_13_0:
		var migrated := Document.migrate({"version": "0.12.0", "features": {
			"type": "Group", "is_group": true, "title": "Planet",
			"style": {"mode": "age", "palette": gone}, "children": []}})
		assert_eq(Feature.from_json(migrated["features"]).style.palette, Palette.RAMP,
			"a style on %s reads the custom ramp" % gone)


### 0.13.0 to 0.14.0: a leaf may carry the icon of its tree row


# There is no step: a leaf without the key has no icon, which is what every
# feature had before there were any.
func test_a_0_13_0_leaf_reads_with_no_icon() -> void:
	var migrated := Document.migrate({"version": "0.13.0", "features": {
		"type": "Group", "is_group": true, "title": "Planet", "children": [
			{"type": "Feature", "title": "Shield", "rings": []}]}})
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var leaf: Feature = Feature.from_json(migrated["features"]).children[0]
	assert_eq(leaf.icon, FeatureIcon.NONE, "and the leaf carries no icon")


### 0.14.0 to 0.15.0: a coupling span may name a second parent


# There is no step either: a span without the key follows one parent, which is
# what every span did before a ridge followed two.
func test_a_0_14_0_span_reads_with_one_parent() -> void:
	var migrated := Document.migrate({"version": "0.14.0", "features": {
		"type": "Group", "is_group": true, "title": "Planet", "children": [
			{"type": "Feature", "title": "Shield", "rings": [],
				"couplings": [{"from": 500.0, "to": 200.0, "parent": "a-uuid"}]}]}})
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var leaf: Feature = Feature.from_json(migrated["features"]).children[0]
	assert_eq(leaf.couplings[0].parent, "a-uuid", "the parent it named")
	assert_eq(leaf.couplings[0].parent_b, "", "and no second one")


### 0.15.0 to 0.16.0: the backdrop is a raster and the graticule a grid


const VIEW_0_15_0 := {
	"backdrop_path": "art/earth.png",
	"backdrop_opacity": 0.4,
	"backdrop_visible": false,
	"graticule_color": [0.9, 0.4, 0.1, 0.5],
	"graticule_spacing": 30.0,
	"ambient": 0.25,
}
const SCRATCH := "user://test_migration.middle-earth"


func test_a_0_15_0_view_block_keeps_its_raster_and_grid() -> void:
	var migrated := Document.migrate({"version": "0.15.0", "features": {}, "view": VIEW_0_15_0})
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var view: Dictionary = migrated["view"]
	for old: String in Document.VIEW_KEYS_BEFORE_0_16_0:
		assert_true(not view.has(old), "%s is gone" % old)
	var settings := ViewSettings.from_json(view)
	assert_eq(settings.raster_path, "art/earth.png", "the raster")
	assert_close(settings.raster_opacity, 0.4, 1e-6, "its opacity")
	assert_eq(settings.raster_visible, false, "and its switch")
	assert_eq(settings.grid_color, Color(0.9, 0.4, 0.1, 0.5), "the grid color")
	assert_eq(settings.grid_spacing, 30.0, "and its spacing")
	assert_close(settings.ambient, 0.25, 1e-6, "a key that kept its name is left alone")
	assert_eq(VIEW_0_15_0.has("backdrop_path"), true, "and the block passed in is not changed")


### 0.16.0 to 0.17.0: the planet has a color and the Earth is a raster


# A file from before the planet had a color of its own showed the built in Earth
# wherever it named no image, so it gets the Earth as its raster, fully shown.
func test_a_0_16_0_file_with_no_raster_gets_the_built_in_earth() -> void:
	var view := {"raster_path": "", "raster_opacity": 0.3, "raster_visible": false, "ambient": 0.25}
	var migrated := Document.migrate({"version": "0.16.0", "features": {}, "view": view})
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var settings := ViewSettings.from_json(migrated["view"])
	assert_eq(settings.raster_path, ViewSettings.BUILT_IN_EARTH, "the built in Earth")
	assert_close(settings.raster_opacity, 1.0, 1e-6, "fully opaque, as the Earth was")
	assert_eq(settings.raster_visible, true, "and shown")
	assert_close(settings.ambient, 0.25, 1e-6, "the rest of the block is left alone")
	assert_eq(settings.planet_color, ViewSettings.DEFAULT_PLANET_COLOR,
		"and the planet color is the default")
	assert_eq(view["raster_path"], "", "the block passed in is not changed")

	var empty_block := {"version": "0.16.0", "features": {}, "view": {}}
	var no_block := {"version": "0.5.0", "features": {}}
	for bare: Dictionary in [empty_block, no_block]:
		var from_bare := ViewSettings.from_json(Document.migrate(bare)["view"])
		assert_eq(from_bare.raster_path, ViewSettings.BUILT_IN_EARTH,
			"a %s file with the view block %s gets the Earth too" % [bare["version"], bare.get("view")])


func test_the_samples_keep_the_built_in_earth() -> void:
	for file_name in OLD_SAMPLES:
		var document := Document.new()
		assert_eq(document.load_from_file("%s/%s" % [DATA_DIR, file_name]), "",
			"%s loads" % file_name)
		assert_eq(document.view.raster_path, ViewSettings.BUILT_IN_EARTH,
			"%s wears the built in Earth" % file_name)


func test_a_0_16_0_file_naming_a_raster_keeps_it() -> void:
	var view := {"raster_path": "art/earth.png", "raster_opacity": 0.4, "raster_visible": false}
	var migrated := Document.migrate({"version": "0.16.0", "features": {}, "view": view})
	var settings := ViewSettings.from_json(migrated["view"])
	assert_eq(settings.raster_path, "art/earth.png", "the raster")
	assert_close(settings.raster_opacity, 0.4, 1e-6, "its opacity")
	assert_eq(settings.raster_visible, false, "and its switch")


func test_a_new_document_has_no_raster() -> void:
	var document := Document.new()
	assert_eq(document.view.raster_path, "", "no raster")
	assert_eq(document.view.planet_color, ViewSettings.DEFAULT_PLANET_COLOR,
		"and the default planet color")
	var reread := Document.migrate(document.to_json())
	assert_eq(ViewSettings.from_json(reread["view"]).raster_path, "",
		"and reading it back does not give it the Earth")


### 0.17.0 to 0.18.0: a leaf may carry the parameters of polar circles


# A leaf from before has none of the three keys, which reads as a feature that
# is not polar circles, so only the version moves.
func test_a_0_17_0_file_changes_only_its_version() -> void:
	var leaf := {"type": "Feature", "title": "Ring", "feature_type": "circle",
		"geometry_kind": "polyline", "rings": [[[0.0, 0.0], [0.0, 10.0]]]}
	var raw := {"version": "0.17.0", "features": {"type": "Group", "title": "Root",
		"children": [leaf]}, "view": {"raster_path": "art/earth.png"}}
	var migrated := Document.migrate(raw)
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var expected := raw.duplicate(true)
	expected["version"] = "0.26.0"
	assert_eq(migrated, expected, "and nothing else changed")
	assert_eq(raw["version"], "0.17.0", "the data passed in is not changed")
	var feature := Feature.from_json(migrated["features"]["children"][0])
	assert_eq(feature.feature_type, "circle", "the leaf keeps its type")
	assert_eq(feature.rings[0].size(), 2, "and its rings")


### 0.18.0 to 0.19.0: a leaf may carry the parameters of a hotspot


# A leaf from before has none of the three keys, which reads as a feature that
# is not a hotspot, so this step moves only the version. The polar circles leaf
# is a circle from 0.21.0 on.
func test_a_0_18_0_file_changes_only_its_version() -> void:
	var leaf := {"type": "Feature", "title": "Aurora", "feature_type": "polar_circles",
		"geometry_kind": "polyline", "rings": [[[0.0, 0.0], [0.0, 10.0]]],
		"axis": [90.0, 0.0], "radius": 23.0, "circle_segments": 36}
	var raw := {"version": "0.18.0", "features": {"type": "Group", "title": "Root",
		"children": [leaf]}, "view": {"raster_path": "art/earth.png"}}
	var migrated := Document.migrate(raw)
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var expected := raw.duplicate(true)
	expected["version"] = "0.26.0"
	expected["features"]["children"][0]["feature_type"] = "circle"
	expected["features"]["children"][0]["polar"] = true
	assert_eq(migrated, expected, "and nothing else changed")
	assert_eq(raw["version"], "0.18.0", "the data passed in is not changed")
	var feature := Feature.from_json(migrated["features"]["children"][0])
	assert_eq(feature.feature_type, "circle", "the leaf is a circle")
	assert_true(not feature.is_hotspot(), "and no hotspot")


### 0.19.0 to 0.20.0: a topology may be closed


# A topology from before has no `closed` key, which reads as an open one, so
# only the version moves.
func test_a_0_19_0_file_changes_only_its_version() -> void:
	var leaf := {"type": "Feature", "title": "Boundary", "feature_type": "topology",
		"geometry_kind": "topology", "sections": [
			{"feature": "a", "part": 0, "from": 0, "to": 1, "reversed": false}]}
	var raw := {"version": "0.19.0", "features": {"type": "Group", "title": "Root",
		"children": [leaf]}, "view": {"raster_path": "art/earth.png"}}
	var migrated := Document.migrate(raw)
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var expected := raw.duplicate(true)
	expected["version"] = "0.26.0"
	assert_eq(migrated, expected, "and nothing else changed")
	assert_eq(raw["version"], "0.19.0", "the data passed in is not changed")
	var feature := Feature.from_json(migrated["features"]["children"][0])
	assert_eq(feature.sections.size(), 1, "the topology keeps its section")
	assert_true(not feature.closed, "and is open")


### 0.20.0 to 0.21.0: Polar circles become a Circle, and a circle keeps its center


func _load_0_20_0(leaf: Dictionary) -> Feature:
	var raw := {"application": Document.APPLICATION, "version": "0.20.0",
		"features": {"type": "Group", "title": "Root", "children": [leaf]}}
	assert_eq(Document.migrate(raw)["version"], "0.26.0", "at the current version")
	assert_eq(raw["version"], "0.20.0", "the data passed in is not changed")
	var path := SCRATCH.get_base_dir().path_join("circle_0_20_0.middle-earth")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(raw, "\t"))
	file.close()
	var document := Document.new()
	assert_eq(document.load_from_file(path), "", "the 0.20.0 file opens")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return document.root.children[0] if not document.root.children.is_empty() else null


# A polar circles leaf is a circle drawn at both ends of its axis, with the same
# parameters and the same two rings.
func test_polar_circles_from_0_20_0_become_a_polar_circle() -> void:
	var axis := Vector2(80.7, -72.7)
	var antipode := Vector2(-80.7, 107.3)
	var rings: Array[PackedVector2Array] = [Circle.vertices(axis, 23.0, 36, false),
		Circle.vertices(antipode, 23.0, 36, false)]
	var leaf := {"type": "Feature", "title": "Aurora", "feature_type": "polar_circles",
		"geometry_kind": "polyline", "rings": Feature.rings_to_json(rings),
		"axis": [axis.x, axis.y], "radius": 23.0, "circle_segments": 36}
	var migrated := Document.migrate({"version": "0.20.0", "features": leaf.duplicate(true)})
	assert_eq(migrated["features"]["feature_type"], "circle", "the type is Circle")
	assert_eq(migrated["features"]["polar"], true, "drawn at both ends of the axis")

	var feature := _load_0_20_0(leaf)
	assert_eq(feature.feature_type, FeatureType.CIRCLE, "the leaf loads as a circle")
	assert_true(feature.polar, "which is polar")
	assert_close(feature.axis, axis, 1e-4, "around the same axis")
	assert_eq([feature.radius, feature.circle_segments], [23.0, 36], "and the same size")
	assert_eq(feature.rings.size(), 2, "with two rings")
	for part in mini(2, feature.rings.size()):
		for index in rings[part].size():
			assert_close(feature.rings[part][index], rings[part][index], 1e-4,
				"vertex %d of ring %d is where it was" % [index, part])


# A drawn circle kept only its ring. It is given the center, radius and segment
# count of that ring, and the ring rebuilt from them is the one it had.
func test_a_drawn_circle_from_0_20_0_gets_its_center_and_radius() -> void:
	var center := Vector2(-35.2, 141.9)
	var ring := Circle.vertices(center, 12.5, 48, false)
	var leaf := {"type": "Feature", "title": "Crater", "feature_type": "circle",
		"geometry_kind": "polyline", "rings": Feature.rings_to_json([ring])}
	var migrated := Document.migrate({"version": "0.20.0", "features": leaf.duplicate(true)})
	var written: Dictionary = migrated["features"]
	assert_close(Vector2(written["axis"][0], written["axis"][1]), center, 0.01,
		"the step writes the center")
	assert_close(float(written["radius"]), 12.5, 0.01, "the radius")
	assert_eq(int(written["circle_segments"]), 48, "and the segment count")
	assert_true(not written.has("polar"), "and leaves the circle plain")

	var feature := _load_0_20_0(leaf)
	assert_eq(feature.feature_type, FeatureType.CIRCLE, "the leaf loads as a circle")
	assert_true(not feature.polar, "which is not polar")
	assert_eq(feature.rings.size(), 1, "with one ring")
	assert_eq(feature.rings[0].size(), ring.size(), "of as many vertices")
	for index in mini(ring.size(), feature.rings[0].size()):
		assert_close(feature.rings[0][index], ring[index], 0.01,
			"vertex %d is within 0.01 degrees of where it was" % index)


# A circle drawn twice holds two rings and is no single circle. It keeps both
# as a Line rather than lose one.
func test_a_circle_drawn_twice_before_0_21_0_becomes_a_line() -> void:
	var rings: Array[PackedVector2Array] = [Circle.vertices(Vector2(0, 0), 5.0, 12, false),
		Circle.vertices(Vector2(0, 40), 5.0, 12, false)]
	var feature := _load_0_20_0({"type": "Feature", "title": "Twice", "feature_type": "circle",
		"geometry_kind": "polyline", "rings": Feature.rings_to_json(rings)})
	assert_eq(feature.feature_type, FeatureType.LINE, "the leaf is a line")
	assert_eq(feature.rings.size(), 2, "holding both rings")


### 0.21.0 to 0.22.0: a hotspot samples its track at the timeline's Skip


# A hotspot leaf loses its track step and keeps the rest; a leaf of another type
# holding the key, which only a hand written file could, keeps it.
func test_a_0_21_0_hotspot_loses_its_track_step() -> void:
	var hotspot := {"type": "Feature", "title": "Hawaii", "feature_type": "hotspot",
		"geometry_kind": "polyline", "rings": [[[19.0, -155.0], [19.0, -154.0]]],
		"hotspot": [19.4, -155.3], "plate": "pacific", "track_step": 2.5}
	var other := {"type": "Feature", "title": "Line", "feature_type": "line",
		"geometry_kind": "polyline", "rings": [[[0.0, 0.0], [0.0, 10.0]]], "track_step": 5.0}
	var raw := {"version": "0.21.0", "features": {"type": "Group", "title": "Root",
		"children": [{"type": "Group", "title": "Group", "children": [hotspot]}, other]}}
	var migrated := Document.migrate(raw)
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var expected := raw.duplicate(true)
	expected["version"] = "0.26.0"
	expected["features"]["children"][0]["children"][0].erase("track_step")
	assert_eq(migrated, expected, "and only the hotspot's track step is gone")
	assert_eq(raw["version"], "0.21.0", "the data passed in is not changed")
	var feature := Feature.from_json(migrated["features"]["children"][0]["children"][0])
	assert_true(feature.is_hotspot() and Hotspot.placed(feature), "the hotspot stays placed")
	assert_close(feature.hotspot, Vector2(19.4, -155.3), 1e-9, "where it was")
	assert_eq(feature.plate_uuid, "pacific", "on its plate")


### 0.22.0 to 0.23.0: the ridge is a topology and the crust is bands


# What the Split tool left at 0.22.0: two halves, the first holding its side of
# the cut in part 1, a ridge following both, and a closed topology beside each
# half running along it and back along the ridge. A closed topology along
# something else is not a crust.
func _split_0_22_0() -> Dictionary:
	var half := func(uuid: String, rings: Array) -> Dictionary:
		return {"type": "Feature", "uuid": uuid, "title": uuid.capitalize(),
			"feature_type": "polygon", "geometry_kind": "polygon", "rings": rings,
			"keyframes": [], "couplings": []}
	var square := [[0.0, 0.0], [0.0, 10.0], [10.0, 10.0], [10.0, 0.0]]
	var ridge := {"type": "Feature", "uuid": "ridge", "title": "West ridge",
		"feature_type": "line", "geometry_kind": "polyline", "time_range": [0, 100],
		"rings": [[[0.0, 0.0], [5.0, 1.0], [10.0, 0.0]]],
		"keyframes": [{"time": 100.0, "rotation": [0.0, 0.0, 0.0]}],
		"couplings": [{"from": 100.0, "to": 0.0, "parent": "west", "parent_b": "east"}]}
	var crust := func(uuid: String, half_uuid: String, part: int) -> Dictionary:
		return {"type": "Feature", "uuid": uuid, "title": "%s crust" % half_uuid.capitalize(),
			"feature_type": "topology", "geometry_kind": "topology", "closed": true,
			"color": [0.0, 0.0, 1.0, 1.0], "time_range": [0, 100], "keyframes": [],
			"couplings": [], "sections": [
				{"feature": half_uuid, "part": part, "from": 0, "to": 2, "reversed": false},
				{"feature": "ridge", "part": 0, "from": 0, "to": 2, "reversed": true}]}
	var other := {"type": "Feature", "uuid": "other", "title": "Other",
		"feature_type": "topology", "geometry_kind": "topology", "closed": true,
		"sections": [
			{"feature": "west", "part": 0, "from": 0, "to": 2, "reversed": false},
			{"feature": "east", "part": 0, "from": 0, "to": 2, "reversed": false}]}
	return {"version": "0.22.0", "features": {"type": "Group", "title": "Root", "children": [
		{"type": "Group", "title": "Plates", "children": [
			half.call("west", [square, square]), half.call("east", [square]), ridge,
			crust.call("west-crust", "west", 1), crust.call("east-crust", "east", 0)]},
		other]}}


func test_a_0_22_0_ridge_becomes_a_midway_topology() -> void:
	var raw := _split_0_22_0()
	var migrated := Document.migrate(raw)
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	assert_eq(raw["version"], "0.22.0", "the data passed in is not changed")
	var ridge := Feature.from_json(migrated["features"]["children"][0]["children"][2])
	assert_true(ridge.midway and ridge.geometry_kind == Feature.GeometryKind.TOPOLOGY,
		"the ridge is a midway topology")
	assert_eq(ridge.feature_type, "topology", "typed as one")
	assert_eq(ridge.title, "West ridge", "keeping its title")
	assert_eq(ridge.time_range, Vector2i(0, 100), "and its time range")
	assert_eq(ridge.keyframes.size() + ridge.couplings.size(), 0, "with no motion")
	assert_eq(TopologySection.list_to_json(ridge.sections), [
		{"feature": "west", "part": 1, "from": 0, "to": 2, "reversed": false},
		{"feature": "east", "part": 0, "from": 0, "to": 2, "reversed": true}],
		"between the part the west crust ran along and the east half, walked back")
	assert_true(not migrated["features"]["children"][0]["children"][2].has("rings"),
		"and no rings of its own")


func test_a_0_22_0_crust_becomes_bands() -> void:
	var migrated := Document.migrate(_split_0_22_0())
	var plates: Array = migrated["features"]["children"][0]["children"]
	assert_eq(plates.map(func(leaf: Dictionary) -> String: return leaf["title"]),
		["West", "East", "West ridge", "West crust", "East crust"], "one crust per half")
	for index in [3, 4]:
		var crust := Feature.from_json(plates[index])
		var half := "west" if index == 3 else "east"
		assert_true(crust.is_crust() and crust.closed, "%s is a crust" % crust.title)
		assert_eq([crust.crust_half, crust.crust_ridge, crust.crust_edge], [half, "ridge", 3],
			"beside its half, opened by the ridge, along a cut of three")
		assert_true(crust.sections.is_empty(), "with no sections")
		assert_eq(crust.color, Color(0, 0, 1, 1), "keeping its colour")
		assert_eq(crust.line_color(crust.color), FeatureType.color(FeatureType.CRUST_LINES),
			"and drawing its lines in their own colour")
	var other: Dictionary = migrated["features"]["children"][1]
	assert_eq(other, _split_0_22_0()["features"]["children"][1],
		"a closed topology along two plates is left alone")


### 0.23.0 to 0.24.0: the crust draws its own isochrons and flowlines


# What the Split tool left at 0.23.0: the two halves, the ridge, and a lines
# leaf and a crust for each half. Built by migrating the 0.22.0 split, which is
# what wrote those four rows.
func _split_0_23_0() -> Dictionary:
	var data := Document.migrate(_split_0_22_0())
	var plates: Array = data["features"]["children"][0]["children"]
	# Last one first, so inserting does not move the one still to come.
	for index in [4, 3]:
		var crust: Dictionary = plates[index]
		var lines: Dictionary = crust.duplicate(true)
		lines["uuid"] = "%s-lines" % crust["uuid"]
		lines["title"] = "%s lines" % crust["title"]
		lines.erase("closed")
		lines["crust"]["lines"] = true
		plates.insert(index, lines)
	data["version"] = "0.23.0"
	return data


func test_a_0_23_0_crust_keeps_its_bands_and_drops_its_lines_leaf() -> void:
	var raw := _split_0_23_0()
	var before: Array = raw["features"]["children"][0]["children"]
	assert_eq(before.map(func(leaf: Dictionary) -> String: return leaf["title"]),
		["West", "East", "West ridge", "West crust lines", "West crust", "East crust lines",
			"East crust"], "the four crust rows of 0.23.0")
	var migrated := Document.migrate(raw)
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	assert_eq(raw["version"], "0.23.0", "the data passed in is not changed")
	var plates: Array = migrated["features"]["children"][0]["children"]
	assert_eq(plates.map(func(leaf: Dictionary) -> String: return leaf["title"]),
		["West", "East", "West ridge", "West crust", "East crust"],
		"load with one crust per half")
	# The crusts are the fifth and the seventh of the seven rows; nothing else
	# about them moves.
	for pair in [[3, 4], [4, 6]]:
		var crust: Dictionary = plates[pair[0]]
		assert_eq(crust, before[pair[1]], "%s is left as it was" % crust["title"])
		assert_true(not (crust["crust"] as Dictionary).has("lines"),
			"and carries no lines key")
	var other: Dictionary = migrated["features"]["children"][1]
	assert_eq(other, _split_0_22_0()["features"]["children"][1],
		"a closed topology along two plates is still left alone")


# The crust that survives the migration is a working one, drawing between them
# what the two 0.23.0 rows drew: the bands, and the isochrons and the flowlines.
func test_a_migrated_0_23_0_crust_draws_the_bands_and_the_lines() -> void:
	var root := Feature.from_json(Document.migrate(_split_0_23_0())["features"])
	root.is_root = true
	var plates: Feature = root.children[0]
	assert_eq(plates.children.size(), 5, "the split leaves five rows")
	for index in [3, 4]:
		var crust: Feature = plates.children[index]
		Crust.rebuild(root, crust, 0.0, 25.0)
		assert_eq(crust.rings.size(), 4, "%s: four bands from 100 Ma at 25 My" % crust.title)
		assert_eq(Crust.chunks(crust), 4, "counted as four chunks")
		assert_eq(crust.crust_line_rings.size(), 5 + 3,
			"with five isochrons and three flowlines over them")


### 0.24.0 to 0.25.0: a hotspot and a crust carry their own time step


# A hotspot or a crust from before has no `time_step` key, which reads as 0,
# and 0 is the timeline's Skip, which is what both followed. Only the version
# moves.
func test_a_0_24_0_file_changes_only_its_version() -> void:
	var leaf := {"type": "Feature", "title": "Hawaii", "feature_type": "hotspot",
		"geometry_kind": "polyline", "rings": [[[19.0, -155.0], [19.0, -154.0]]],
		"hotspot": [19.4, -155.3], "plate": "pacific"}
	var raw := {"version": "0.24.0", "features": {"type": "Group", "title": "Root",
		"children": [leaf]}, "view": {"raster_path": "art/earth.png"}}
	var migrated := Document.migrate(raw)
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	var expected := raw.duplicate(true)
	expected["version"] = "0.26.0"
	assert_eq(migrated, expected, "and nothing else changed")
	assert_eq(raw["version"], "0.24.0", "the data passed in is not changed")
	var feature := Feature.from_json(migrated["features"]["children"][0])
	assert_true(feature.is_hotspot(), "the hotspot comes back")
	assert_eq(feature.time_step, 0.0, "following the timeline's Skip")


### 0.25.0 to 0.26.0: circles and hotspots take no part in coupling


# The shape and the motion every leaf of the fixture below carries, so that a
# step which was meant to touch the spans alone is caught touching either.
const RING := [[0.0, 0.0], [0.0, 10.0], [10.0, 0.0]]
const KEYFRAME := {"time": 100.0, "rotation": [1.0, 2.0, 3.0]}


# A 0.25.0 file that couples a circle and a hotspot every way a file can: each
# one follows something, each one is followed, and each one stands as the second
# parent of a midway span. The span between the two plain features is the one
# that has to survive.
func _couplings_0_25_0() -> Dictionary:
	var span := func(from_: float, to_: float, parent: String, parent_b: String) -> Dictionary:
		var made := {"from": from_, "to": to_, "parent": parent}
		if not parent_b.is_empty():
			made["parent_b"] = parent_b
		return made
	# A circle and a hotspot hold polylines, which is the kind either type takes;
	# a leaf whose kind its type does not allow reads back as the kind's own type.
	var leaf := func(uuid: String, type: String, spans: Array) -> Dictionary:
		return {"type": "Feature", "uuid": uuid, "title": uuid.capitalize(),
			"feature_type": type, "rings": [RING], "keyframes": [KEYFRAME],
			"geometry_kind": "polygon" if type == "polygon" else "polyline",
			"couplings": spans}
	return {"version": "0.25.0", "features": {"type": "Group", "title": "Root", "children": [
		leaf.call("ring", "circle", [span.call(500.0, 0.0, "north", "")]),
		{"type": "Group", "title": "Plumes", "children": [
			leaf.call("hawaii", "hotspot", [span.call(500.0, 0.0, "north", "")])]},
		leaf.call("north", "polygon", []),
		leaf.call("south", "polygon", [
			span.call(500.0, 400.0, "north", ""),
			span.call(400.0, 300.0, "ring", ""),
			span.call(300.0, 200.0, "hawaii", ""),
			span.call(200.0, 100.0, "north", "hawaii"),
			span.call(100.0, 0.0, "north", "ring")]),
	]}}


func test_a_0_25_0_file_drops_every_span_on_a_circle_or_a_hotspot() -> void:
	var raw := _couplings_0_25_0()
	var migrated := Document.migrate(raw)
	assert_eq(migrated["version"], "0.26.0", "at the current version")
	assert_eq(raw["version"], "0.25.0", "the data passed in is not changed")
	var children: Array = migrated["features"]["children"]
	var leaves: Array = [children[0], children[1]["children"][0], children[2], children[3]]
	assert_eq(leaves.map(func(leaf: Dictionary) -> String: return leaf["title"]),
		["Ring", "Hawaii", "North", "South"], "every feature is still there")
	assert_eq(leaves[0]["couplings"], [], "the circle no longer follows anything")
	assert_eq(leaves[1]["couplings"], [], "nor does the hotspot")
	assert_eq(leaves[2]["couplings"], [], "the parent followed nothing to begin with")
	assert_eq(leaves[3]["couplings"], [{"from": 500.0, "to": 400.0, "parent": "north"}],
		"and the only span left follows a plain feature")
	for leaf: Dictionary in leaves:
		assert_eq(leaf["keyframes"], [KEYFRAME], "%s keeps its keyframes" % leaf["title"])
		assert_eq(leaf["rings"], [RING], "%s keeps its rings" % leaf["title"])


# The document the migrated file loads as: the circle and the hotspot are still
# there, and a stretch that followed one of them now follows nothing, with the
# keyframe that held the feature still in place.
func test_a_child_left_without_a_span_keeps_its_keyframes() -> void:
	var root := Feature.from_json(Document.migrate(_couplings_0_25_0())["features"])
	root.is_root = true
	assert_true(root.children[0].is_circle(), "the circle is still in the tree")
	assert_true(root.children[1].children[0].is_hotspot(), "and so is the hotspot")
	var south: Feature = root.children[3]
	assert_eq(south.couplings.size(), 1, "one span is left")
	assert_true(Coupling.span_at(south, 250.0) == null,
		"and the stretch that followed the hotspot follows nothing")
	assert_eq(south.keyframes.size(), 1, "the keyframe is still there")
	assert_close(south.keyframes[0].rotation, Vector3(1, 2, 3), 1e-5,
		"holding the feature where it stood")


# A 0.25.0 file that couples nothing to a circle or a hotspot only moves on.
func test_a_0_25_0_file_without_such_spans_changes_only_its_version() -> void:
	var raw := {"version": "0.25.0", "features": {"type": "Group", "title": "Root", "children": [
		{"type": "Feature", "uuid": "north", "title": "North", "feature_type": "polygon",
			"geometry_kind": "polygon", "rings": [RING], "couplings": []},
		{"type": "Feature", "uuid": "south", "title": "South", "feature_type": "polygon",
			"geometry_kind": "polygon", "rings": [RING],
			"couplings": [{"from": 500.0, "to": 0.0, "parent": "north"}]}]}}
	var expected := raw.duplicate(true)
	expected["version"] = "0.26.0"
	assert_eq(Document.migrate(raw), expected, "nothing but the version changed")
	assert_eq(raw["version"], "0.25.0", "the data passed in is not changed")


# The keys a 0.26.0 file writes are the ones it reads back.
func test_a_0_26_0_file_round_trips() -> void:
	var document := Document.new()
	document.view.planet_color = Color(0.5, 0.25, 0.1)
	document.view.raster_path = "C:/pictures/earth.png"
	document.view.raster_opacity = 0.5
	document.view.raster_visible = false
	document.view.grid_color = Color(0.2, 0.4, 0.6, 1.0)
	document.view.grid_spacing = 20.0
	var circle := Feature.create_feature("Aurora")
	var plate := Feature.create_feature("Plate")
	plate.add_ring(PackedVector2Array([Vector2(-10, -10), Vector2(-10, 10), Vector2(10, 0)]),
		Feature.GeometryKind.POLYGON)
	var hotspot := Feature.create_feature("Hawaii")
	var waiting := Feature.create_feature("Waiting")
	document.root.children.append_array([circle, plate, hotspot, waiting])
	document.set_feature_type(circle, FeatureType.CIRCLE)
	document.set_circle(circle, Vector2(70.0, 20.0), 15.0, 24, true)
	document.set_feature_type(hotspot, FeatureType.HOTSPOT)
	document.set_hotspot(hotspot, Vector2(1.0, 2.0), plate.uuid, 20.0)
	document.set_feature_type(waiting, FeatureType.HOTSPOT)
	var square := Feature.create_feature("Square")
	square.add_ring(PackedVector2Array([Vector2(-10, -10), Vector2(-10, 10), Vector2(10, 10),
		Vector2(10, -10)]), Feature.GeometryKind.POLYGON)
	document.root.children.append(square)
	document.current_time = 100.0
	assert_eq(document.split_feature_along(square, 0,
		PackedVector2Array([Vector2(-11, 0), Vector2(11, 0)]), true, true), "")
	assert_eq(document.save_to_file(SCRATCH), "", "the document is written")
	var file := FileAccess.open(SCRATCH, FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	assert_eq(raw["version"], "0.26.0", "at the current version")
	assert_eq(Document.migrate(raw), raw, "migration leaves a 0.26.0 file as it is")

	var reloaded := Document.new()
	assert_eq(reloaded.load_from_file(SCRATCH), "", "the written file loads back")
	assert_eq(reloaded.view.to_json(), document.view.to_json(), "with the same view block")
	for index in 9:
		assert_eq(reloaded.root.children[index].to_json(), document.root.children[index].to_json(),
			"and the same %s" % document.root.children[index].title)
	assert_eq(reloaded.root.children[2].time_step, 20.0, "the hotspot keeps its own step")
	assert_true(not Hotspot.placed(reloaded.root.children[3]), "the waiting hotspot is not placed")
	assert_true(not (raw["features"]["children"][3] as Dictionary).has("time_step"),
		"a hotspot left on the Skip writes no step")
	assert_true(reloaded.root.children[6].midway, "the ridge is midway")
	for index in [7, 8]:
		assert_eq(reloaded.root.children[index].crust_ridge, reloaded.root.children[6].uuid,
			"one crust per half, each naming the ridge")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func test_version_ordering() -> void:
	assert_true(Document._is_older_than("0.9.0", "0.10.0"), "the minor number is a number")
	assert_true(Document._is_older_than("0.1.0", "0.2.0"))
	assert_true(Document._is_older_than("0.1", "0.2.0"))
	assert_true(not Document._is_older_than("0.2.0", "0.2.0"))
	assert_true(not Document._is_older_than("0.2", "0.2.0"))
	assert_true(not Document._is_older_than("1.0.0", "0.2.0"))
	assert_true(Document._is_older_than("0.3.0", "0.4.0"))


### Helpers


func _migrate_leaf(leaf: Dictionary) -> Dictionary:
	return Document.migrate({"version": "0.1.0", "features": leaf})["features"]


func _migrate_0_3_0(node: Dictionary) -> Dictionary:
	return Document.migrate({"version": "0.3.0", "features": node})["features"]


# The one keyframe a migrated leaf is expected to carry.
func _only_keyframe(leaf: Dictionary) -> Dictionary:
	var list: Array = leaf.get("keyframes", [])
	if list.size() != 1:
		fail("expected one keyframe, found %d" % list.size())
		return {}
	return list[0]


# The edges a triangle soup uses exactly once, as "a|b" with the two vertices
# in a fixed order, so the set does not depend on the direction of an edge.
func _boundary_edges(vertices: Array) -> Array:
	var counts := {}
	for t in range(vertices.size() / 3):
		for e in range(3):
			var key := _edge(vertices[t * 3 + e], vertices[t * 3 + (e + 1) % 3])
			counts[key] = int(counts.get(key, 0)) + 1
	var edges: Array = []
	for key in counts:
		if int(counts[key]) == 1:
			edges.append(key)
	edges.sort()
	return edges


# The edges of the recovered rings, in the same form.
func _ring_edges(rings: Array) -> Array:
	var edges: Array = []
	for ring in rings:
		for i in range(ring.size()):
			edges.append(_edge(ring[i], ring[(i + 1) % ring.size()]))
	edges.sort()
	return edges


func _edge(a: Array, b: Array) -> String:
	var first := "%.6f,%.6f" % [a[0], a[1]]
	var second := "%.6f,%.6f" % [b[0], b[1]]
	return "%s|%s" % [first, second] if first < second else "%s|%s" % [second, first]


func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail("cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		fail("%s is not a JSON object" % path)
		return {}
	return parsed


func _collect_leaves(node: Variant, leaves: Array) -> void:
	if node is not Dictionary:
		return
	if node.get("is_group", node.get("type") == "Group"):
		for child in node.get("children", []):
			_collect_leaves(child, leaves)
		return
	leaves.append(node)
