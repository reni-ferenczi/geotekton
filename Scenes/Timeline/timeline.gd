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

# The Skip box took a new value, which a hotspot's track is sampled at.
signal skip_changed()

# The animation range has changed, so the slider spans something else. The
# kinematics graphs are drawn over the same span and follow it.
signal animation_changed()

# How tall the strip of keyframe markers under the slider is, and how far
# either side of a mark a click still lands on it, in pixels.
const MARKER_HEIGHT := 10
const MARKER_PICK_PIXELS := 4.0

# What the strip says when the pointer is not on a mark.
const MARKERS_TOOLTIP := "The keyframes of the selected feature; click one to go there"

# The keyframe markers of the selected node, and the current time among them.
const MARKER_COLOR := Color(1.0, 0.85, 0.2, 1.0)

# The spans over which the selected feature follows another, a bar along the
# bottom of the strip under the keyframe marks in the parent's color, opaque
# whatever the parent's opacity. A span midway between two parents takes the
# first one's color. A span whose parent cannot be followed is dashed, and
# drawn in COUPLING_COLOR when there is no parent left to take a color from.
# COUPLING_PICK_PIXELS is how far above the bar the pointer still counts as on
# it.
const COUPLING_HEIGHT := 3.0
const COUPLING_DASH := 6.0
const COUPLING_PICK_PIXELS := 3.0
const COUPLING_COLOR := Color(0.35, 0.75, 1.0, 1.0)

# Where a ridge of the selected feature appears, a small red dot at the top of
# the strip at the ridge's split age, over any keyframe mark there. Shown while
# show_ridges is on (View > Ridge markers).
const RIDGE_COLOR := Color(0.95, 0.15, 0.15, 1.0)
const RIDGE_DOT_RADIUS := 2.5

# How close to a keyframe's time the current time counts as being on it, so
# that a jump from a keyframe goes to the next one rather than back to itself.
const TIME_EPSILON := 1e-9
const CURSOR_COLOR := Color(1.0, 1.0, 1.0, 0.6)

# The step of the typed time: what it is written to, and while the animation
# plays, whole Ma (GP-0145).
const TIME_STEP := 0.0001
const PLAYING_TIME_STEP := 1.0

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
var older_keyframe_button: Button
var younger_keyframe_button: Button
var configure_button: Button

var playing: bool = false

# The node whose keyframes are marked under the slider, null for none.
var marked: Feature = null

# The ridges marked with a dot for the marked node, found when it is marked.
var _ridges: Array[Feature] = []

# Whether the ridge dots are drawn.
var show_ridges: bool = true:
	set(value):
		show_ridges = value
		if markers != null:
			markers.queue_redraw()

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

	older_keyframe_button = _control_button(
		controls, "OlderKeyframe", "<<", "The next keyframe towards the older end (Ctrl+Page Up)")
	older_keyframe_button.pressed.connect(jump_keyframe.bind(true))
	older_button = _control_button(controls, "Older", "<", "One skip towards the older end (Page Up)")
	older_button.pressed.connect(step.bind(true))
	play_button = _control_button(controls, "Play", "Play", "Run the animation (Space)")
	play_button.pressed.connect(play)
	pause_button = _control_button(controls, "Pause", "Pause", "Stop where it is (Space)")
	pause_button.pressed.connect(pause)
	younger_button = _control_button(controls, "Younger", ">", "One skip towards the younger end (Page Down)")
	younger_button.pressed.connect(step.bind(false))
	younger_keyframe_button = _control_button(
		controls, "YoungerKeyframe", ">>", "The next keyframe towards the younger end (Ctrl+Page Down)")
	younger_keyframe_button.pressed.connect(jump_keyframe.bind(false))

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
	time_spin.step = TIME_STEP
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
	markers.tooltip_text = MARKERS_TOOLTIP
	markers.draw.connect(_draw_markers)
	markers.resized.connect(markers.queue_redraw)
	markers.gui_input.connect(_on_markers_input)
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


