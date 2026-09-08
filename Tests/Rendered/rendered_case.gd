class_name RenderedCase
extends TestCase

# Base class of the rendered tests. They run against the real application window,
# so they load sample files, read window pixels and inject mouse clicks.
# Helper names must not begin with test_, the runner would call them as tests.

const DATA_DIR := "res://Tests/Data"

# Last injected mouse position, used to fill in the relative motion.
var mouse: Vector2 = Vector2.ZERO


# The planet view, typed, because TestCase.app cannot be.
func view() -> PlanetView:
	return app.planet_view


# Turn the globe so a lat/lon faces the camera, and let Planet._process apply it.
# Points near the limb are dark, anti-aliased against the background and hard to
# hit with the physics picking, so the tests bring their probe points to the front.
func look_at_latlon(lat: float, lon: float) -> void:
	view().planet.lat = lat
	view().planet.lon = lon
	await frames(2)


# Load a file from Tests/Data into the running application.
func load_sample(file_name: String) -> void:
	var path := ProjectSettings.globalize_path("%s/%s" % [DATA_DIR, file_name])
	app.document.load_from_file(path)
	app.refresh_geometry()
	await frames(2)


# Wait for a number of process frames.
func frames(count: int) -> void:
	for i in count:
		await tree.process_frame


# Colour of a window pixel, read once the frame is on screen.
func probe(screen: Vector2) -> Color:
	await RenderingServer.frame_post_draw
	var image: Image = app.get_viewport().get_texture().get_image()
	return image.get_pixel(int(screen.x), int(screen.y))


# Left click at a window pixel, the recipe AutomationPort uses.
func click(screen: Vector2) -> void:
	# Keep the injected motion discrete instead of merging it per frame.
	Input.use_accumulated_input = false

	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	motion.relative = screen - mouse
	mouse = screen
	Input.parse_input_event(motion)
	await _physics_frames(2)

	_button(true)
	await _physics_frames(2)
	_button(false)
	await _physics_frames(2)
	# Selection on click is deferred, so give it process frames to land.
	await frames(2)


# How far the other two channels may come up before a colour stops being
# dominated by one of them. The channels are compared against each other rather
# than against a fixed level, so a feature the hover highlight has brightened is
# still its own colour. Matches DOMINANT_RATIO in Tests/session.py.
const DOMINANT_RATIO := 0.7


# Name of the channel that dominates a probed colour, "" when none does.
# The craton material is lit, so the pure colours come back tinted.
func dominant_channel(color: Color) -> String:
	if color.r > 0.5 and maxf(color.g, color.b) < color.r * DOMINANT_RATIO:
		return "red"
	if color.g > 0.5 and maxf(color.r, color.b) < color.g * DOMINANT_RATIO:
		return "green"
	if color.b > 0.5 and maxf(color.r, color.g) < color.b * DOMINANT_RATIO:
		return "blue"
	return ""


func _physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = mouse
	event.global_position = mouse
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)
