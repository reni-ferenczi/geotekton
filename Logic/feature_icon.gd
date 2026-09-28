class_name FeatureIcon

# The built in glyphs a feature's tree row can carry, so that a mountain range
# and a coastline are told apart at a glance. See Docs/Properties.md.
#
# A glyph is one of the Geotekton icons, a PNG under DIR at whatever size it
# was painted. It is shrunk to SIZE on first use, the size of the group and
# rule icons beside it, so the tree and the selector draw it as is. FILES names
# the picture behind each id in CATALOG.
#
# A feature stores the id. Nothing else in the program reads it: the icon is
# for whoever is looking.

const DIR := "res://Assets/Geotekton Icons"

# The width and height a glyph is shown at.
const SIZE := 32

# No icon at all, which is what every feature carries until one is picked. The
# tree row then shows its type's picture, see for_type(), else the rule icon.
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
	"points": "Points",
	"line": "Line",
	"circle": "Circle",
	"hotspot": "Hotspot",
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
	"points": "Icons1-Points",
	"line": "Icons1-Line",
	"circle": "Icons1-Circle",
	"hotspot": "Icons1-Hotspot",
}

# FeatureType id to the stem of the picture a feature of that type shows while
# it carries no icon of its own. A type not listed, such as a Topology, shows
# the rule icon. The texture is named after its stem, as the rule icon is.
const TYPE_FILES := {
	"polygon": "Icons1-Features",
	"line": "Icons1-Line",
	"points": "Icons1-Points",
	"circle": "Icons1-Circle",
	"hotspot": "Icons1-Hotspot",
}

# The pictures a group's row can show in place of the plain folder, id to
# name, in the order the selector lists them. Each is the PNG under
# FOLDER_DIR named after it. Placeholders for now: to replace one, overwrite
# its file; to add one, drop the PNG in and list it here (GP-0146).
const FOLDER_DIR := DIR + "/Folders"
const FOLDERS := {
	"red": "Red",
	"green": "Green",
	"blue": "Blue",
	"purple": "Purple",
	"gray": "Gray",
}

static var _textures: Dictionary[String, Texture2D] = {}
static var _folder_textures: Dictionary[String, Texture2D] = {}
static var _type_textures: Dictionary[String, Texture2D] = {}


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


# The folder picture an id names, or null for the plain folder and for an id
# this version does not know.
static func folder_texture(id: String) -> Texture2D:
	if not FOLDERS.has(id):
		return null
	if not _folder_textures.has(id):
		_folder_textures[id] = shrunk("Folders/%s" % FOLDERS[id], id)
	return _folder_textures[id]


# The picture a feature of the type shows when it has no glyph, or null for a
# type without one.
static func for_type(type_id: String) -> Texture2D:
	if not TYPE_FILES.has(type_id):
		return null
	if not _type_textures.has(type_id):
		_type_textures[type_id] = shrunk(TYPE_FILES[type_id], TYPE_FILES[type_id])
	return _type_textures[type_id]


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
