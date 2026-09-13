class_name ViewSettings
extends RefCounted

# How the scene around the features is drawn: the background, the graticule, the
# light and the backdrop image on the planet, along with which classes of
# geometry are shown at all and what colour the features come out.
#
# These belong to a document rather than to whoever is at the keyboard, because
# a map of a world is drawn the way its author chose, so they are saved with the
# file. The preferences hold a second copy of the same block, which is what a
# new document starts from; see Config.get_view_defaults().
#
# Nothing here is on the undo stack. A view setting says how the document is
# looked at, not what it holds, so undo leaves it alone; it does dirty the
# document, since it is written to the file. See Docs/Persistence.md.

# The scene as it was drawn before any of this was settable, so a document that
# says nothing about its view looks the way every file did until 0.6.0.
const DEFAULT_BACKGROUND := Color(0.0, 0.0, 0.0, 1.0)
const DEFAULT_GRATICULE_COLOR := Color(1.0, 1.0, 1.0, 0.3333)
const DEFAULT_GRATICULE_SPACING := 15.0
const DEFAULT_LIGHT := Vector2(0.0, 0.0)
const DEFAULT_AMBIENT := 0.0
const DEFAULT_BACKDROP_OPACITY := 1.0

# What the graticule may be spaced at, in degrees. The lower end keeps the
# window from being filled with lines; the upper end still draws the equator and
# one meridian.
const MIN_SPACING := 1.0
const MAX_SPACING := 90.0

# How far the light may be lifted above or below the line of sight. Straight
# above would leave the direction it is turned about undefined, so it stops a
# degree short of the pole.
const MAX_ELEVATION := 89.0

# How much light reaches the side facing away from the light. Zero is the black
# night side the scene has always had; one is a planet with no night at all.
const MIN_AMBIENT := 0.0
const MAX_AMBIENT := 1.0

var background_color: Color = DEFAULT_BACKGROUND
var star_field: bool = true

var graticule_color: Color = DEFAULT_GRATICULE_COLOR
var graticule_spacing: float = DEFAULT_GRATICULE_SPACING

# Where the light comes from, as an elevation and an azimuth in degrees away
# from the camera: (0, 0) shines straight down the line of sight, which is where
# the scene has always put it. The direction is fixed to the view rather than to
# the planet, so turning the globe carries the terminator across it.
var light_direction: Vector2 = DEFAULT_LIGHT
var ambient: float = DEFAULT_AMBIENT

# An image drawn on the planet in place of the built in Earth. The path is
# relative to the project file when the image sits beside it; see
# Document.resolve_backdrop().
var backdrop_path: String = ""
var backdrop_opacity: float = DEFAULT_BACKDROP_OPACITY
var backdrop_visible: bool = true

# The classes of geometry the View menu has switched off, by the names in
# Styling.CLASSES. Kept as what is hidden rather than what is shown, so an empty
# list is everything drawn and a class this version has never heard of cannot
# quietly hide something.
var hidden_classes: PackedStringArray = PackedStringArray()

# What colour the features come out is not here: since 0.10.0 it is the style
# of the root group. See GroupStyle.


func clone() -> ViewSettings:
	return ViewSettings.from_json(to_json())


func to_json() -> Dictionary:
	return {
		"background_color": _color_to_json(background_color),
		"star_field": star_field,
		"graticule_color": _color_to_json(graticule_color),
		"graticule_spacing": graticule_spacing,
		"light_direction": [light_direction.x, light_direction.y],
		"ambient": ambient,
		"backdrop_path": backdrop_path,
		"backdrop_opacity": backdrop_opacity,
		"backdrop_visible": backdrop_visible,
		"hidden_classes": Array(hidden_classes),
	}


