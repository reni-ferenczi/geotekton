class_name FeatureType

# What a feature is. The type follows the geometry the feature holds: a polygon
# is a Polygon, a polyline a Line, a multipoint Points and a line topology a
# Topology. Circle is the one type someone chooses, since a circle is drawn as a
# polygon or a polyline; the Circle tool gives it on commit. Middle Earth is a
# world building tool and does not carry the GPGIM over. See Docs/Properties.md.
#
# A type is stored by its id, which is also what the file holds. The kinds are
# the names Feature.KIND_NAMES uses, so the catalog is written in the same
# vocabulary as the file and needs nothing from Feature to be read.

# The type of a feature holding nothing yet. It allows every kind, since the
# first shape committed is what decides the type.
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
# carries. An empty kind is a feature holding nothing, which has no type; a
# carried type that does not hold the kind, or that the catalog does not know,
# gives way to the kind's own.
static func resolve(type_id: String, kind_name: String) -> String:
	if kind_name.is_empty():
		return NONE
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
