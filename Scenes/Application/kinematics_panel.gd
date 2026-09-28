extends PanelContainer
class_name KinematicsPanel

# The kinematics panel under the globe: where the middle of the selected feature
# has been over time, and how fast it moves. The rate graph over a time
# axis, with a cursor on the current time; latitude and longitude get a graph
# each above it when show_place is on (View > Kinematics: latitude and longitude).
# See Docs/Kinematics.md.
#
# The numbers are worked out in Logic/kinematics.gd, which needs no scene, so
# what is drawn here can be checked without a window. The panel keeps what it
# was given rather than following the document itself: the application says when
# the selection or the geometry has changed, and the current time comes in
# through the document's own signal.

# How many places along the time axis the path is worked out at. Enough for a
# smooth line across a wide window, and few enough that a redraw is nothing.
const SAMPLES := 200

# The graph rows: how tall one is, the gap between two, and the gutters either
# side of the plotting area for the row's name and the values it spans.
const ROW_HEIGHT := 46
const ROW_GAP := 4
const LABEL_WIDTH := 64
const VALUE_WIDTH := 96

# Room under the last row for the two ends of the time axis.
const AXIS_HEIGHT := 16

# What the two place rows span. They are drawn against the whole of what a
# latitude and a longitude can be, so a feature that hardly moves reads as
# hardly moving rather than being blown up to fill the box.
const LATITUDE_LIMIT := 90.0
const LONGITUDE_LIMIT := 180.0

const LATITUDE_COLOR := Color(0.45, 0.75, 1.0, 1.0)
const LONGITUDE_COLOR := Color(1.0, 0.75, 0.35, 1.0)
const RATE_COLOR := Color(0.5, 0.85, 0.55, 0.85)
const FRAME_COLOR := Color(1.0, 1.0, 1.0, 0.25)
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 0.7)

# The current time, in the colour the timeline marks it in.
const CURSOR_COLOR := Color(1.0, 1.0, 1.0, 0.6)

const FONT_SIZE := 10

# The plate speeds of the worldbuilding tutorial the users follow, shown when
# the pointer rests on the rate. Ranges to compare with, not targets, which is
# why they are not drawn on the graph. See Docs/Kinematics.md#reference-speeds.
const REFERENCE_SPEEDS := """Typical plate speeds (Worldbuilding Pasta, An Apple Pie From Scratch, Part V):
Subducting ocean: 8 to 20 cm/yr
Recent subduction collision: 6 cm/yr
Active margin continent: 3 cm/yr
Passive margin continent: under 1 cm/yr"""

# The open document and the time control, both set by Application through
# attach(). The time control owns the animation range, which is what the time
# axis spans, so the graphs and the slider say the same thing.
var document: Document
var timeline: Timeline

# What is being graphed, null while nothing is.
var node: Feature = null

var readout: Label
var graphs: Control

# The current rate beside the top of the rate row, the one number in the panel
# worth copying, so it is selectable text over the graphs rather than drawn on
# them (GP-0144).
var rate_value: SelectableText

# Whether the latitude and longitude graphs are drawn above the rate. The
# panel is two rows shorter without them, and that height goes to the planet.
var show_place: bool = false:
	set(value):
		show_place = value
		if graphs != null:
			_fit_rows()

# Where the middle of the node is at each sample time, oldest first, and how
# fast it turns between its keyframes. Worked out when the selection, the
# geometry or the animation range changes, not while drawing.
var _samples: Array[Dictionary] = []
var _segments: Array[Dictionary] = []
var _peak: float = 0.0


func _ready() -> void:
	_build()
	show_node(null)


func attach(document_: Document, timeline_: Timeline) -> void:
	document = document_
	timeline = timeline_
	document.time_changed.connect(_show_time)
	timeline.animation_changed.connect(refresh)


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

	readout = Label.new()
	readout.name = "Readout"
	readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readout.tooltip_text = REFERENCE_SPEEDS
	readout.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(readout)

	graphs = Control.new()
	graphs.name = "Graphs"
	graphs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graphs.tooltip_text = REFERENCE_SPEEDS
	graphs.draw.connect(_draw_graphs)
	graphs.resized.connect(graphs.queue_redraw)
	box.add_child(graphs)

	rate_value = SelectableText.new()
	rate_value.name = "RateValue"
	rate_value.add_theme_font_size_override("font_size", FONT_SIZE)
	rate_value.set_color(TEXT_COLOR)
	rate_value.tooltip_text = REFERENCE_SPEEDS
	graphs.add_child(rate_value)
	_fit_rows()


# How many graph rows are drawn: the rate, and the two place rows over it when
# they are switched on.
func row_count() -> int:
	return 3 if show_place else 1


# The graphs are as tall as their rows; the panel is as tall as they are, with
# the line above them only while it has something to say.
func _fit_rows() -> void:
	var rows_height := row_count() * (ROW_HEIGHT + ROW_GAP) + AXIS_HEIGHT
	graphs.custom_minimum_size = Vector2(0, rows_height)
	graphs.queue_redraw()