# Read a block back, taking the default for anything it does not say. A file
# written before 0.6.0 carries no block at all and gets every default, which is
# the scene as it was drawn then.
static func from_json(data: Variant) -> ViewSettings:
	var settings := ViewSettings.new()
	if data is not Dictionary:
		return settings
	settings.background_color = _color_from_json(
		data.get("background_color"), DEFAULT_BACKGROUND)
	settings.star_field = bool(data.get("star_field", true))
	settings.graticule_color = _color_from_json(
		data.get("graticule_color"), DEFAULT_GRATICULE_COLOR)
	settings.graticule_spacing = clampf(
		float(data.get("graticule_spacing", DEFAULT_GRATICULE_SPACING)),
		MIN_SPACING, MAX_SPACING)
	var light: Variant = data.get("light_direction")
	if light is Array and (light as Array).size() >= 2:
		settings.light_direction = clamp_light(Vector2(float(light[0]), float(light[1])))
	settings.ambient = clampf(
		float(data.get("ambient", DEFAULT_AMBIENT)), MIN_AMBIENT, MAX_AMBIENT)
	settings.backdrop_path = str(data.get("backdrop_path", ""))
	settings.backdrop_opacity = clampf(
		float(data.get("backdrop_opacity", DEFAULT_BACKDROP_OPACITY)), 0.0, 1.0)
	settings.backdrop_visible = bool(data.get("backdrop_visible", true))
	var hidden: Variant = data.get("hidden_classes")
	if hidden is Array:
		for name in hidden:
			settings.hide_class(str(name), true)
	return settings


### Which classes of geometry are drawn


func shows_class(class_id: String) -> bool:
	return not (class_id in hidden_classes)


# Switch a class off or back on. A name that is not a class at all is ignored,
# so a file from a later version cannot hide geometry this one cannot show again.
func hide_class(class_id: String, hidden: bool) -> void:
	if not Styling.CLASSES.has(class_id):
		return
	var at := hidden_classes.find(class_id)
	if hidden and at < 0:
		hidden_classes.append(class_id)
	elif not hidden and at >= 0:
		hidden_classes.remove_at(at)


# How many divisions of the whole planet the graticule spacing comes to, which
# is what planet.gdshader counts in: longitude first, then latitude.
func graticule_split() -> Vector2:
	return Vector2(360.0 / graticule_spacing, 180.0 / graticule_spacing)


### The light
#
# The direction is an elevation above the line of sight and an azimuth around
# it, both in degrees, and it is fixed to the view: (0, 0) shines straight from
# the camera, which is where the scene has always put the light. The two
# functions below turn that into a direction in the scene and back, which is how
# the Light tool takes a drag on the globe and stores what it means.


# Which way the light comes from, in the frame the scene is laid out in: +Z is
# towards the camera, +X to the right and +Y up.
func light_vector() -> Vector3:
	var elevation := deg_to_rad(light_direction.x)
	var azimuth := deg_to_rad(light_direction.y)
	var cos_elevation := cos(elevation)
	return Vector3(
		sin(azimuth) * cos_elevation, sin(elevation), cos(azimuth) * cos_elevation)


# The elevation and azimuth of a direction in the scene, which is light_vector()
# the other way round.
static func light_from_vector(direction: Vector3) -> Vector2:
	if direction.length_squared() < 1e-12:
		return DEFAULT_LIGHT
	var unit := direction.normalized()
	return clamp_light(Vector2(
		rad_to_deg(asin(clampf(unit.y, -1.0, 1.0))),
		rad_to_deg(atan2(unit.x, unit.z))))


# An elevation the light can actually be turned to, and an azimuth in the range
# every other angle in the application is given in.
static func clamp_light(direction: Vector2) -> Vector2:
	return Vector2(
		clampf(direction.x, -MAX_ELEVATION, MAX_ELEVATION),
		fposmod(direction.y + 180.0, 360.0) - 180.0)


static func _color_to_json(color: Color) -> Array:
	return [color.r, color.g, color.b, color.a]


static func _color_from_json(value: Variant, fallback: Color) -> Color:
	if value is not Array or (value as Array).size() < 3:
		return fallback
	var list: Array = value
	return Color(
		float(list[0]), float(list[1]), float(list[2]),
		float(list[3]) if list.size() > 3 else 1.0)