# While playing, the number beside the slider steps in whole Ma, which is also
# how it is written: the decimals change every frame and only flash (GP-0145).
# Pausing shows the exact time again.
func _show_time() -> void:
	if document == null:
		return
	_filling = true
	slider.set_value_no_signal(-document.current_time)
	time_spin.step = PLAYING_TIME_STEP if playing else TIME_STEP
	time_spin.set_value_no_signal(document.current_time)
	_filling = false
	markers.queue_redraw()
	_update_buttons()


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
	_show_time()
	_update_buttons()


# What the Space key does: stop if it is running, start if it is not.
func toggle() -> void:
	if playing:
		pause()
	else:
		play()


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
	skip_changed.emit()


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
	older_keyframe_button.disabled = _keyframe_beyond(true) == null
	younger_keyframe_button.disabled = _keyframe_beyond(false) == null


### Jumping between keyframes


# The nearest keyframe of the marked node beyond the current time in the given
# direction, or null when there is none that way.
func _keyframe_beyond(towards_older: bool) -> Keyframe:
	if marked == null or document == null:
		return null
	var found: Keyframe = null
	for keyframe in marked.keyframes:
		var beyond := keyframe.time > document.current_time + TIME_EPSILON if towards_older \
			else keyframe.time < document.current_time - TIME_EPSILON
		if not beyond:
			continue
		if found == null or absf(keyframe.time - document.current_time) \
				< absf(found.time - document.current_time):
			found = keyframe
	return found


# Land on the next keyframe of the marked node in that direction, exactly.
func jump_keyframe(towards_older: bool) -> void:
	var keyframe := _keyframe_beyond(towards_older)
	if keyframe == null:
		return
	pause()
	document.set_time(keyframe.time)


# A click on a mark lands the time on that keyframe exactly, which is what the
# marks are for; typing the time would need every digit of it.
func _on_markers_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var under := _keyframe_at_x(event.position.x)
		var ridge := _ridge_at(event.position)
		var coupling := _coupling_at(event.position)
		if ridge != null:
			markers.tooltip_text = _ridge_tooltip(ridge)
		elif under != null:
			markers.tooltip_text = "%s Ma" % under.time
		elif coupling != null:
			markers.tooltip_text = _coupling_tooltip(coupling)
		else:
			markers.tooltip_text = MARKERS_TOOLTIP
		return
	if event is not InputEventMouseButton or not event.pressed \
			or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var keyframe := _keyframe_at_x(event.position.x)
	var ridge := _ridge_at(event.position)
	if keyframe == null and ridge == null:
		return
	pause()
	document.set_time(_split_age(ridge) if ridge != null else keyframe.time)
	markers.accept_event()


# The marked keyframe whose mark is nearest this x across the strip and within
# reach of it, or null.
func _keyframe_at_x(x: float) -> Keyframe:
	var span := oldest() - youngest()
	if marked == null or span <= 0.0:
		return null
	var found: Keyframe = null
	var nearest := MARKER_PICK_PIXELS + 1.0
	for keyframe in marked.keyframes:
		var distance := absf(_marker_x(keyframe.time, span) - x)
		if distance <= MARKER_PICK_PIXELS and distance < nearest:
			nearest = distance
			found = keyframe
	return found


# The ridges a dot is drawn for: the marked ridge itself, a crust's ridge, or
# every ridge one of whose sections runs along the marked feature. A half split
# more than once has one per split made with a ridge; a split without one left
# no ridge and gets no dot.
func _find_ridges(node: Feature) -> Array[Feature]:
	var result: Array[Feature] = []
	if node == null or node.is_group or document == null:
		return result
	if node.midway:
		result.append(node)
		return result
	if node.is_crust():
		var ridge := document.root.get_node_by_uuid(node.crust_ridge)
		if ridge != null:
			result.append(ridge)
		return result
	var stack: Array[Feature] = [document.root]
	while not stack.is_empty():
		var other: Feature = stack.pop_back()
		stack.append_array(other.children)
		if other.midway and Ridge.side_of(other, node) != -1:
			result.append(other)
	return result


# A ridge appears at its split age, the older end of its time range.
func _split_age(ridge: Feature) -> float:
	return float(ridge.time_range.y)


