class_name Palette
extends RefCounted

# A colour palette: a value in, a colour out. Two shapes of the same thing, both
# of them written in the GMT colour palette table format the `.cpt` files GPlates
# ships are in.
#
# A *regular* palette is a list of slices, each running from one value to
# another between two colours. A slice whose two colours are the same is flat,
# which is what makes a palette discrete; one whose colours differ is a ramp.
# Nothing switches between the two, so a file can hold both at once.
#
# A *categorical* palette is a lookup from a key to a colour, with no order and
# nothing between the entries.
#
# Three colours stand outside either: below everything the palette covers, above
# it, and for a value it says nothing about. See Docs/Styling.md.

# The tables the chooser offers without a file, beside the custom ramp below.
# Each is written in the same format a file is and read by the same parser, so
# there is one way in.
const BUILT_IN := {
	"rainbow": {
		"name": "Rainbow",
		"cpt": """0\t255 0 0\t\t200\t255 255 0
200\t255 255 0\t400\t0 255 0
400\t0 255 0\t\t600\t0 255 255
600\t0 255 255\t800\t0 0 255
800\t0 0 255\t\t1000\t255 0 255
B\t255 0 0
F\t255 0 255""",
	},
}

# The custom ramp a group style carries itself; see GroupStyle.ramp(). It is
# listed with the built in palettes but has no table, since its colours and its
# span are the style's.
const RAMP := "ramp"
const RAMP_NAME := "Custom"

# The palette a document uses until someone picks another: the custom ramp.
const DEFAULT := RAMP

# A ramp needs an end at each side of it, so two colours is the fewest it can
# have and the one it starts with is black to white over 300 My. The defaults
# are here rather than on GroupStyle so that resolve() can answer for the ramp
# without a style to read them off.
const MIN_RAMP_COLORS := 2
const DEFAULT_RAMP_COLORS: Array[Color] = [Color(0.0, 0.0, 0.0, 1.0), Color(1.0, 1.0, 1.0, 1.0)]
const DEFAULT_RAMP_SPAN := 300.0

# What GMT gives a palette that names none of them: black below, white above and
# grey for a value the palette does not cover.
const DEFAULT_BACKGROUND := Color(0.0, 0.0, 0.0, 1.0)
const DEFAULT_FOREGROUND := Color(1.0, 1.0, 1.0, 1.0)
const DEFAULT_NO_DATA := Color(0.502, 0.502, 0.502, 1.0)

# A colour no fill can be, so Color.from_string can say that a name is not one.
const _NOT_A_COLOR := Color(-1.0, -1.0, -1.0, -1.0)

# What the chooser shows this palette as.
var name: String = ""

# Where it came from: a key of BUILT_IN, or the path of the file it was read
# from. This is what a document stores and what resolve() takes back.
var source: String = ""

# The slices of a regular palette, sorted by where they start. Each is
# { "low": float, "high": float, "from": Color, "to": Color }.
var slices: Array = []

# The entries of a categorical palette, by key.
var categories: Dictionary = {}

var background: Color = DEFAULT_BACKGROUND
var foreground: Color = DEFAULT_FOREGROUND
var no_data: Color = DEFAULT_NO_DATA

# What could not be read, one message per line that could not be, each naming
# the line it was on. A palette with errors is still a palette: the lines that
# did parse are in it, so one bad line does not lose the rest.
var errors: PackedStringArray = PackedStringArray()


### Reading a palette


# The palette a document names: the custom ramp, a built in one by its key, or
# the file at that path. An empty name, and the ramp named without a style to
# read the colours off, give the default ramp.
static func resolve(name_or_path: String) -> Palette:
	if name_or_path.is_empty() or name_or_path == RAMP:
		return ramp(DEFAULT_RAMP_COLORS, DEFAULT_RAMP_SPAN)
	if BUILT_IN.has(name_or_path):
		return built_in(name_or_path)
	return load_from(name_or_path)


# What a palette chooser lists without a file, by key against the name shown:
# the custom ramp, then the built in tables.
static func choices() -> Dictionary:
	var listed := {RAMP: RAMP_NAME}
	for key in BUILT_IN:
		listed[key] = str(BUILT_IN[key]["name"])
	return listed


