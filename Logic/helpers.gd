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

const ICON_ENABLE := 0
const ICON_REPEAT := 2
const ICON_INVERT := 3
const ICON_SINGLE := 4
const ICON_WRAP := 5
const ICON_RESIZE := 6
const ICON_PERMUTATION := 9
const ICON_ORIENTATION := 10


static var rule_options_atlas := Helpers.split_atlas_to_textures(preload("res://Assets/Icons/Generated/IconAtlas.png"), Vector2i(32, 32))


static func get_rule_option_icon(shape: int, show_icon: bool = true, enabled: bool = true) -> Texture2D:
	var index := shape + (ICON_SHOWN if show_icon else 0) + (0 if enabled else ICON_DISABLED)
	return rule_options_atlas[index]


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
