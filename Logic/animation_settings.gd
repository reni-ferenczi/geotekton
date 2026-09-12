class_name AnimationSettings
extends RefCounted

# How playback runs the timeline: from start to end at a speed in millions of
# years per second of wall clock, and round again when it loops. Times are ages
# in millions of years before present, so the usual animation runs from a large
# start down to an end of 0, the present. See Docs/Time.md.
#
# These belong to whoever is at the keyboard rather than to the document: they
# say how fast a person likes to watch, not anything about the planet, so they
# live in the config file and moving them dirties nothing.

const DEFAULTS := {
	"start": 2000.0,
	"end": 0.0,
	"speed": 50.0,
	"loop": false,
}

# The oldest start or end a dialog offers; the same limit a time range has.
const MAX_TIME := Document.MAX_TIME

# Where the animation begins and ends. start above end runs backwards in age,
# which is the direction the Earth is usually watched in.
var start: float = DEFAULTS["start"]
var end: float = DEFAULTS["end"]

# How far the time moves in one second of playback, always positive: the
# direction comes from the ends. 50 takes the default range in 40 seconds.
var speed: float = DEFAULTS["speed"]

# Start again from the beginning instead of stopping at the end.
var loop: bool = DEFAULTS["loop"]


### Playback


# The time playback reaches after this many seconds at the given time, moving
# from start towards end and never past it. Every rendered frame asks with the
# seconds since the frame before, so the motion is continuous and between two
# keyframes it is the interpolation the keyframes already give.
func advance(time: float, seconds: float) -> float:
	var moved := time + signf(end - start) * speed * seconds
	return clampf(moved, minf(start, end), maxf(start, end))


# Whether playback has run out at this time.
func reached_end(time: float) -> bool:
	return is_equal_approx(time, end) or (end > start and time > end) \
		or (end < start and time < end)


### Validation


# Why these settings cannot be played, or an empty string when they can.
func problem() -> String:
	if speed <= 0.0:
		return "The speed must be more than zero."
	for value in [start, end]:
		if value < 0.0 or value > MAX_TIME:
			return "A time of %s is outside 0 to %d." % [value, MAX_TIME]
	return ""


### Settings file


func to_json() -> Dictionary:
	return {
		"start": start,
		"end": end,
		"speed": speed,
		"loop": loop,
	}


# Read what the config file holds, falling back to the default of each field on
# its own, so a file written by an older version is read as far as it goes. The
# step, frame rate and end landing that version kept are left unread: playback
# is continuous now and has no use for them.
static func from_json(data: Variant) -> AnimationSettings:
	var settings := AnimationSettings.new()
	if data is not Dictionary:
		return settings
	settings.start = float(data.get("start", DEFAULTS["start"]))
	settings.end = float(data.get("end", DEFAULTS["end"]))
	settings.speed = float(data.get("speed", DEFAULTS["speed"]))
	settings.loop = bool(data.get("loop", DEFAULTS["loop"]))
	if not settings.problem().is_empty():
		return AnimationSettings.new()
	return settings


static func load_settings() -> AnimationSettings:
	return AnimationSettings.from_json(Config.get_value("animation"))


func save_settings() -> void:
	Config.set_value("animation", to_json())
