class_name FeatureIcon

# The built in glyphs a feature's tree row can carry, so that a mountain range
# and a coastline are told apart at a glance. See Docs/Properties.md.
#
# A glyph is one of the MiddleEarth icons, a PNG under DIR at whatever size it
# was painted. It is shrunk to SIZE on first use, the size of the group and
# rule icons beside it, so the tree and the selector draw it as is. FILES names
# the picture behind each id in CATALOG.
#
# A feature stores the id. Nothing else in the program reads it: the icon is
# for whoever is looking.

const DIR := "res://Assets/MiddleEarth Icons"

# The width and height a glyph is shown at.
const SIZE := 32

# No icon at all, which is what every feature carries until one is picked. The
# tree row then shows the rule icon, as it did before there were any.
const NONE := ""

# Id to name, in the order the Icon selector lists them.
const CATALOG := {
	"antarctica": "Antarctica",
	"africa": "Africa",
	"australia": "Australia",
	"eurasia": "Eurasia",
	"north_america": "North America",
	"mountain": "Mountain",
	"volcano": "Volcano",
	"heart": "Heart",
	"moon": "Moon",
	"shield": "Shield",
	"star": "Star",
}

# Id to the stem of its picture under DIR.
const FILES := {
	"antarctica": "Icons1-Features",
	"africa": "Icons1-Africa",
	"australia": "Icons1-Australia",
	"eurasia": "Icons1-Eurasia",
	"north_america": "Icons1-NorthAmerica",
	"mountain": "Icons1-Mountain",
	"volcano": "Icons1-Volcano",
	"heart": "Icons1-Heart",
	"moon": "Icons1-Moon",
	"shield": "Icons1-Shield",
	"star": "Icons1-Star",
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
		_textures[id] = _shrunk(id)
	return _textures[id]


# A picture under DIR shrunk to SIZE: done once, in software, rather than by
# the tree and the selector each time they draw it, which would come out ragged
# from a picture painted this much larger. It also keeps whatever is built from
# a row's icon, such as the drag preview, at SIZE. The texture is named as the
# caller says, which is how the automation port tells a row what it is showing.
static func shrunk(stem: String, name: String) -> Texture2D:
	var source := load("%s/%s.png" % [DIR, stem]) as Texture2D
	var image := source.get_image()
	if image.is_compressed():
		image.decompress()
	image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = name
	return texture


# A glyph, named after its id.
static func _shrunk(id: String) -> Texture2D:
	return shrunk(FILES[id], id)
