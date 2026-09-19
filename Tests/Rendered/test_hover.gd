extends RenderedCase

# The craton under the pointer stops being drawn highlighted once the pointer
# leaves the planet view. Inside the window the background behind the globe
# ends the hover on its own; out of the window, or over another one, only the
# view learns that the pointer is gone, through mouse_exited.
#
# Both ends of the hover are driven through the view's signals rather than by
# injected motion. The pointer of whoever runs the tests sits over the window
# and sends motion of its own, which lands on the background behind the globe
# and ends the hover mid test.

# Where Green Moved sits at NOW, the probe point the README documents.
const GREEN_LAT := -3.0
const GREEN_LON := -60.0

# The two times the feature is keyframed at.
const NOW := 0.0
const THEN := 200.0


func test_the_pointer_leaving_the_view_ends_the_hover() -> void:
	await load_sample("two_cratons.geotekt")
	view().craton_hovered.emit(-3.0, -60.0)
	assert_eq(_hovered_title(), "Green Moved", "the pointer on a craton hovers it")

	view().mouse_exited.emit()
	assert_eq(_hovered_title(), "", "the hover ends with the pointer off the view")


# The pointer can also stop being over a feature without moving, because the
# feature moved instead: the current time changes and the geometry is resolved
# somewhere else. Nothing reports that, so the application works the hover out
# again whenever the features move, from where the pointer last was.
#
# Nothing is awaited between the hover and the last assertion. Emitting the
# signal and setting the time both land synchronously, and an await would let
# the real pointer of whoever runs the tests send motion of its own and end the
# hover mid test.
func test_the_time_moving_a_feature_off_the_pointer_ends_the_hover() -> void:
	await load_sample("two_cratons.geotekt")
	var green := _feature("Green Moved")
	assert_true(green != null, "the sample must contain the Green Moved feature")
	if green == null:
		return

	# Two keyframes 120 degrees of longitude apart, so the older one takes the
	# feature out from under the point the younger one puts it at.
	var keyframes: Array[Keyframe] = [
		Keyframe.create(NOW, Vector3(60, 0, 0)),
		Keyframe.create(THEN, Vector3(-60, 0, 0)),
	]
	green.keyframes = keyframes
	# A document opens at the oldest age the animation covers, and the probe
	# point the README documents is where the feature stands at NOW.
	app.document.set_time(NOW)
	app.refresh_geometry()
	await frames(2)

	view().craton_hovered.emit(GREEN_LAT, GREEN_LON)
	assert_eq(_hovered_title(), "Green Moved", "the pointer on the craton hovers it")

	app.document.set_time(THEN)
	assert_eq(_hovered_title(), "", "the time carrying it away ends the hover")

	app.document.set_time(NOW)
	assert_eq(_hovered_title(), "Green Moved", "and bringing it back raises it again")


func _hovered_title() -> String:
	return "" if app.hovered_feature == null else app.hovered_feature.title


func _feature(title: String) -> Feature:
	for node in app.features.root.children[0].children:
		if node.title == title:
			return node
	return null
