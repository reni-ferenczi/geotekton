class_name FeatureIcon

# The built in glyphs a feature's tree row can carry, so that a mountain range
# and a coastline are told apart at a glance. See Docs/Properties.md.
#
# What a glyph has to be: an SVG with width="32" height="32" on its root, so it
# rasterizes to 32 by 32 like the group and rule icons beside it, drawn in white
# strokes on transparent so the tree can tint it. The viewBox is free. The file
# goes into Assets/Icons/Features with the default import (svg/scale=1.0) and
# its stem is named in CATALOG below.
#
# A feature stores the id, which is also the file stem and what the file holds.
# Nothing else in the program reads it: the icon is for whoever is looking.

const DIR := "res://Assets/Icons/Features"

# No icon at all, which is what every feature carries until one is picked. The
# tree row then shows the rule icon, as it did before there were any.
const NONE := ""

# Id to name, in the order the Icon selector lists them.
const CATALOG := {
	"continent": "Continent",
	"craton": "Craton",
	"island": "Island",
	"ocean": "Ocean",
	"sea": "Sea",
	"mountain": "Mountain",
	"volcano": "Volcano",
	"rift": "Rift",
	"ridge": "Ridge",
	"trench": "Trench",
	"plateau": "Plateau",
	"basin": "Basin",
	"river": "River",
	"ice": "Ice",
	"crater": "Crater",
	"marker": "Marker",
}

static var _textures: Dictionary[String, Texture2D] = {}


static func label(id: String) -> String:
	return str(CATALOG.get(id, ""))


# The glyph an id names, or null for no icon and for an id this version does not
# know, which is what a hand written file can carry. A null is the caller's cue
# to show what it showed before there were icons.
static func texture(id: String) -> Texture2D:
	if not CATALOG.has(id):
		return null
	if not _textures.has(id):
		_textures[id] = load("%s/%s.svg" % [DIR, id]) as Texture2D
	return _textures[id]
