class_name Styling
extends RefCounted

# Which features are drawn and what colour they come out. One of these is built
# from the open document's view settings and the palette they name, and handed
# to Planet.collect_geometry(), which is the single place either question is
# asked. See Docs/Styling.md.

# The geometry classes the View menu switches on and off, by the name the file
# stores against the label the menu shows. A feature belongs to exactly one:
# a topology by the geometry it holds, a small circle by its feature type, and
# everything else by its geometry kind. Every switch therefore takes away its
# own class and nothing else.
const CLASSES := {
	"polygons": "Polygons",
	"polylines": "Polylines",
	"points": "Points",
	"small_circles": "Small Circles",
	"topologies": "Topologies",
}

const POLYGONS := "polygons"
const POLYLINES := "polylines"
const POINTS := "points"
const SMALL_CIRCLES := "small_circles"
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

# What every feature is drawn in under the single colour style until someone
# picks another.
const DEFAULT_SINGLE := Color(0.9, 0.9, 0.9, 1.0)

# What the document asks for, and the palette it names, already read.
var settings: ViewSettings
var palette: Palette


static func of(settings_: ViewSettings, palette_: Palette = null) -> Styling:
	var styling := Styling.new()
	styling.settings = settings_ if settings_ != null else ViewSettings.new()
	styling.palette = palette_ if palette_ != null else Palette.resolve(styling.settings.palette)
	return styling


# The class a feature is switched on and off with.
static func class_of(feature: Feature) -> String:
	if feature.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		return TOPOLOGIES
	if feature.feature_type == "small_circle":
		return SMALL_CIRCLES
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


# How old a feature is, which is the older end of its time range: the age it
# came into existence at. Ages run backwards, so that is the larger of the two.
static func age_of(feature: Feature) -> float:
	return float(feature.time_range.y)


func shows(feature: Feature) -> bool:
	return settings.shows_class(class_of(feature))


func color_of(feature: Feature) -> Color:
	match Styling.normalize_style(settings.draw_style):
		BY_SINGLE:
			return settings.single_color
		BY_AGE:
			return palette.color_at(Styling.age_of(feature))
		BY_TYPE:
			return FeatureType.color(feature.feature_type)
	return feature.color
