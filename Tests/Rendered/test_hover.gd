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


func test_the_pointer_leaving_the_view_ends_the_hover() -> void:
	await load_sample("two_cratons.middle-earth")
	view().craton_hovered.emit(-3.0, -60.0)
	assert_eq(_hovered_title(), "Green Moved", "the pointer on a craton hovers it")

	view().mouse_exited.emit()
	assert_eq(_hovered_title(), "", "the hover ends with the pointer off the view")


func _hovered_title() -> String:
	return "" if app.hovered_feature == null else app.hovered_feature.title
