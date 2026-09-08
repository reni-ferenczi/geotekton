class_name Backdrop
extends RefCounted

# The image a document wears in place of the built in Earth.
#
# The file is read from wherever the document points, not imported as a project
# resource, so any image on the machine can be dropped onto the planet. What
# comes back is either a texture or the reason there is none; a document naming
# an image that has since been moved still opens, showing the built in Earth and
# saying why. See Docs/Shader.md#the-backdrop-image.

# The formats a backdrop may be in: what the engine reads as a raster, plus SVG,
# which it rasterizes from the text of the file.
const EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg"]

# How many pixels across an SVG is rasterized to. Large enough to wrap a planet
# without the coastlines going soft, small enough to load in a moment.
const SVG_WIDTH := 2048.0

var texture: ImageTexture = null
var error: String = ""


# Read the image at a path. The result always answers: `texture` is null exactly
# when `error` says why.
static func load_from(path: String) -> Backdrop:
	var result := Backdrop.new()
	if path.is_empty():
		return result
	var extension := path.get_extension().to_lower()
	if not EXTENSIONS.has(extension):
		result.error = "%s is not an image Middle Earth reads (%s)" % [
			path.get_file(), ", ".join(EXTENSIONS)]
		return result
	if not FileAccess.file_exists(path):
		result.error = "The backdrop image %s is not there" % path
		return result

	var image := Image.new()
	var status: int
	if extension == "svg":
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			result.error = "Cannot read %s: %s" % [
				path, error_string(FileAccess.get_open_error())]
			return result
		# An SVG has no size of its own that a texture can use, so it is drawn
		# at a fixed width and whatever height its own proportions ask for.
		status = image.load_svg_from_string(file.get_as_text(), _svg_scale(file.get_as_text()))
	else:
		status = image.load(path)
	if status != OK:
		result.error = "Cannot read %s: %s" % [path, error_string(status)]
		return result

	result.texture = ImageTexture.create_from_image(image)
	return result


# How far to scale an SVG so that it comes out SVG_WIDTH pixels across. The
# width is read off the document; one that does not say falls back to a scale of
# 1, which is the size the file was drawn at.
static func _svg_scale(source: String) -> float:
	var found := RegEx.create_from_string(
		"<svg[^>]*?\\bwidth\\s*=\\s*[\"']([0-9.]+)").search(source)
	if found == null:
		return 1.0
	var width := found.get_string(1).to_float()
	return 1.0 if width <= 0.0 else SVG_WIDTH / width