# The custom ramp as a palette: one slice per neighbouring pair of colours, each
# `span` wide, with the first colour below the ramp and the last past it, so an
# age past the end holds at the last colour.
static func ramp(colors: Array, span: float) -> Palette:
	var stops := colors if colors.size() >= MIN_RAMP_COLORS else DEFAULT_RAMP_COLORS
	var palette := Palette.new()
	palette.name = RAMP_NAME
	palette.source = RAMP
	for i in stops.size() - 1:
		palette.slices.append({"low": i * span, "high": (i + 1) * span,
			"from": stops[i] as Color, "to": stops[i + 1] as Color})
	palette.background = stops[0] as Color
	palette.foreground = stops[-1] as Color
	return palette


static func built_in(key: String) -> Palette:
	if not BUILT_IN.has(key):
		key = str(BUILT_IN.keys()[0])
	var palette := parse(str(BUILT_IN[key]["cpt"]), str(BUILT_IN[key]["name"]))
	palette.source = key
	return palette


# Read a `.cpt` file. A file that cannot be opened comes back as an empty
# palette carrying the reason, so the caller has something to draw with either
# way and something to show the person who picked it.
static func load_from(path: String) -> Palette:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var failed := Palette.new()
		failed.name = path.get_file()
		failed.source = path
		failed.errors.append("Cannot read %s: %s" % [
			path, error_string(FileAccess.get_open_error())])
		return failed
	var palette := parse(file.get_as_text(), path.get_file())
	palette.source = path
	return palette


# Read palette text. Blank lines and lines starting with `#` are skipped, which
# is where a CPT file keeps its comments and its colour model declaration.
static func parse(text: String, name_: String = "") -> Palette:
	var palette := Palette.new()
	palette.name = name_
	var lines := text.replace("\r\n", "\n").split("\n")
	for index in lines.size():
		var line := lines[index].strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var problem := palette._read_line(line)
		if not problem.is_empty():
			palette.errors.append("line %d: %s" % [index + 1, problem])
	palette.slices.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["low"] < b["low"])
	return palette


# Take one line in, or say why it cannot be taken.
func _read_line(line: String) -> String:
	if line.count("'") % 2 == 1:
		return "the quoted key is not closed: %s" % line
	var tokens := _tokens(line)
	if tokens.is_empty():
		return ""

	# The three colours that stand outside the palette proper.
	if tokens[0] in ["B", "F", "N"]:
		var special := _fill(tokens, 1)
		if special.is_empty():
			return "%s must be followed by a colour: %s" % [tokens[0], line]
		match tokens[0]:
			"B": background = special[0]
			"F": foreground = special[0]
			"N": no_data = special[0]
		return ""

	# A slice of a regular palette: a value, a colour, a second value and a
	# second colour, with the annotation flags and the label after them ignored.
	if tokens.size() >= 4 and _is_number(tokens[0]):
		var low := _fill(tokens, 1)
		if not low.is_empty():
			var next := 1 + int(low[1])
			if next < tokens.size() and _is_number(tokens[next]):
				var high := _fill(tokens, next + 1)
				if not high.is_empty():
					slices.append({
						"low": float(tokens[0]),
						"high": float(tokens[next]),
						"from": low[0] as Color,
						"to": high[0] as Color,
					})
					return ""

	# An entry of a categorical palette: a key and a colour, and a label after
	# them that nothing here reads.
	var fill := _fill(tokens, 1)
	if fill.is_empty():
		return "neither a slice nor an entry: %s" % line
	categories[tokens[0]] = fill[0] as Color
	return ""


# The words of one line, with a trailing `;label` dropped and a key in single
# quotes kept whole, spaces and all.
static func _tokens(line: String) -> PackedStringArray:
	var tokens := PackedStringArray()
	var current := ""
	var quoted := false
	for i in line.length():
		var c := line[i]
		if quoted:
			if c == "'":
				quoted = false
				tokens.append(current)
				current = ""
			else:
				current += c
		elif c == "'":
			quoted = true
		elif c == ";" or c == "#":
			break
		elif c == " " or c == "\t":
			if not current.is_empty():
				tokens.append(current)
				current = ""
		else:
			current += c
	if not current.is_empty():
		tokens.append(current)
	return tokens


