class_name AnimationSettings
extends RefCounted

# How playback walks the timeline: from start to end in steps of increment, at
# frames_per_second, and round again when it loops. Times are ages in millions
# of years before present, so the usual animation runs from a large start down
# to an end of 0, the present. See Docs/Time.md.
#
# These belong to whoever is at the keyboard rather than to the document: they
# say how fast a person likes to watch, not anything about the planet, so they
# live in the config file and moving them dirties nothing.

const DEFAULTS := {
	"start": 2000.0,
	"end": 0.0,
	"increment": 10.0,
	"frames_per_second": 24.0,
	"loop": false,
	"land_on_end": true,
}

# The oldest start or end a dialog offers; the same limit a time range has.
const MAX_TIME := Document.MAX_TIME

# Where the animation begins and ends. start above end runs backwards in age,
# which is the direction the Earth is usually watched in.
var start: float = DEFAULTS["start"]
var end: float = DEFAULTS["end"]

# How far one frame moves, always positive: the direction comes from the ends.
var increment: float = DEFAULTS["increment"]

var frames_per_second: float = DEFAULTS["frames_per_second"]

# Start again from the beginning instead of stopping at the end.
var loop: bool = DEFAULTS["loop"]

# Whether the last frame lands exactly on the end time when the increment does
# not divide the range. Without it the animation stops at the last whole step.
var land_on_end: bool = DEFAULTS["land_on_end"]


### The frames


# The times the animation steps through, in order, the ends included. Each one
# is a whole number of increments from the start rather than the one before it
# plus an increment, so a long run cannot drift away from the times the
# keyframes sit at. There is always at least one frame.
func times() -> PackedFloat64Array:
	var frames := PackedFloat64Array()
	var span := end - start
	if is_zero_approx(span) or increment <= 0.0:
		frames.append(start)
		return frames

	var direction := signf(span)
	var steps := int(floor(absf(span) / increment))
	for i in steps + 1:
		frames.append(start + direction * increment * i)
	if land_on_end and not is_equal_approx(frames[frames.size() - 1], end):
		frames.append(end)
	return frames


# How long one frame is on screen, in seconds.
func frame_seconds() -> float:
	return 1.0 / maxf(frames_per_second, 0.01)


### Validation


# Why these settings cannot be played, or an empty string when they can.
func problem() -> String:
	if increment <= 0.0:
		return "The increment must be more than zero."
	if frames_per_second <= 0.0:
		return "The frame rate must be more than zero."
	for value in [start, end]:
		if value < 0.0 or value > MAX_TIME:
			return "A time of %s is outside 0 to %d." % [value, MAX_TIME]
	return ""


### Settings file


func to_json() -> Dictionary:
	return {
		"start": start,
		"end": end,
		"increment": increment,
		"frames_per_second": frames_per_second,
		"loop": loop,
		"land_on_end": land_on_end,
	}


# Read what the config file holds, falling back to the default of each field on
# its own, so a file written by an older version is read as far as it goes.
static func from_json(data: Variant) -> AnimationSettings:
	var settings := AnimationSettings.new()
	if data is not Dictionary:
		return settings
	settings.start = float(data.get("start", DEFAULTS["start"]))
	settings.end = float(data.get("end", DEFAULTS["end"]))
	settings.increment = float(data.get("increment", DEFAULTS["increment"]))
	settings.frames_per_second = float(
		data.get("frames_per_second", DEFAULTS["frames_per_second"]))
	settings.loop = bool(data.get("loop", DEFAULTS["loop"]))
	settings.land_on_end = bool(data.get("land_on_end", DEFAULTS["land_on_end"]))
	if not settings.problem().is_empty():
		return AnimationSettings.new()
	return settings


static func load_settings() -> AnimationSettings:
	return AnimationSettings.from_json(Config.get_value("animation"))


func save_settings() -> void:
	Config.set_value("animation", to_json())
