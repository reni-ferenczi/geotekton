extends RenderedCase

# A resolved line topology is really drawn, in its own colour, along the
# sections it names — and nothing is drawn across the gap between two of them.
#
# The sample is two multipoints on the equator with a topology running along
# both; see Tests/Data/README.md. Their vertices are markers, so the only thing
# drawn between two of them is the boundary, which is what makes the probe say
# which feature painted the pixel rather than which one was painted last.

const SAMPLE := "topology.middle-earth"

# Between two vertices of the western section, and of the eastern one. Both are
# well away from the markers themselves and off the grid.
const ON_WEST_SECTION := Vector2(0.0, -32.5)
const ON_EAST_SECTION := Vector2(0.0, 17.5)

# Between the end of one section and the start of the next, where a topology
# that joined its sections up would draw a line and this one does not.
const IN_THE_GAP := Vector2(0.0, 3.0)


func test_a_resolved_topology_is_drawn_along_its_sections() -> void:
	await load_sample(SAMPLE)
	await look_at_latlon(0.0, 0.0)
	await _check_probe(ON_WEST_SECTION, "green", "on the western section")
	await _check_probe(ON_EAST_SECTION, "green", "on the eastern section")


func test_nothing_is_drawn_across_the_gap_between_two_sections() -> void:
	await load_sample(SAMPLE)
	await look_at_latlon(0.0, 0.0)
	await _check_probe(IN_THE_GAP, "", "between the two sections")


# The markers the sections run along are still drawn in their own colours, so
# the topology is over them rather than instead of them.
func test_the_features_the_sections_run_along_are_still_drawn() -> void:
	await load_sample(SAMPLE)
	await look_at_latlon(0.0, 0.0)
	await _check_probe(Vector2(0.0, -40.0), "red", "the westernmost marker")
	await _check_probe(Vector2(0.0, 40.0), "blue", "the easternmost marker")


# Moving the current time moves the features the sections run along, and the
# topology goes with them: the western section is drawn where the markers have
# been carried to, and no longer where they were.
func test_the_topology_follows_a_section_feature_that_moves() -> void:
	await load_sample(SAMPLE)
	await look_at_latlon(0.0, 0.0)

	var west := _feature("West Points")
	if west == null:
		return
	# A turn about the poles carries a point on the equator along the equator.
	app.document.set_keyframe(west, 0.0, Vector3.ZERO)
	app.document.set_keyframe(west, 100.0, Vector3(-15.0, 0.0, 0.0))
	app.document.set_time(100.0)
	await frames(2)

	await _check_probe(ON_WEST_SECTION + Vector2(0.0, 15.0), "green",
		"where the section has been carried to at 100 Ma")
	await _check_probe(ON_WEST_SECTION, "", "and no longer where it was at the present")
	await _check_probe(ON_EAST_SECTION, "green",
		"while the section whose feature did not move is where it was")

	app.document.set_time(0.0)
	await frames(2)


func _feature(title: String) -> Feature:
	var stack: Array[Feature] = [app.document.root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if node.title == title:
			return node
		stack.append_array(node.children)
	fail("the sample holds no feature called %s" % title)
	return null


func _check_probe(at: Vector2, expected: String, what: String) -> void:
	var screen: Variant = view().latlon_to_screen(at.x, at.y)
	if screen == null:
		fail("%s (%s) is not on the visible hemisphere" % [what, at])
		return
	var color := await probe(screen)
	var found := dominant_channel(color)
	if expected.is_empty():
		assert_true(found.is_empty(),
			"%s (%s) shows the Earth, not %s: %s" % [what, at, found, color])
	else:
		assert_eq(found, expected, "%s (%s) is %s: %s" % [what, at, expected, color])
