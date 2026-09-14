class_name Helpers


static func v2i_to_json(v: Vector2i) -> Variant:
	return {x=v.x, y=v.y}
	

static func v2i_from_json(data :Variant) -> Vector2i:
	return Vector2i(data["x"], data["y"])


static func split_atlas_to_images(atlas: Texture2D, tile_size: Vector2i) -> Array[Image]:
	var img := atlas.get_image()
	var count := img.get_size() / tile_size
	
	var tiles: Array[Image] = []
	for y in range(count.y):
		for x in range(count.x):
			var rc := Rect2i(x * tile_size.x, y * tile_size.y, tile_size.x, tile_size.y)
			var tile := img.get_region(rc)
			tiles.append(tile)
			
	return tiles


static func split_atlas_to_textures(atlas: Texture2D, tile_size: Vector2i) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for image in split_atlas_to_images(atlas, tile_size):
		textures.append(ImageTexture.create_from_image(image))
	return textures


static func checksum_image(img: Image, properties: Dictionary = {}) -> String:
	var data: PackedByteArray = img.get_data()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	if not properties.is_empty():
		ctx.update(JSON.stringify(properties).to_ascii_buffer())
	return ctx.finish().hex_encode()


static func checksum_text(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


static func generate_uuid_v4() -> String:
	var crypto = Crypto.new()
	# Generate 16 random bytes
	var bytes = crypto.generate_random_bytes(16)
	
	# Set the version (4) and variant (RFC 4122)
	# 0x40 at index 6, 0x80 at index 8
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	
	var hex = bytes.hex_encode()
	
	# Format: 8-4-4-4-12
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12)
	]


const ICON_ATLAS_COLUMNS := 18

const ICON_SHOWN := ICON_ATLAS_COLUMNS
const ICON_DISABLED := ICON_ATLAS_COLUMNS * 2

# Columns of the icon atlas. Repeat (2), invert (3), single (4), wrap (5) and
# resize (6) went with the tree row buttons they named in 0.2.0; permutation (9)
# and orientation (10) were never used here either. The icons stay in the atlas.
const ICON_ENABLE := 0


static var rule_options_atlas := Helpers.split_atlas_to_textures(preload("res://Assets/Icons/Generated/IconAtlas.png"), Vector2i(32, 32))


static func get_rule_option_icon(shape: int, show_icon: bool = true, enabled: bool = true) -> Texture2D:
	var index := shape + (ICON_SHOWN if show_icon else 0) + (0 if enabled else ICON_DISABLED)
	return rule_options_atlas[index]


#################################


# Colour pickers. Every place a colour is picked uses the same button, so the
# picker offers the same things wherever it is opened from. See Docs/Properties.md.

# What every button that opens a picker says. The feature tree's swatch adds
# what its right click does, since that is the one it has of its own.
const COLOR_TOOLTIP := "Pick a colour"
const SWATCH_TOOLTIP := COLOR_TOOLTIP + "\nRight click: the type's default"

# What the pickers offer as presets: the default colour of each feature type to
# start with, and every colour committed since the application started, so a
# palette built for one feature is a click away on the next. The list lives for
# the session and is not written to the settings file.
static var _color_presets: Array[Color] = []


static func color_presets() -> Array[Color]:
	if _color_presets.is_empty():
		for type_id in FeatureType.CATALOG:
			_color_presets.append(FeatureType.color(type_id))
	return _color_presets.duplicate()


# Offer a colour in every picker from now on, which is what committing one to a
# feature or a group does. A colour already there stays where it is rather than
# moving to the end.
static func remember_color(color: Color) -> void:
	var opaque := Color(color, 1.0)
	if opaque not in color_presets():
		_color_presets.append(opaque)


# A colour picker button showing all of Godot's picker: the screen sampler, the
# hex field, the presets, the colour modes and the sliders. Whether the alpha
# can be edited is left to the caller, since a row with an opacity box beside it
# keeps the alpha out of the picker.
static func color_button(button_name: String, tooltip: String) -> ColorPickerButton:
	var button := ColorPickerButton.new()
	button.name = button_name
	button.tooltip_text = tooltip
	var picker := button.get_picker()
	picker.sampler_visible = true
	picker.hex_visible = true
	picker.presets_visible = true
	picker.color_modes_visible = true
	picker.sliders_visible = true
	_offer_presets(picker)
	# The presets are shared and the picker's own copy is not, so it is brought
	# up to date every time it opens rather than when something else changed.
	button.get_popup().about_to_popup.connect(_offer_presets.bind(picker))
	return button


static func _offer_presets(picker: ColorPicker) -> void:
	var shown := picker.get_presets()
	for color in color_presets():
		if color not in shown:
			picker.add_preset(color)


#################################


const ATLAS_TILE_RECT := Rect2i(0, 0, 32, 32)

# Cache
const CACHE_MAX_LEN := 4000
static var tiles: Array[Image] = []
static var cache: Dictionary[int, CachedGraphics] = {}
static var atlas_texture: Texture2DArray


class CachedGraphics:
	var image: Image
	var texture: Texture2D


static func render_cell(color: Color) -> CachedGraphics:
	var cache_key := (color.r8 << 16) | (color.g8 << 8) | (color.b8 << 0)
	var cached := cache.get(cache_key) as CachedGraphics
	if cached != null:
		return cached

	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(color)

	var graphics = CachedGraphics.new()
	graphics.image = image
	graphics.texture = ImageTexture.create_from_image(image)

	if len(cache) >= CACHE_MAX_LEN:
		cache.clear()
		
	cache[cache_key] = graphics
	
	return graphics