# The marked ridge whose dot is under this point of the strip, or null.
func _ridge_at(point: Vector2) -> Feature:
	var span := oldest() - youngest()
	if not show_ridges or span <= 0.0 or point.y > RIDGE_DOT_RADIUS * 2.0 + MARKER_PICK_PIXELS:
		return null
	for ridge in _ridges:
		if absf(_marker_x(_split_age(ridge), span) - point.x) <= MARKER_PICK_PIXELS:
			return ridge
	return null


# What the pointer over a dot says: the two halves the ridge runs between, by
# the first feature on each side, and when it appears.
func _ridge_tooltip(ridge: Feature) -> String:
	var names := ["?", "?"]
	for section in ridge.sections:
		if section.side in [0, 1] and names[section.side] == "?":
			var feature := document.root.get_node_by_uuid(section.feature_uuid)
			if feature != null:
				names[section.side] = feature.title
	return "Ridge between %s and %s from %s Ma" % [names[0], names[1], _split_age(ridge)]


# The span of the marked node whose bar is under this point of the strip, or
# null.
func _coupling_at(point: Vector2) -> Coupling:
	var span := oldest() - youngest()
	if marked == null or span <= 0.0 \
			or point.y < markers.size.y - COUPLING_HEIGHT - COUPLING_PICK_PIXELS:
		return null
	for coupling in marked.couplings:
		if point.x >= _marker_x(coupling.from, span) and point.x <= _marker_x(coupling.to, span):
			return coupling
	return null


# What the pointer over a bar says: what the span follows and when, and why
# the parent cannot be followed when it cannot.
func _coupling_tooltip(coupling: Coupling) -> String:
	var nodes := _nodes()
	var text := "Follows %s from %s to %s Ma" % [
		Coupling.parents_label(nodes, coupling), coupling.from, coupling.to]
	var problem := Coupling.parent_problem(nodes, marked, coupling)
	return text if problem.is_empty() else "%s. %s" % [text, problem]


# The color a span's bar is drawn in: its first parent's, opaque.
func _coupling_color(coupling: Coupling) -> Color:
	var parent: Feature = _nodes().get(coupling.parent)
	if parent == null:
		return COUPLING_COLOR
	return Color(parent.color, 1.0)


func _nodes() -> Dictionary:
	return Coupling.index(document.root) \
		if document != null and marked != null and not marked.couplings.is_empty() else {}


### Keyframe markers


# Mark the keyframes of this node under the slider. Called with whatever the
# feature tree has selected, and again whenever its keyframes change.
func show_keyframes(node: Feature) -> void:
	marked = node
	_ridges = _find_ridges(node)
	markers.queue_redraw()
	_update_buttons()


func _draw_markers() -> void:
	var span := oldest() - youngest()
	if span <= 0.0 or markers.size.x <= 0.0:
		return

	if document != null:
		var x := _marker_x(document.current_time, span)
		markers.draw_line(Vector2(x, 0.0), Vector2(x, markers.size.y), CURSOR_COLOR, 1.0)

	if marked == null:
		return
	var nodes := _nodes()
	for coupling in marked.couplings:
		var from_x := _marker_x(coupling.from, span)
		var to_x := _marker_x(coupling.to, span)
		var color := _coupling_color(coupling)
		if Coupling.parent_problem(nodes, marked, coupling).is_empty():
			markers.draw_rect(Rect2(from_x, markers.size.y - COUPLING_HEIGHT,
				to_x - from_x, COUPLING_HEIGHT), color)
		else:
			var y := markers.size.y - COUPLING_HEIGHT / 2.0
			markers.draw_dashed_line(Vector2(from_x, y), Vector2(to_x, y), color,
				COUPLING_HEIGHT, COUPLING_DASH)
	for keyframe in marked.keyframes:
		var x := _marker_x(keyframe.time, span)
		markers.draw_line(Vector2(x, 0.0), Vector2(x, markers.size.y), MARKER_COLOR, 2.0)
	if show_ridges:
		for ridge in _ridges:
			markers.draw_circle(Vector2(_marker_x(_split_age(ridge), span), RIDGE_DOT_RADIUS),
				RIDGE_DOT_RADIUS, RIDGE_COLOR)