### What is being graphed


# Graph this node, or nothing at all. Called with whatever the feature tree has
# selected, and again whenever its geometry or its motion has changed.
func show_node(node_: Feature) -> void:
	node = node_
	refresh()


# Work the graphs out again from what the node holds now. Also what follows the
# animation range being configured, since that is the span they are drawn over.
func refresh() -> void:
	_samples = Kinematics.path(_root(), node, oldest(), youngest(), SAMPLES)
	_segments = Kinematics.segments(_root(), node, Config.get_planet_radius())
	_peak = Kinematics.peak_rate(_segments)
	readout.text = _readout_text()
	# Empty while a feature is graphed, and then it takes no room either.
	readout.visible = not readout.text.is_empty()
	_show_time()


# The cursor and the rate beside the rate row follow the current time; the
# graphs themselves stand still under it.
func _show_time() -> void:
	var text := rate_label(_current_rate(), Config.get_rate_unit()) if not _samples.is_empty() else ""
	# Set only when it changes, so a selection in it survives the frames between.
	if rate_value.text != text:
		rate_value.text = text
	graphs.queue_redraw()


func _root() -> Feature:
	return document.root if document != null else null


# The two ends of the time axis, the span the timeline slider covers.
func oldest() -> float:
	return timeline.oldest() if timeline != null else 0.0


func youngest() -> float:
	return timeline.youngest() if timeline != null else 0.0


# The line above the graphs: why there is nothing to draw, and empty while a
# feature is graphed. The rate is beside the rate row; the panel gives no title,
# time, place or bearing (GP-0142).
func _readout_text() -> String:
	if node == null:
		return "Nothing is selected."
	if node.is_group:
		return "A group has no geometry of its own, so there is no place to follow."
	if node.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return "A topology is resolved from the features its sections run along, so it has no motion of its own."
	if _samples.is_empty():
		return "%s has no geometry yet." % node.title
	return ""


# A time the way the time axis writes it: a plain number of millions of years,
# without the trailing zero a whole one would carry.
static func format_time(time: float) -> String:
	return String.num(time, 4).trim_suffix(".0")


func _current_time() -> float:
	return document.current_time if document != null else 0.0


# What the graphs come to at the current time: where the middle of the node is
# and how fast it is turning there. Empty while there is nothing graphed.
func _current_values() -> Dictionary:
	if _samples.is_empty():
		return {}
	var place := Kinematics.position_at(_root(), node, _current_time())
	return Kinematics.rate_at(_segments, _current_time()).merged(
		{"lat": place.x, "lon": place.y})


### Drawing


func _draw_graphs() -> void:
	if _samples.is_empty() or graphs.size.x <= LABEL_WIDTH + VALUE_WIDTH:
		return
	if show_place:
		_draw_place_row(0, "Latitude", "lat", LATITUDE_LIMIT, LATITUDE_COLOR, false)
		_draw_place_row(1, "Longitude", "lon", LONGITUDE_LIMIT, LONGITUDE_COLOR, true)
	_draw_rate_row(row_count() - 1)
	_draw_time_axis()


# The plotting area of one row, without the gutters either side of it.
func _plot(row: int) -> Rect2:
	return Rect2(
		LABEL_WIDTH,
		row * (ROW_HEIGHT + ROW_GAP),
		graphs.size.x - LABEL_WIDTH - VALUE_WIDTH,
		ROW_HEIGHT)


# One of the two graphs of where the middle is: the frame, the line through the
# samples, and the cursor on the current time. The row spans plus and minus the
# limit, with the equator or the prime meridian along the middle of the box.
# `wraps` says the values run right round, so the line is cut where it leaves
# one edge and comes back at the other rather than drawn across the whole box.
func _draw_place_row(row: int, label: String, key: String, limit: float,
		color: Color, wraps: bool) -> void:
	var plot := _plot(row)
	_draw_frame(plot, label, "%+.0f°" % limit, "%+.0f°" % -limit)
	graphs.draw_line(
		Vector2(plot.position.x, plot.get_center().y),
		Vector2(plot.end.x, plot.get_center().y), GRID_COLOR, 1.0)

	var line := PackedVector2Array()
	var previous := 0.0
	for sample in _samples:
		var value := float(sample[key])
		if wraps and not line.is_empty() and absf(value - previous) > limit:
			_stroke(line, color)
			line = PackedVector2Array()
		previous = value
		line.append(Vector2(
			_time_x(float(sample["time"]), plot),
			_value_y(value, limit, plot)))
	_stroke(line, color)
	_draw_cursor(plot)


