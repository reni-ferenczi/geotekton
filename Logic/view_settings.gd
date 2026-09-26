class_name ViewSettings
extends RefCounted

# How the scene around the features is drawn: the background, the grid, the
# light, the planet's own color and the raster on it, along with which classes
# of geometry are shown at all and what colour the features come out.
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
const DEFAULT_GRID_COLOR := Color(1.0, 1.0, 1.0, 0.3333)
const DEFAULT_GRID_SPACING := 15.0
const DEFAULT_LIGHT := Vector2(0.0, 0.0)
const DEFAULT_AMBIENT := 0.0
const DEFAULT_RASTER_OPACITY := 1.0

# The palettes the crust may be colored from, in the order the View settings
# dialog lists them, and the one a document starts with.
const CRUST_PALETTES := {"blue": "Blue", "rainbow": "Rainbow", Palette.RAMP: "Custom ramp"}
const DEFAULT_CRUST_PALETTE := "blue"
const DEFAULT_CRUST_RAMP: Array[Color] = [Color(0.776, 0.859, 0.937),
	Color(0.275, 0.510, 0.706), Color(0.063, 0.204, 0.380)]

# The planet under any raster: an ocean blue. Unlike the scene settings above,
# this is not how files were drawn before it existed; those carried the built in
# Earth, and Document.migrate() gives it back to them as their raster.
const DEFAULT_PLANET_COLOR := Color(0.16, 0.36, 0.60)

# The image the developers call the built in Earth, which a raster path may name
# like any file on disk.
const BUILT_IN_EARTH := "res://Assets/Textures/Earth.jpg"

# What the grid may be spaced at, in degrees. The lower end keeps the
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

var grid_color: Color = DEFAULT_GRID_COLOR
var grid_spacing: float = DEFAULT_GRID_SPACING

# Where the light comes from, as an elevation and an azimuth in degrees away
# from the camera: (0, 0) shines straight down the line of sight, which is where
# the scene has always put it. The direction is fixed to the view rather than to
# the planet, so turning the globe carries the terminator across it.
var light_direction: Vector2 = DEFAULT_LIGHT
var ambient: float = DEFAULT_AMBIENT

# The color of the planet where no raster covers it. Always opaque: the planet
# is never see-through, so whatever alpha is given is dropped.
var planet_color: Color = DEFAULT_PLANET_COLOR:
	set(value):
		planet_color = Color(value, 1.0)

# An image drawn over the planet color. Empty is none. The path is relative to
# the project file when the image sits beside it, and a res:// path names an
# image the application ships, such as BUILT_IN_EARTH; see
# Document.resolve_raster().
var raster_path: String = ""
var raster_opacity: float = DEFAULT_RASTER_OPACITY
var raster_visible: bool = true

# The classes of geometry the View menu has switched off, by the names in
# Styling.CLASSES. Kept as what is hidden rather than what is shown, so an empty
# list is everything drawn and a class this version has never heard of cannot
# quietly hide something.
var hidden_classes: PackedStringArray = PackedStringArray()

# What colour the features come out is not here: since 0.10.0 it is the style
# of the root group. See GroupStyle. The sea floor is the exception, since no
# group style reaches it: the colors of every ridge and crust are here.

# The color every ridge is drawn in. A document that says nothing takes the
# Line color from the preferences, which is what a ridge was given before.
var ridge_color: Color = FeatureType.color(FeatureType.LINE)

# What the crust is colored from, by its age: a key of Palette.BUILT_IN, or
# Palette.RAMP for crust_ramp_colors. Spread from 0 My to the oldest crust in
# the document; see Styling.crust_color().
var crust_palette: String = DEFAULT_CRUST_PALETTE

# The custom ramp, youngest first. It starts as the Blue palette's stops.
var crust_ramp_colors: Array[Color] = DEFAULT_CRUST_RAMP.duplicate()