# The colour starting at tokens[at] as [Color, how many tokens it took], or an
# empty array when what is there is not one. GMT writes a fill as `r/g/b`, as
# three separate numbers, or as a colour name; a name is read by Godot's own
# table, so `#rrggbb` works as well.
static func _fill(tokens: PackedStringArray, at: int) -> Array:
	if at >= tokens.size():
		return []
	var token := tokens[at]
	if "/" in token:
		var parts := token.split("/")
		if parts.size() != 3 or not _are_numbers(parts):
			return []
		return [_rgb(float(parts[0]), float(parts[1]), float(parts[2])), 1]
	if _is_number(token):
		if at + 2 >= tokens.size() or not _is_number(tokens[at + 1]) \
			or not _is_number(tokens[at + 2]):
			return []
		return [_rgb(float(token), float(tokens[at + 1]), float(tokens[at + 2])), 3]
	var named := _named(token)
	return [] if named == _NOT_A_COLOR else [named, 1]


# A colour by name. Godot's own table answers first, so a name it knows is its
# colour; GMT also names a few Godot does not by putting `light` or `dark` in
# front of one it does, and those are worked out from the colour behind them.
static func _named(token: String) -> Color:
	var known := Color.from_string(token, _NOT_A_COLOR)
	if known != _NOT_A_COLOR:
		return known
	var lower := token.to_lower()
	for prefix in ["light", "dark"]:
		if not lower.begins_with(prefix):
			continue
		var base := Color.from_string(lower.substr(prefix.length()), _NOT_A_COLOR)
		if base != _NOT_A_COLOR:
			return base.lightened(0.5) if prefix == "light" else base.darkened(0.5)
	return _NOT_A_COLOR


static func _rgb(r: float, g: float, b: float) -> Color:
	return Color(clampf(r / 255.0, 0.0, 1.0), clampf(g / 255.0, 0.0, 1.0),
		clampf(b / 255.0, 0.0, 1.0), 1.0)


static func _is_number(token: String) -> bool:
	return token.is_valid_float()


static func _are_numbers(tokens: PackedStringArray) -> bool:
	for token in tokens:
		if not _is_number(token):
			return false
	return true


### Looking a colour up


func is_categorical() -> bool:
	return not categories.is_empty()


func is_empty() -> bool:
	return slices.is_empty() and categories.is_empty()


# The colour of a value on a regular palette. Below everything the palette
# covers is the background colour and above it the foreground; a value falling
# in a gap between two slices, and any value at all on a palette with no
# slices, is the no-data colour.
#
# A value on the boundary between two slices belongs to the lower of them,
# which is the same colour whenever the two meet without a step.
func color_at(value: float) -> Color:
	if is_nan(value) or slices.is_empty():
		return no_data
	if value < low():
		return background
	if value > high():
		return foreground
	for slice in slices:
		var from := float(slice["low"])
		var to := float(slice["high"])
		if value < from or value > to:
			continue
		var along := 0.0 if to <= from else (value - from) / (to - from)
		return (slice["from"] as Color).lerp(slice["to"] as Color, along)
	return no_data


# The colour of a key on a categorical palette, the no-data colour for a key it
# does not name.
func color_for(key: String) -> Color:
	return categories.get(key, no_data) as Color


# The range the slices cover. Both are zero on a palette with no slices.
func low() -> float:
	return 0.0 if slices.is_empty() else float(slices[0]["low"])


func high() -> float:
	return 0.0 if slices.is_empty() else float(slices[-1]["high"])


# The palette across its whole range, for the strip the chooser previews it
# with. A categorical palette has no range, so its entries come back in the
# order they were read.
func sample(steps: int) -> PackedColorArray:
	var colors := PackedColorArray()
	if is_categorical():
		for key in categories:
			colors.append(categories[key] as Color)
		return colors
	if slices.is_empty() or steps < 1:
		return colors
	for i in range(steps):
		var along := 0.0 if steps == 1 else float(i) / float(steps - 1)
		colors.append(color_at(lerpf(low(), high(), along)))
	return colors
