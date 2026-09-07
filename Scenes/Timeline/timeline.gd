extends PanelContainer
class_name Timeline

# The time control under the globe: where the document is being looked at, and
# the playback that walks it through an animation. Time is an age in millions of
# years before present, so the slider runs from the oldest time on the left to 0
# on the right and an animation normally plays from left to right. See
# Docs/Time.md.
#
# The document owns the current time. Everything here either asks the document
# to move it or follows it once it has moved, so a time set from a script or
# from the Properties panel reaches the slider by the same path a drag does.

# The Configure button was pressed: the application opens the animation dialog.
signal configure_requested()

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
var play_button: Button
var pause_button: Button
var reset_button: Button
var older_button: Button
var younger_button: Button
var configure_button: Button

# The times playback steps through, and where in them it is. Built when play is
# pressed, so a change to the settings takes effect at the next play.
var frames := PackedFloat64Array()
var frame_index: int = -1
var seconds_on_this_frame: float = 0.0
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

	older_button = _control_button(controls, "Older", "<", "One step towards the older end")
	older_button.pressed.connect(step.bind(true))
	play_button = _control_button(controls, "Play", "Play", "Run the animation")
	play_button.pressed.connect(play)
	pause_button = _control_button(controls, "Pause", "Pause", "Stop where it is")
	pause_button.pressed.connect(pause)
	younger_button = _control_button(controls, "Younger", ">", "One step towards the younger end")
	younger_button.pressed.connect(step.bind(false))
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
	slider.name = "TimestampSlider"
	slider.unique_name_in_owner = true
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
	frames = animation.times()
	frame_index = _frame_at(document.current_time)
	seconds_on_this_frame = 0.0
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
	frame_index = -1
	if document != null:
		document.set_time(animation.start)


# One step of the animation towards the older or the younger end.
func step(towards_older: bool) -> void:
	if document == null:
		return
	pause()
	var delta := absf(animation.increment) * (1.0 if towards_older else -1.0)
	document.set_time(clampf(document.current_time + delta, youngest(), oldest()))


func _process(delta: float) -> void:
	if not playing:
		return
	seconds_on_this_frame += delta
	var per_frame := animation.frame_seconds()
	# A slow machine catches up rather than falling behind, but the times
	# themselves come from the list, so no frame time is ever accumulated.
	while seconds_on_this_frame >= per_frame:
		seconds_on_this_frame -= per_frame
		if not _advance():
			return


# Show the next frame. False once the animation has run out and does not loop.
func _advance() -> bool:
	frame_index += 1
	if frame_index >= frames.size():
		if not animation.loop:
			frame_index = frames.size() - 1
			pause()
			return false
		frame_index = 0
	document.set_time(frames[frame_index])
	return true


# Which frame a time belongs to: the last one at or before it in playing order,
# so pressing play carries on from where the slider was left rather than
# jumping back to the start.
func _frame_at(time: float) -> int:
	for i in range(frames.size() - 1, -1, -1):
		var reached := frames[i] >= time if animation.start > animation.end else frames[i] <= time
		if reached:
			return i
	return -1


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
		"frame": frame_index,
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