# The color of the isochrons and flowlines drawn over every crust.
var crust_lines_color: Color = FeatureType.color(FeatureType.CRUST_LINES)


func clone() -> ViewSettings:
	return ViewSettings.from_json(to_json())


func to_json() -> Dictionary:
	return {
		"background_color": _color_to_json(background_color),
		"star_field": star_field,
		"grid_color": _color_to_json(grid_color),
		"grid_spacing": grid_spacing,
		"light_direction": [light_direction.x, light_direction.y],
		"ambient": ambient,
		"planet_color": _color_to_json(planet_color),
		"raster_path": raster_path,
		"raster_opacity": raster_opacity,
		"raster_visible": raster_visible,
		"hidden_classes": Array(hidden_classes),
		"ridge_color": _color_to_json(ridge_color),
		"crust_palette": crust_palette,
		"crust_ramp_colors": crust_ramp_colors.map(func(color: Color) -> Array: return _color_to_json(color)),
		"crust_lines_color": _color_to_json(crust_lines_color),
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
	settings.grid_color = _color_from_json(
		data.get("grid_color"), DEFAULT_GRID_COLOR)
	settings.grid_spacing = clampf(
		float(data.get("grid_spacing", DEFAULT_GRID_SPACING)),
		MIN_SPACING, MAX_SPACING)
	var light: Variant = data.get("light_direction")
	if light is Array and (light as Array).size() >= 2:
		settings.light_direction = clamp_light(Vector2(float(light[0]), float(light[1])))
	settings.ambient = clampf(
		float(data.get("ambient", DEFAULT_AMBIENT)), MIN_AMBIENT, MAX_AMBIENT)
	settings.planet_color = _color_from_json(
		data.get("planet_color"), DEFAULT_PLANET_COLOR)
	settings.raster_path = str(data.get("raster_path", ""))
	settings.raster_opacity = clampf(
		float(data.get("raster_opacity", DEFAULT_RASTER_OPACITY)), 0.0, 1.0)
	settings.raster_visible = bool(data.get("raster_visible", true))
	var hidden: Variant = data.get("hidden_classes")
	if hidden is Array:
		for name in hidden:
			settings.hide_class(str(name), true)
	settings.ridge_color = _color_from_json(data.get("ridge_color"), settings.ridge_color)
	var palette := str(data.get("crust_palette", DEFAULT_CRUST_PALETTE))
	settings.crust_palette = palette if CRUST_PALETTES.has(palette) else DEFAULT_CRUST_PALETTE
	var ramp: Variant = data.get("crust_ramp_colors")
	if ramp is Array and (ramp as Array).size() >= Palette.MIN_RAMP_COLORS:
		settings.crust_ramp_colors.assign((ramp as Array).map(
			func(value: Variant) -> Color: return _color_from_json(value, Color.BLACK)))
	settings.crust_lines_color = _color_from_json(
		data.get("crust_lines_color"), settings.crust_lines_color)
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


# How many divisions of the whole planet the grid spacing comes to, which
# is what planet.gdshader counts in: longitude first, then latitude.
func grid_split() -> Vector2:
	return Vector2(360.0 / grid_spacing, 180.0 / grid_spacing)


### The light
#
# The direction is an elevation above the line of sight and an azimuth around
# it, both in degrees, and it is fixed to the view: (0, 0) shines straight from
# the camera, which is where the scene has always put the light. The View
# settings panel sets both angles; light_vector() turns them into a direction in
# the scene, and clamp_light() keeps them in range.


# Which way the light comes from, in the frame the scene is laid out in: +Z is
# towards the camera, +X to the right and +Y up.
func light_vector() -> Vector3:
	var elevation := deg_to_rad(light_direction.x)
	var azimuth := deg_to_rad(light_direction.y)
	var cos_elevation := cos(elevation)
	return Vector3(
		sin(azimuth) * cos_elevation, sin(elevation), cos(azimuth) * cos_elevation)


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
