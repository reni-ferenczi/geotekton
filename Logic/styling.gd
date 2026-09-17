class_name Styling
extends RefCounted

# Which features are drawn and what colour they come out. One of these is built
# from the open document's view settings and its feature tree, whose groups
# carry the styles, and handed to Planet.collect_geometry(), which is the single
# place either question is asked. See Docs/Styling.md.

# The geometry classes the View menu switches on and off, by the name the file
# stores against the label the menu shows. A feature belongs to exactly one:
# a topology by the geometry it holds, a circle by its feature type, and
# everything else by its geometry kind. Every switch therefore takes away its
# own class and nothing else.
const CLASSES := {
	"polygons": "Polygons",
	"polylines": "Polylines",
	"points": "Points",
	"circles": "Circles",
	"topologies": "Topologies",
}

const POLYGONS := "polygons"
const POLYLINES := "polylines"
const POINTS := "points"
const CIRCLES := "circles"
const TOPOLOGIES := "topologies"

# How a feature's colour is chosen, by the name the file stores against the
# label the chooser shows. `feature` is the colour the feature itself carries,
# which is what every version before this one drew and what a document still
# gets until someone picks another style.
const STYLES := {
	"feature": "Feature colour",
	"single": "Single colour",
	"age": "Feature age",
	"type": "Feature type",
}

const BY_FEATURE := "feature"
const BY_SINGLE := "single"
const BY_AGE := "age"
const BY_TYPE := "type"

# What a group other than the root may also say: nothing, leaving the choice to
# the group above it. The file keeps the name `inherit`; the chooser calls it
# Same as parent, since a nested group on it follows its parent's style where
# one on Feature colour would not.
const INHERIT := "inherit"
const MODES := {
	"inherit": "Same as parent",
	"feature": "Feature colour",
	"single": "Single colour",
	"age": "Feature age",
	"type": "Feature type",
}

# What every feature is drawn in under the single colour style until someone
# picks another.
const DEFAULT_SINGLE := Color(0.9, 0.9, 0.9, 1.0)

# The switches, and the palettes read so far by source, shared with whoever
# built this so a file is read once rather than on every rebuild.
var settings: ViewSettings
var palettes: Dictionary = {}

# For every leaf under the root this was built with, the style that decides its
# color and the product of the opacities of every group above it.
var _deciding := {}
var _opacity := {}

# True when some leaf is colored by its age, which moves with the current time,
# so a step of an animation has to work the colors out again.
var by_age := false

# The ramp palette of each style that reads one, built on first use.
var _ramps := {}


# A feature outside the tree given here, or every feature when no tree is
# given, is drawn in its own colour at its own opacity.
static func of(settings_: ViewSettings, root: Feature = null, palettes_: Dictionary = {}) -> Styling:
	var styling := Styling.new()
	styling.settings = settings_ if settings_ != null else ViewSettings.new()
	styling.palettes = palettes_
	if root != null:
		styling._walk(root, GroupStyle.for_root(), 1.0)
	return styling


# One pass down the tree: a group on inherit hands down the style it was handed,
# and every group multiplies its opacity into what it hands down. The root has
# nothing above it, so it is handed GroupStyle.for_root(), and a root on inherit
# draws each feature's own colour. A loaded document's root carries that style
# itself.
func _walk(node: Feature, deciding: GroupStyle, opacity: float) -> void:
	if not node.is_group:
		_deciding[node] = deciding
		_opacity[node] = opacity
		by_age = by_age or deciding.mode == BY_AGE
		return
	var style: GroupStyle = node.style if node.style != null else GroupStyle.new()
	var handed := deciding if style.mode == INHERIT else style
	for child in node.children:
		_walk(child, handed, opacity * style.opacity)


# The class a feature is switched on and off with.
static func class_of(feature: Feature) -> String:
	if feature.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return TOPOLOGIES
	if feature.feature_type == FeatureType.CIRCLE:
		return CIRCLES
	match feature.geometry_kind:
		Feature.GeometryKind.POLYLINE:
			return POLYLINES
		Feature.GeometryKind.MULTIPOINT:
			return POINTS
	return POLYGONS


static func class_label(class_id: String) -> String:
	return str(CLASSES.get(class_id, class_id))


# The style as it can be used, so an id from a file or a script that names no
# style becomes the one every document started with rather than no colour at all.
static func normalize_style(style_id: String) -> String:
	return style_id if STYLES.has(style_id) else BY_FEATURE


# How long a feature has existed at a time: the older end of its time range,
# where it came into existence, minus the time. Ages run backwards, so that is
# the larger end. Never below zero, before the feature exists.
static func age_of(feature: Feature, time: float = 0.0) -> float:
	return maxf(float(feature.time_range.y) - time, 0.0)


func shows(feature: Feature) -> bool:
	return settings.shows_class(class_of(feature))


# The color a feature is drawn in: what the nearest group not on inherit says,
# with the alpha multiplied by the opacity of every group above the feature. The
# age style reads the feature's age at `time`.
func color_of(feature: Feature, time: float = 0.0) -> Color:
	var style: GroupStyle = _deciding.get(feature)
	var color := feature.color
	if style != null:
		match style.mode:
			BY_SINGLE:
				color = style.color
			BY_AGE:
				color = age_palette(style).color_at(Styling.age_of(feature, time))
			BY_TYPE:
				color = FeatureType.color(feature.feature_type)
		color.a *= float(_opacity[feature])
	return color


# The palette a style's age mode reads: its own ramp, or a palette by source.
func age_palette(style: GroupStyle) -> Palette:
	if style.palette != Palette.RAMP:
		return palette_of(style.palette)
	if not _ramps.has(style):
		_ramps[style] = style.ramp()
	return _ramps[style]


# A palette by source, read the first time it is asked for.
func palette_of(source: String) -> Palette:
	if not palettes.has(source):
		palettes[source] = Palette.resolve(source)
	return palettes[source]
