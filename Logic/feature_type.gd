class_name FeatureType

# What a feature is. A type names the geometry kinds a feature of it may hold
# and the colour a new one starts in; nothing else about it is interpreted yet.
# This small catalog stands in for the GPGIM, which Middle Earth does not carry
# over. See Docs/Properties.md.
#
# A type is stored by its id, which is also what the file holds. The kinds are
# the names Feature.KIND_NAMES uses, so the catalog is written in the same
# vocabulary as the file and needs nothing from Feature to be read.

# The type a feature has until someone picks one. It allows every kind, so a
# feature can be drawn before it is classified and an older file, which carries
# no type at all, cannot arrive holding a kind its type forbids.
const UNCLASSIFIED := "unclassified"

const ALL_KINDS := ["polygon", "polyline", "multipoint"]

# Id to name, allowed geometry kinds and default colour, in the order the type
# selector lists them.
const CATALOG := {
	UNCLASSIFIED: {"name": "Unclassified", "kinds": ALL_KINDS, "color": Color.CHOCOLATE},
	"craton": {"name": "Craton", "kinds": ["polygon"], "color": Color.TAN},
	"terrane": {"name": "Terrane", "kinds": ["polygon"], "color": Color.OLIVE},
	"coastline": {"name": "Coastline", "kinds": ["polygon", "polyline"], "color": Color.STEEL_BLUE},
	"ridge": {"name": "Ridge", "kinds": ["polyline"], "color": Color.CRIMSON},
	"marker": {"name": "Marker", "kinds": ["multipoint"], "color": Color.GOLD},
}


# The id as it can be used, so an unknown one from a file or a script becomes
# the unclassified type rather than a feature nothing can describe.
static func normalize(type_id: String) -> String:
	return type_id if CATALOG.has(type_id) else UNCLASSIFIED


static func label(type_id: String) -> String:
	return str(CATALOG[normalize(type_id)]["name"])


static func color(type_id: String) -> Color:
	return CATALOG[normalize(type_id)]["color"] as Color


# The geometry kinds a feature of this type may hold, by name.
static func kinds(type_id: String) -> Array:
	return CATALOG[normalize(type_id)]["kinds"] as Array


static func allows(type_id: String, kind_name: String) -> bool:
	return kind_name in kinds(type_id)
