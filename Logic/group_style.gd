class_name GroupStyle
extends RefCounted

# How a group colors the features under it, the way a GPlates layer colors
# everything in it at once. Every group carries one; the root group's is the
# document default, which the View settings dialog edits, and any other group's
# is edited in the Properties panel. Styling.color_of() walks up from a feature
# to the nearest group whose mode is not inherit. See Docs/Styling.md.

# The view settings keys that 0.10.0 moved onto the root group, against the
# style field each became. Document.migrate() and the preferences both read
# older blocks through it.
const VIEW_KEYS := {"draw_style": "mode", "single_color": "color", "palette": "palette"}

# An id in Styling.MODES. Inherit leaves the choice to the group above.
var mode: String = Styling.INHERIT

# What the single colour mode paints with.
var color: Color = Styling.DEFAULT_SINGLE

# 0 to 1, multiplied into every feature under the group, whichever group
# decides the color.
var opacity: float = 1.0

# The palette the feature age mode reads: Palette.RAMP, a key of
# Palette.BUILT_IN or the path of a `.cpt` file.
var palette: String = Palette.DEFAULT

# The custom ramp, read when `palette` is Palette.RAMP: the first colour at age
# zero, each next one ramp_span My later, and the last held after that. Two
# colours at the least.
var ramp_colors: Array[Color] = Palette.DEFAULT_RAMP_COLORS.duplicate()
var ramp_span: float = Palette.DEFAULT_RAMP_SPAN


# The document default: the root has nothing above it to inherit from, so it
# starts on each feature's own colour.
static func for_root() -> GroupStyle:
	var style := GroupStyle.new()
	style.mode = Styling.BY_FEATURE
	return style


func clone() -> GroupStyle:
	return GroupStyle.from_json(to_json())


func to_json() -> Dictionary:
	return {
		"mode": mode,
		"color": [color.r, color.g, color.b, color.a],
		"opacity": opacity,
		"palette": palette,
		"ramp_colors": ramp_colors.map(
			func(c: Color) -> Array: return [c.r, c.g, c.b, c.a]),
		"ramp_span": ramp_span,
	}


# The ramp as a palette, so it is looked up and previewed the way every other
# palette is.
func ramp() -> Palette:
	return Palette.ramp(ramp_colors, ramp_span)


# Read a style back, taking the default for anything it does not say. A mode no
# version knows is inherit, so a file from a later version cannot take the
# choice away from the group above.
static func from_json(data: Variant) -> GroupStyle:
	var style := GroupStyle.new()
	if data is not Dictionary:
		return style
	var mode_id := str(data.get("mode", Styling.INHERIT))
	style.mode = mode_id if Styling.MODES.has(mode_id) else Styling.INHERIT
	style.color = _color(data.get("color"), Styling.DEFAULT_SINGLE)
	style.opacity = clampf(float(data.get("opacity", 1.0)), 0.0, 1.0)
	style.palette = str(data.get("palette", Palette.DEFAULT))
	style.ramp_colors = colors_from(data.get("ramp_colors"))
	style.ramp_span = clampf(float(data.get("ramp_span", Palette.DEFAULT_RAMP_SPAN)),
		1.0, Document.MAX_TIME)
	return style


# A list of `[r, g, b]` or `[r, g, b, a]` as the colours of a ramp, or the
# default ramp when fewer than two of them can be read.
static func colors_from(list: Variant) -> Array[Color]:
	var colors: Array[Color] = []
	if list is Array:
		for entry in list as Array:
			colors.append(_color(entry, Color.BLACK))
	return colors if colors.size() >= Palette.MIN_RAMP_COLORS \
		else Palette.DEFAULT_RAMP_COLORS.duplicate()


# `[r, g, b]` or `[r, g, b, a]`, or the fallback for anything else.
static func _color(c: Variant, fallback: Color) -> Color:
	if c is Array and (c as Array).size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]),
			float(c[3]) if (c as Array).size() > 3 else 1.0)
	return fallback


# The style a view settings block written before 0.10.0 describes, as the JSON
# the root group carries now. Empty when the block names none of the keys.
static func json_from_view_block(block: Dictionary) -> Dictionary:
	var style := {}
	for key in VIEW_KEYS:
		if block.has(key):
			style[VIEW_KEYS[key]] = block[key]
	return style
