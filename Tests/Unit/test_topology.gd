extends TestCase

# Line topologies: a feature whose geometry is a list of sections borrowed from
# other features, resolved at a time. What is checked here is the resolution
# itself and what a file makes of it, without a window.
#
# The fixture is two polylines side by side on the equator, one running east
# from the prime meridian and one running east from 40 degrees, and a topology
# naming a stretch of each. The two are far enough apart that the gap between
# them cannot be mistaken for a rounding error.

# A PackedVector2Array is not a constant expression, so the vertices are held as
# plain arrays and packed where they are used.
const WEST := [Vector2(0, 0), Vector2(0, 10), Vector2(0, 20), Vector2(0, 30)]
const EAST := [Vector2(0, 60), Vector2(0, 70), Vector2(0, 80)]


func west_ring() -> PackedVector2Array:
	return PackedVector2Array(WEST)


func east_ring() -> PackedVector2Array:
	return PackedVector2Array(EAST)


# Root > Lines > West, East, and Boundary beside them.
func _build_tree() -> Feature:
	var root := Feature.create_group("Planet")
	root.is_root = true

	var lines := Feature.create_group("Lines")
	root.children.append(lines)

	var west := Feature.create_feature("West")
	west.add_ring(west_ring(), Feature.GeometryKind.POLYLINE)
	lines.children.append(west)

	var east := Feature.create_feature("East")
	east.add_ring(east_ring(), Feature.GeometryKind.POLYLINE)
	lines.children.append(east)

	var boundary := Feature.create_feature("Boundary")
	boundary.feature_type = "topology"
	boundary.geometry_kind = Feature.GeometryKind.TOPOLOGY
	boundary.sections = [
		TopologySection.create(west.uuid, 0, 1, 3),
		TopologySection.create(east.uuid, 0, 0, 2),
	]
	root.children.append(boundary)
	return root


func _boundary(root: Feature) -> Feature:
	return root.get_node_by_pnid(root.children[1].pnid)


func test_a_topology_resolves_to_the_runs_its_sections_name() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	var resolved := Topology.resolve(root, boundary, 0.0)

	assert_eq(resolved.size(), 2, "one entry per section")
	if resolved.size() != 2:
		return
	assert_eq(resolved[0]["problem"], "", "the first section resolves")
	assert_eq(resolved[1]["problem"], "", "the second section resolves")
	assert_eq(resolved[0]["vertices"], west_ring().slice(1, 4),
		"the first section is the range it names, not the whole part")
	assert_eq(resolved[1]["vertices"], east_ring(),
		"the second section is the whole of the other feature's part")


# The two ends of neighbouring sections are not joined: a line topology is the
# stretches it names, and a segment across the gap is one no feature drew.
func test_each_section_becomes_a_part_of_its_own() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	Topology.rebuild(root, boundary, 0.0)

	assert_eq(boundary.rings.size(), 2, "one part per section")
	if boundary.rings.size() != 2:
		return
	assert_eq(boundary.rings[0].size(), 3, "the first part holds the three vertices named")
	assert_eq(boundary.rings[1].size(), 3, "and the second the other three")
	assert_close(boundary.rings[0][2].y, 30.0, 1e-4, "the first part ends at 30 east")
	assert_close(boundary.rings[1][0].y, 60.0, 1e-4, "and the second starts at 60 east")


func test_a_reversed_section_runs_the_other_way() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	boundary.sections[0].reversed = true
	var resolved := Topology.resolve(root, boundary, 0.0)

	var forward := west_ring().slice(1, 4)
	forward.reverse()
	assert_eq(resolved[0]["vertices"], forward,
		"a reversed section holds the same vertices back to front")
	assert_eq(resolved[1]["vertices"], east_ring(), "and the other section is left alone")


