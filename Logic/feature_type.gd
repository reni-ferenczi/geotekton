class_name FeatureType

# What a feature is. The type is picked in the Properties panel and says what
# the tools draw into the feature: a Polygon a polygon, a Line a polyline,
# Points a multipoint, a Topology a line topology, and a Circle either a polygon
# or a polyline, whichever the Circle tool's Outline switch asks for. Once the
# feature holds a shape, a type that does not hold that kind gives way to the
# kind's own. Middle Earth is a world building tool and does not carry the GPGIM
# over. See Docs/Properties.md.
#
# A type is stored by its id, which is also what the file holds. The kinds are
# the names Feature.KIND_NAMES uses, so the catalog is written in the same
# vocabulary as the file and needs nothing from Feature to be read.

# The type a new feature is given, and what the Draw tool produces on a feature
# carrying no type at all.
const POLYGON := "polygon"
# No type at all, which is what a file written before 0.3.0 carries. It allows
# every kind, since nothing in the file said which one was meant.
const NONE := ""
const CIRCLE := "circle"

const ALL_KINDS := ["polygon", "polyline", "multipoint", "topology"]

# The colour a new feature starts in, before it holds anything.
const NONE_COLOR := Color.CHOCOLATE

# Id to name, allowed geometry kinds and default colour, in the order the type
# selector lists them.
const CATALOG := {
	"polygon": {"name": "Polygon", "kinds": ["polygon"], "color": Color.CHOCOLATE},
	"line": {"name": "Line", "kinds": ["polyline"], "color": Color.CRIMSON},
	"points": {"name": "Points", "kinds": ["multipoint"], "color": Color.GOLD},
	CIRCLE: {"name": "Circle", "kinds": ["polygon", "polyline"], "color": Color.DARK_TURQUOISE},
	"topology": {"name": "Topology", "kinds": ["topology"], "color": Color.MEDIUM_PURPLE},
}

# The type each geometry kind gives a feature that holds it.
const OF_KIND := {
	"polygon": "polygon",
	"polyline": "line",
	"multipoint": "points",
	"topology": "topology",
}


# The type a feature holding geometry of this kind has, given the type it
# carries. An empty kind is a feature holding nothing, which keeps the type it
# was given, since that is what decides how the tools draw into it; a carried
# type that does not hold the kind, or that the catalog does not know, gives way
# to the kind's own.
static func resolve(type_id: String, kind_name: String) -> String:
	if kind_name.is_empty():
		return type_id if CATALOG.has(type_id) else NONE
	if CATALOG.has(type_id) and allows(type_id, kind_name):
		return type_id
	return str(OF_KIND.get(kind_name, NONE))


static func label(type_id: String) -> String:
	return str(CATALOG[type_id]["name"]) if CATALOG.has(type_id) else ""


static func color(type_id: String) -> Color:
	return CATALOG[type_id]["color"] as Color if CATALOG.has(type_id) else NONE_COLOR


# The geometry kinds a feature of this type may hold, by name. A feature with no
# type yet may take any.
static func kinds(type_id: String) -> Array:
	return CATALOG[type_id]["kinds"] as Array if CATALOG.has(type_id) else ALL_KINDS


static func allows(type_id: String, kind_name: String) -> bool:
	return kind_name in kinds(type_id)