# Where a time sits across the strip, under the middle of the slider's grabber
# at that time: the oldest end on the left, the youngest on the right. The
# grabber travels over the slider's width less its own, inset by half of it
# at each end unless the theme centers it on the ends, which is also how the
# slider turns a click into a value.
func _marker_x(time: float, span: float) -> float:
	var ratio := clampf((oldest() - time) / span, 0.0, 1.0)
	var inset := 0.0
	if slider.get_theme_constant("center_grabber") == 0:
		inset = slider.get_theme_icon("grabber").get_width() / 2.0
	var left := slider.get_global_rect().position.x - markers.get_global_rect().position.x + inset
	return left + ratio * (slider.size.x - 2.0 * inset)


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
		"shown": time_spin.get_line_edit().text,
		"shown_width": time_spin.size.x,
		"playing": playing,
		"skip": skip(),
		"markers": _markers_to_json(),
		"marker_screen": _marker_screen_to_json(),
		"slider_screen": [slider.get_global_rect().position.x, slider.get_global_rect().position.y,
			slider.size.x, slider.size.y],
		"couplings": _couplings_to_json(),
		"ridges": _ridges_to_json(),
		"animation": animation.to_json(),
	}


# The bars of the marked feature's spans: both ends as ages, where the bar
# starts and ends across the window, with the height it is drawn at, the color
# it is drawn in, whether it is dashed, and what the pointer over it says.
func _couplings_to_json() -> Array:
	var bars: Array = []
	var span := oldest() - youngest()
	if marked == null or span <= 0.0:
		return bars
	var origin := markers.get_global_rect().position
	var nodes := _nodes()
	for coupling in marked.couplings:
		var color := _coupling_color(coupling)
		bars.append({
			"color": [color.r, color.g, color.b, color.a],
			"dashed": not Coupling.parent_problem(nodes, marked, coupling).is_empty(),
			"tooltip": _coupling_tooltip(coupling),
			"from": coupling.from,
			"to": coupling.to,
			"screen": [origin.x + _marker_x(coupling.from, span), origin.x + _marker_x(coupling.to, span),
				origin.y + markers.size.y - COUPLING_HEIGHT / 2.0],
		})
	return bars


# The ridge dots drawn for the marked node: the split age, what the pointer
# over the dot says, and where the dot is in the window. Empty while the dots
# are switched off.
func _ridges_to_json() -> Array:
	var dots: Array = []
	var span := oldest() - youngest()
	if not show_ridges or span <= 0.0:
		return dots
	var origin := markers.get_global_rect().position
	for ridge in _ridges:
		dots.append({
			"time": _split_age(ridge),
			"tooltip": _ridge_tooltip(ridge),
			"screen": [origin.x + _marker_x(_split_age(ridge), span), origin.y + RIDGE_DOT_RADIUS],
		})
	return dots


func _markers_to_json() -> Array:
	var times: Array = []
	if marked != null:
		for keyframe in marked.keyframes:
			times.append(keyframe.time)
	return times


# Where each mark is in the window, as [time, x, y], so a scripted run can click
# one the way a person does.
func _marker_screen_to_json() -> Array:
	var marks: Array = []
	var span := oldest() - youngest()
	if marked == null or span <= 0.0:
		return marks
	var origin := markers.get_global_rect().position
	for keyframe in marked.keyframes:
		# A mark at either end of the range sits on the edge of the strip, and
		# the edge pixel itself is outside the control; a pixel in from it is
		# still within reach of the mark.
		var x := clampf(_marker_x(keyframe.time, span), 1.0, markers.size.x - 1.0)
		marks.append([keyframe.time, origin.x + x, origin.y + markers.size.y / 2.0])
	return marks


# Press one of the buttons the way a person would, for the scripted session.
func press(button_name: String) -> String:
	var button: Button = {
		"Play": play_button,
		"Pause": pause_button,
		"Reset": reset_button,
		"Older": older_button,
		"Younger": younger_button,
		"OlderKeyframe": older_keyframe_button,
		"YoungerKeyframe": younger_keyframe_button,
		"Configure": configure_button,
	}.get(button_name)
	if button == null:
		return "no timeline button called %s" % button_name
	if button.disabled:
		return "the %s button is disabled" % button_name
	button.pressed.emit()
	return ""
