extends PanelContainer
class_name Timeline

# The time control under the globe: where the document is being looked at, and
# the playback that runs it through an animation. Time is an age in millions of
# years before present, so the slider runs from the oldest time on the left to 0
# on the right and an animation normally plays from left to right. See
# Docs/Time.md.
#
# The document owns the current time. Everything here either asks the document
# to move it or follows it once it has moved, so a time set from a script or
# from the Properties panel reaches the slider by the same path a drag does.

# The Configure button was pressed: the application opens the animation dialog.
signal configure_requested()

# The animation range has changed, so the slider spans something else. The
# kinematics graphs are drawn over the same span and follow it.
signal animation_changed()

# How tall the strip of keyframe markers under the slider is.
const MARKER_HEIGHT := 10

# The keyframe markers of the selected node, and the current time among them.
const MARKER_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const CURSOR_COLOR := Color(1.0, 1.0, 1.0, 0.6)

var document: Document

# How playback walks the timeline. The defaults stand until attach() reads the
# config file, which cannot happen before the application has decided whether
# this run is allowed to read one at all.
var animation := AnimationSettings.new()

var slider: HSlider
var markers: Control
var time_spin: SpinBox
var skip_spin: SpinBox
var play_button: Button
var pause_button: Button
var reset_button: Button
var older_button: Button
var younger_button: Button
var configure_button: Button

var playing: bool = false

# The node whose keyframes are marked under the slider, null for none.
var marked: Feature = null

# True while the widgets are being filled from the document, so what they emit
# on the way is not mistaken for someone moving them.
var _filling: bool = false


func _ready() -> void:
	_build()
	set_process(false)
	_apply_animation()
	_update_buttons()


func attach(document_: Document) -> void:
	document = document_
	document.time_changed.connect(_show_time)
	animation = AnimationSettings.load_settings()
	skip_spin.set_value_no_signal(Config.get_skip_increment())
	_apply_animation()


### Layout