# The rate, one bar per span between two keyframes. A bar rather than a line:
# the rate holds over the whole span and steps at each keyframe, which a line
# through the middle of each span would draw as a slope that is not there.
func _draw_rate_row(row: int) -> void:
	var plot := _plot(row)
	_draw_frame(plot, "Rate", "", "0")
	# The rate itself stands where the frame would write the top value.
	rate_value.position = Vector2(plot.end.x + 6.0, plot.position.y - 3.0)
	rate_value.size = Vector2(VALUE_WIDTH - 6, FONT_SIZE + 4)
	if _peak > 0.0:
		for segment in _segments:
			var left := _time_x(float(segment["to"]), plot)
			var right := _time_x(float(segment["from"]), plot)
			var height := plot.size.y * float(segment["km_per_my"]) / _peak
			graphs.draw_rect(
				Rect2(left, plot.end.y - height, maxf(right - left, 1.0), height), RATE_COLOR)
	_draw_cursor(plot)


# What the rate row says beside its top: the rate at the current time, `km` in
# km/My, in the unit the preference names, the only place it is written. The
# fastest span the bars are scaled against is not written anywhere; it says
# nothing about where the feature is now (GP-0136).
static func rate_label(km: float, unit: String) -> String:
	return Measure.format_rate(maxf(km, 0.0), unit)


func _current_rate() -> float:
	return float(Kinematics.rate_at(_segments, _current_time())["km_per_my"])


# The box of one row, with its name to the left of it and what its top and its
# bottom edge stand for to the right.
func _draw_frame(plot: Rect2, label: String, top: String, bottom: String) -> void:
	graphs.draw_rect(plot, FRAME_COLOR, false, 1.0)
	var font := get_theme_default_font()
	graphs.draw_string(font, Vector2(0.0, plot.get_center().y + FONT_SIZE * 0.4), label,
		HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 6, FONT_SIZE, TEXT_COLOR)
	graphs.draw_string(font, Vector2(plot.end.x + 6.0, plot.position.y + FONT_SIZE), top,
		HORIZONTAL_ALIGNMENT_LEFT, VALUE_WIDTH - 6, FONT_SIZE, TEXT_COLOR)
	graphs.draw_string(font, Vector2(plot.end.x + 6.0, plot.end.y - 1.0), bottom,
		HORIZONTAL_ALIGNMENT_LEFT, VALUE_WIDTH - 6, FONT_SIZE, TEXT_COLOR)


# The two ends of the time axis, under the last row: the oldest on the left, the
# youngest on the right, which is the way the timeline runs.
func _draw_time_axis() -> void:
	var plot := _plot(row_count() - 1)
	var font := get_theme_default_font()
	var baseline := plot.end.y + AXIS_HEIGHT - 2.0
	graphs.draw_string(font, Vector2(plot.position.x, baseline),
		"%s Ma" % format_time(oldest()),
		HORIZONTAL_ALIGNMENT_LEFT, plot.size.x * 0.5, FONT_SIZE, TEXT_COLOR)
	graphs.draw_string(font, Vector2(plot.get_center().x, baseline),
		"%s Ma" % format_time(youngest()),
		HORIZONTAL_ALIGNMENT_RIGHT, plot.size.x * 0.5, FONT_SIZE, TEXT_COLOR)


func _draw_cursor(plot: Rect2) -> void:
	var x := _time_x(_current_time(), plot)
	graphs.draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), CURSOR_COLOR, 1.0)


func _stroke(line: PackedVector2Array, color: Color) -> void:
	if line.size() > 1:
		graphs.draw_polyline(line, color, 1.5, true)


# Where a time sits across a row, matching the timeline below it: the oldest end
# on the left, the youngest on the right.
func _time_x(time: float, plot: Rect2) -> float:
	var span := oldest() - youngest()
	if span <= 0.0:
		return plot.position.x
	return plot.position.x + clampf((oldest() - time) / span, 0.0, 1.0) * plot.size.x


func _value_y(value: float, limit: float, plot: Rect2) -> float:
	return plot.end.y - clampf((value + limit) / (limit * 2.0), 0.0, 1.0) * plot.size.y


### The automation port


func to_json() -> Dictionary:
	return {
		"title": node.title if node != null else "",
		"readout": readout.text,
		"time": _current_time(),
		"span": [oldest(), youngest()],
		"samples": _samples,
		"segments": _segments,
		"current": _current_values(),
		"rate_label": rate_value.text,
		"tooltip": readout.tooltip_text,
		# Where the cursor is drawn across the plotting area, and how wide that
		# is, so a run can check that it moved with the time.
		"cursor": _time_x(_current_time(), _plot(0)) - LABEL_WIDTH,
		"plot_width": maxf(graphs.size.x - LABEL_WIDTH - VALUE_WIDTH, 0.0),
		# Where the readout and the graphs sit in the window, so a run can check
		# that playing does not move them (GP-0141).
		"readout_rect": _rect_to_json(readout.get_global_rect()),
		"graphs_rect": _rect_to_json(graphs.get_global_rect()),
	}


static func _rect_to_json(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