# A topology follows the features it runs along, so moving one of them at a
# later time moves the part that came from it and leaves the other where it was.
func test_a_topology_follows_a_section_feature_that_moves() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	var west: Feature = root.children[0].children[0]
	Keyframe.upsert(west.keyframes, 0.0, Vector3.ZERO)
	# A turn about the poles carries a point on the equator along the equator.
	Keyframe.upsert(west.keyframes, 100.0, Vector3(-25.0, 0.0, 0.0))

	var now := Topology.resolve(root, boundary, 0.0)
	var later := Topology.resolve(root, boundary, 100.0)
	assert_close((now[0]["vertices"] as PackedVector2Array)[0], Vector2(0, 10), 1e-4,
		"at the present the first section is where its feature was drawn")
	assert_close((later[0]["vertices"] as PackedVector2Array)[0], Vector2(0, 35), 1e-4,
		"at 100 Ma it has gone with the feature it runs along")
	assert_eq(later[1]["vertices"], east_ring(),
		"and the section of the feature that did not move is unchanged")


func test_a_section_of_a_feature_that_is_not_there_yet_is_not_resolved() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	var east: Feature = root.children[0].children[1]
	east.time_range = Vector2i(0, 50)

	var resolved := Topology.resolve(root, boundary, 100.0)
	assert_eq(resolved[0]["problem"], "", "the section whose feature is there resolves")
	assert_true(not str(resolved[1]["problem"]).is_empty(),
		"the section whose feature is not there at that time says so")
	assert_eq(resolved[1]["title"], "East", "and still names the feature it meant")


### Broken sections


func test_a_section_whose_feature_is_gone_is_broken_rather_than_dropped() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	var lines: Feature = root.children[0]
	lines.children.remove_at(0)

	var resolved := Topology.resolve(root, boundary, 0.0)
	assert_eq(resolved.size(), 2, "the broken section is still one of them")
	assert_true(not str(resolved[0]["problem"]).is_empty(), "and says why it resolves to nothing")
	assert_eq((resolved[0]["vertices"] as PackedVector2Array).size(), 0,
		"a broken section contributes no vertices")

	Topology.rebuild(root, boundary, 0.0)
	assert_eq(boundary.rings.size(), 1, "so the topology draws the one section that is left")
	assert_true(boundary.has_geometry(),
		"and still holds geometry, because it still names two sections")


func test_a_topology_naming_nothing_that_exists_still_loads_and_saves() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	root.children[0].children.clear()

	var text := JSON.stringify(boundary.to_json())
	var restored := Feature.from_json(JSON.parse_string(text))
	assert_eq(restored.sections.size(), 2, "both dangling sections survive the file")
	assert_eq(restored.sections[0].feature_uuid, boundary.sections[0].feature_uuid,
		"naming the same feature as before, so an undo can bring it back")
	Topology.rebuild(root, restored, 0.0)
	assert_eq(restored.rings.size(), 0, "nothing is drawn while nothing can be found")


func test_a_topology_cannot_run_along_itself_or_another_topology() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	boundary.sections = [TopologySection.create(boundary.uuid, 0, 0, 1)]
	assert_true(not str(Topology.resolve(root, boundary, 0.0)[0]["problem"]).is_empty(),
		"a section naming its own topology is broken")

	var other := Feature.create_feature("Other")
	other.geometry_kind = Feature.GeometryKind.TOPOLOGY
	root.children.append(other)
	boundary.sections = [TopologySection.create(other.uuid, 0, 0, 1)]
	assert_true(not str(Topology.resolve(root, boundary, 0.0)[0]["problem"]).is_empty(),
		"and so is one naming another topology")


func test_a_range_naming_fewer_than_two_vertices_is_broken() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	boundary.sections[0].to_index = boundary.sections[0].from_index
	assert_true(not str(Topology.resolve(root, boundary, 0.0)[0]["problem"]).is_empty(),
		"a single vertex is not a piece of a line")


# A file written by hand can name vertices a feature does not have; the range is
# brought back into the part rather than the whole section being thrown away.
func test_a_range_beyond_the_part_is_brought_back_into_it() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	boundary.sections[0] = TopologySection.create(boundary.sections[0].feature_uuid, 0, -5, 99)
	var resolved := Topology.resolve(root, boundary, 0.0)
	assert_eq(resolved[0]["problem"], "", "the section still resolves")
	assert_eq(resolved[0]["vertices"], west_ring(), "as the whole part it overran")


### The file and the tree