func _build() -> void:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 8)
	add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Content"
	margin.add_child(box)

	var controls := HBoxContainer.new()
	controls.name = "Controls"
	box.add_child(controls)

	older_button = _control_button(controls, "Older", "<", "One skip towards the older end (Page Up)")
	older_button.pressed.connect(step.bind(true))
	play_button = _control_button(controls, "Play", "Play", "Run the animation")
	play_button.pressed.connect(play)
	pause_button = _control_button(controls, "Pause", "Pause", "Stop where it is")
	pause_button.pressed.connect(pause)
	younger_button = _control_button(controls, "Younger", ">", "One skip towards the younger end (Page Down)")
	younger_button.pressed.connect(step.bind(false))

	skip_spin = SpinBox.new()
	skip_spin.name = "Skip"
	skip_spin.min_value = Config.MIN_SKIP
	skip_spin.max_value = Document.MAX_TIME
	skip_spin.step = 0.0001
	skip_spin.value = Config.DEFAULT_SKIP
	skip_spin.suffix = "My"
	skip_spin.custom_minimum_size = Vector2(100, 0)
	skip_spin.tooltip_text = "How far the < and > buttons jump, in millions of years"
	skip_spin.value_changed.connect(_on_skip_changed)
	controls.add_child(skip_spin)

	reset_button = _control_button(controls, "Reset", "Reset", "Back to the start of the animation")
	reset_button.pressed.connect(reset)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)

	time_spin = SpinBox.new()
	time_spin.name = "Time"
	time_spin.min_value = 0.0
	time_spin.max_value = Document.MAX_TIME
	time_spin.step = 0.0001
	time_spin.custom_minimum_size = Vector2(110, 0)
	time_spin.tooltip_text = "The age everything is drawn at, in millions of years"
	time_spin.value_changed.connect(_on_time_typed)
	controls.add_child(time_spin)

	var unit := Label.new()
	unit.text = "Ma"
	controls.add_child(unit)

	configure_button = _control_button(
		controls, "Configure", "Configure...", "Set the range, the step and the speed")
	configure_button.pressed.connect(func() -> void: configure_requested.emit())

	slider = HSlider.new()
	slider.name = "Slider"
	slider.custom_minimum_size = Vector2(150, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.step = 1.0
	slider.ticks_on_borders = true
	slider.value_changed.connect(_on_slider_moved)
	box.add_child(slider)

	markers = Control.new()
	markers.name = "Markers"
	markers.custom_minimum_size = Vector2(0, MARKER_HEIGHT)
	markers.tooltip_text = "The keyframes of the selected feature"
	markers.draw.connect(_draw_markers)
	markers.resized.connect(markers.queue_redraw)
	box.add_child(markers)


func _control_button(parent: Control, node_name: String, text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tooltip
	parent.add_child(button)
	return button


### The slider and the typed time


# The oldest and the youngest time the slider spans: the two ends of the
# animation, whichever way round they were configured.
func oldest() -> float:
	return maxf(animation.start, animation.end)


func youngest() -> float:
	return minf(animation.start, animation.end)


# Lay the slider out for the animation range. The value it holds is the negative
# of the time, which is what puts the oldest end on the left: a slider always
# grows to the right and an age grows into the past.
func _apply_animation() -> void:
	_filling = true
	slider.min_value = -oldest()
	slider.max_value = -youngest()
	slider.tick_count = 11
	_filling = false
	_show_time()
	markers.queue_redraw()
	animation_changed.emit()


func _show_time() -> void:
	if document == null:
		return
	_filling = true
	slider.set_value_no_signal(-document.current_time)
	time_spin.set_value_no_signal(document.current_time)
	_filling = false
	markers.queue_redraw()


func _on_slider_moved(value: float) -> void:
	if _filling or document == null:
		return
	# Taking hold of the slider is taking over from the animation.
	pause()
	document.set_time(-value)


func _on_time_typed(value: float) -> void:
	if _filling or document == null:
		return
	pause()
	document.set_time(value)


### Playback


func play() -> void:
	if document == null:
		return
	var problem := animation.problem()
	if not problem.is_empty():
		return
	# Playing again from the end is playing from the start; anywhere else
	# carries on from where the slider was left.
	if animation.reached_end(document.current_time):
		document.set_time(animation.start)
	playing = true
	set_process(true)
	_update_buttons()


func pause() -> void:
	playing = false
	set_process(false)
	_update_buttons()


# Back to the start of the animation, stopped.
func reset() -> void:
	pause()
	if document != null:
		document.set_time(animation.start)


# One skip towards the older or the younger end, by the number beside the
# buttons, kept inside the animation range.
func step(towards_older: bool) -> void:
	if document == null:
		return
	pause()
	var delta := skip() * (1.0 if towards_older else -1.0)
	document.set_time(clampf(document.current_time + delta, youngest(), oldest()))


func skip() -> float:
	return skip_spin.value


func _on_skip_changed(value: float) -> void:
	Config.set_skip_increment(value)


# Move the time on by however long the last frame took. Nothing is accumulated
# beyond the time itself: the frame after a slow one moves further, and the
# animation reaches the end at the same moment on any machine.
func _process(delta: float) -> void:
	if not playing:
		return
	document.set_time(animation.advance(document.current_time, delta))
	if animation.reached_end(document.current_time):
		if animation.loop:
			document.set_time(animation.start)
		else:
			pause()


func _update_buttons() -> void:
	play_button.disabled = playing
	pause_button.disabled = not playing


### Keyframe markers


# Mark the keyframes of this node under the slider. Called with whatever the
# feature tree has selected, and again whenever its keyframes change.
func show_keyframes(node: Feature) -> void:
	marked = node
	markers.queue_redraw()


func _draw_markers() -> void:
	var span := oldest() - youngest()
	if span <= 0.0 or markers.size.x <= 0.0:
		return

	if document != null:
		var x := _marker_x(document.current_time, span)
		markers.draw_line(Vector2(x, 0.0), Vector2(x, markers.size.y), CURSOR_COLOR, 1.0)

	if marked == null:
		return
	for keyframe in marked.keyframes:
		var x := _marker_x(keyframe.time, span)
		markers.draw_line(Vector2(x, 0.0), Vector2(x, markers.size.y), MARKER_COLOR, 2.0)


# Where a time sits across the strip, matching the slider above it: the oldest
# end on the left, the youngest on the right.
func _marker_x(time: float, span: float) -> float:
	return clampf((oldest() - time) / span, 0.0, 1.0) * markers.size.x


### The animation settings


# Take new settings, remember them and lay the slider out for them again.
func set_animation(settings: AnimationSettings) -> void:
	animation = settings
	animation.save_settings()
	_apply_animation()
	if document != null:
		document.set_time(clampf(document.current_time, youngest(), oldest()))


### The automation port


func to_json() -> Dictionary:
	return {
		"time": document.current_time if document != null else 0.0,
		"slider": slider.value,
		"slider_range": [slider.min_value, slider.max_value],
		"typed": time_spin.value,
		"playing": playing,
		"skip": skip(),
		"markers": _markers_to_json(),
		"animation": animation.to_json(),
	}


func _markers_to_json() -> Array:
	var times: Array = []
	if marked != null:
		for keyframe in marked.keyframes:
			times.append(keyframe.time)
	return times


# Press one of the buttons the way a person would, for the scripted session.
func press(button_name: String) -> String:
	var button: Button = {
		"Play": play_button,
		"Pause": pause_button,
		"Reset": reset_button,
		"Older": older_button,
		"Younger": younger_button,
		"Configure": configure_button,
	}.get(button_name)
	if button == null:
		return "no timeline button called %s" % button_name
	if button.disabled:
		return "the %s button is disabled" % button_name
	button.pressed.emit()
	return ""