func test_the_sections_survive_the_round_trip() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	boundary.sections[1].reversed = true
	var restored := Feature.from_json(JSON.parse_string(JSON.stringify(boundary.to_json())))

	assert_eq(restored.geometry_kind, Feature.GeometryKind.TOPOLOGY, "it is still a topology")
	assert_eq(restored.sections.size(), 2, "with both its sections")
	for i in range(mini(restored.sections.size(), boundary.sections.size())):
		var was: TopologySection = boundary.sections[i]
		var now: TopologySection = restored.sections[i]
		assert_eq(now.feature_uuid, was.feature_uuid, "section %d names the same feature" % i)
		assert_eq(now.part, was.part, "section %d keeps its part" % i)
		assert_eq(now.from_index, was.from_index, "section %d keeps where it starts" % i)
		assert_eq(now.to_index, was.to_index, "section %d keeps where it ends" % i)
		assert_eq(now.reversed, was.reversed, "section %d keeps its direction" % i)


func test_the_resolved_rings_are_not_written_to_the_file() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	Topology.rebuild(root, boundary, 0.0)
	assert_eq(boundary.rings.size(), 2, "the topology has rings to draw")

	var data: Dictionary = boundary.to_json()
	assert_true(not data.has("rings"),
		"but they are resolved from the sections, so the file does not carry them")
	assert_true(data.has("sections"), "the sections are what the file carries")


func test_a_clone_carries_the_sections_and_a_duplicate_keeps_them() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	var cloned := boundary.clone()
	cloned.sections[0].reversed = true
	assert_eq(boundary.sections[0].reversed, false,
		"a clone holds sections of its own rather than the same ones")

	# A duplicated topology goes on naming the same features: it is a copy of
	# the boundary, not a copy of what the boundary runs along.
	var copy := boundary.duplicate()
	assert_eq(copy.sections[0].feature_uuid, boundary.sections[0].feature_uuid,
		"a duplicate names the same features")
	assert_true(copy.uuid != boundary.uuid, "under a uuid of its own")


func test_a_topology_is_drawn_and_measured_as_a_polyline() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	Topology.rebuild(root, boundary, 0.0)
	assert_eq(boundary.drawn_as(), Feature.GeometryKind.POLYLINE,
		"a topology is drawn as the line it resolves to")
	assert_eq(boundary.triangles.size(), 0, "and is not filled")

	# Two runs of 30 degrees on the equator, measured along and not closed.
	var length := Measure.geometry_length(boundary, 1.0)
	assert_close(rad_to_deg(length), 20.0 + 20.0, 1e-3,
		"its length is the length of its parts, without the gap between them")


# A topology holds geometry but none of it is its own, which is what the Vertex
# tool, the Split button and the coordinate table all go by: there is nothing
# there to drag, insert, delete or cut in two.
func test_a_topology_holds_geometry_but_no_vertices_of_its_own() -> void:
	var root := _build_tree()
	var boundary := _boundary(root)
	Topology.rebuild(root, boundary, 0.0)
	assert_true(boundary.has_geometry(), "a topology naming sections holds geometry")
	assert_true(not boundary.has_own_vertices(), "but none of the vertices are its own")

	var west: Feature = root.children[0].children[0]
	assert_true(west.has_own_vertices(), "while a drawn feature's vertices are")

	var document := Document.new()
	document.root = root
	assert_true(not document.split_feature(boundary, 0, 1).is_empty(),
		"so a topology is refused a split")


func test_the_tree_finds_a_node_by_uuid() -> void:
	var root := _build_tree()
	var west: Feature = root.children[0].children[0]
	assert_eq(root.get_node_by_uuid(west.uuid), west, "a uuid reaches the node it names")
	assert_eq(root.get_node_by_uuid("not-a-uuid"), null, "and an unknown one reaches nothing")
	assert_eq(root.get_node_by_uuid(""), null, "as does an empty one")


func test_the_tree_says_whether_it_holds_a_topology() -> void:
	var root := _build_tree()
	assert_true(Topology.holds_any(root), "the fixture holds one")
	root.children.remove_at(1)
	assert_true(not Topology.holds_any(root), "and does not once it is taken out")
