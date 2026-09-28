extends Node3D
class_name Planet

# What one entry of the geometry data texture draws. The values are the ones
# the shader switches on, so they must match the kinds listed in planet.gdshader.
# SAMPLE is a hotspot track sample: a POINT drawn SAMPLE_DOT_SCALE the size.
# CIRCLE is one ring of a circle, drawn from its center and radius.
enum Primitive { TRIANGLE = 0, SEGMENT = 1, POINT = 2, SAMPLE = 3, CIRCLE = 4 }

# How large a hotspot sample dot is against a multipoint marker, and how wide
# the pole cross is against a feature line. planet.gdshader holds both. The
# cross is as wide as a feature line: it was half of one until 0.29.0 halved
# the line, and a tool's marker had no reason to get thinner with it.
const SAMPLE_DOT_SCALE := 0.5
const BOLD_SCALE := 1.0

# Radius of the globe, in the units planet.tscn is laid out in. The SphereMesh
# is set to it in _ready(), and PlanetView casts a ray against a sphere of the
# same radius, so the surface the pointer meets is the surface the pixel shows.
const GLOBE_RADIUS := 0.5

# How close a click counts as a hit on a polyline or a multipoint, as a chord
# length on the unit sphere. A little wider than what is drawn, so a thin line
# and a small marker stay easy to pick.
const LINE_HIT_WIDTH := 0.02
const POINT_HIT_RADIUS := 0.025

# What the outline overlay draws its vertex markers and its lines at before the
# preferences scale them. Both match the uniform defaults in planet.gdshader.
# The markers were twice this until 0.29.0; see Config.get_vertex_marker_scale().
const DEFAULT_DOT_RADIUS := 0.003
const DEFAULT_LINE_WIDTH := 0.002

# What a feature's lines are drawn at before Feature.line_scale(), from their
# middle to their edge as a chord: planet.gdshader's geometry_line_width. Twice
# this until 0.29.0; see Config.get_default_line_width().
const GEOMETRY_LINE_WIDTH := 0.006

# What a child of the selected feature is traced in, when the View menu
# asks for it, and what tints its row in the tree. planet.gdshader
# holds the same color, linearized, as CHILD_COLOR.
const CHILD_COLOR := Color(1.0, 0.5, 0.0)

# The same for the parent and the siblings of the selected feature, with View >
# Highlight parent and siblings on: magenta and lime, apart from the orange so
# all three can be on at once. planet.gdshader holds them linearized.
const PARENT_COLOR := Color(1.0, 0.25, 0.85)
const SIBLING_COLOR := Color(0.55, 1.0, 0.2)

# How a feature is related to the selected one, what row 4 of feature_data
# carries for the shader.
enum Relation { NONE = 0, CHILD = 1, PARENT = 2, SIBLING = 3 }

# What the feature picked as the parent to follow is traced in while the pick
# is on, until Couple takes it. planet.gdshader holds it linearized.
const CANDIDATE_COLOR := Color(0.2, 0.9, 1.0)

# Style of one part of the outline overlay. Matches planet.gdshader.
enum OutlineStyle {
	OPEN = 0,           # a line from the first vertex to the last
	CLOSED_PREVIEW = 1, # closed, with the closing segment drawn faintly
	POINTS = 2,         # the vertex markers only, no segments
	CLOSED = 3,         # closed, with every segment drawn the same
	OUTLINE = 4,        # closed like CLOSED, with no vertex markers
	MARKERS = 5,        # the vertex markers only, drawn larger
	CHILD = 6,          # closed like OUTLINE, in CHILD_COLOR
	BOLD = 7,           # open like OPEN, BOLD_SCALE times a feature line, no markers
	CIRCLE = 8,         # a center and a point of the rim, the circle drawn like CLOSED, no markers
	OPEN_LINE = 9,      # open like OPEN, in the same white and width, with no markers
	REFUSED = 10,       # open like OPEN, markers and all, in red: a cut the Split tool refused
	PARENT = 11,        # closed like CHILD, in PARENT_COLOR
	SIBLING = 12,       # closed like CHILD, in SIBLING_COLOR
	CANDIDATE = 13,     # closed like OUTLINE, wider than a feature line, in CANDIDATE_COLOR
}

# The map mesh with the sheet of a projection half a unit tall, which is what a
# rectangular one wants. Its local x runs across the sheet and its local z down
# it; _apply_projection() scales that z by the projection's own extent, so the
# mesh is exactly as tall as the projection draws and its UV covers the sheet
# and nothing else.
const MAP_BASIS := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

@export var show_map: bool = false;
@export var projection: MapProjection.Kind = MapProjection.Kind.RECTANGULAR;
@export_range(-90, 90, 1.0, "Latitude") var lat: float = 0.0;
@export_range(-180, 180, 1.0, "Longitude") var lon: float = 0.0;
# How far the view is turned clockwise about the point it looks at. The camera
# is what carries it, in PlanetView, so it turns the map and the globe alike.
@export_range(-180, 180, 1.0, "Angle") var angle: float = 0.0;

@onready var globe = $Globe;
@onready var map = $Map;
@onready var background: MeshInstance3D = $Background;
@onready var sun: DirectionalLight3D = $DirectionalLight3D;


func _ready() -> void:
	var sphere: SphereMesh = globe.mesh
	sphere.radius = GLOBE_RADIUS
	sphere.height = GLOBE_RADIUS * 2.0


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	globe.visible = not show_map
	map.visible = show_map

	if globe:
		globe.rotation = Vector3(deg_to_rad(lat), deg_to_rad(180 - lon), 0.0)
	_apply_projection()


# Shape the map mesh for the projection it draws and tell the shader which one
# that is. The sheet is always two units wide and as tall as the projection asks
# for, so the fragment shader turns UV into a point of the sheet the same way
# whatever is selected, and MapProjection.inverse() takes it from there.
func _apply_projection() -> void:
	var extent := MapProjection.extent(projection)
	map.transform = Transform3D(
		Basis(MAP_BASIS.x, MAP_BASIS.y, MAP_BASIS.z * extent), Vector3.ZERO)
	var material: ShaderMaterial = map.get_surface_override_material(0)
	material.set_shader_parameter("projection", int(projection))
	material.set_shader_parameter("map_extent", extent)
	material.set_shader_parameter("map_centre", Vector2(deg_to_rad(lat), deg_to_rad(lon)))


# How the scene around the features is drawn: the star field behind the planet,
# the planet's own color, the grid over it and where the light comes from. The rest of the block —
# the background colour and the ambient level — belongs to the environment,
# which PlanetView owns; see PlanetView.apply_view_settings().
func apply_view_settings(settings: ViewSettings) -> void:
	background.visible = settings.star_field
	# The light shines along its own -Z, so it faces the direction the light
	# travels in, which is the way it comes from turned round.
	sun.basis = Basis.looking_at(-settings.light_vector(), Vector3.UP)
	for material in [
		globe.get_surface_override_material(0), map.get_surface_override_material(0)]:
		# Linearized for the same reason the feature colours are; see set_geometry().
		material.set_shader_parameter("color", settings.grid_color.srgb_to_linear())
		# Not linearized here: the uniform is a source_color, which the engine
		# linearizes itself.
		material.set_shader_parameter("planet_color", settings.planet_color)
		material.set_shader_parameter("split", settings.grid_split())


# Put an image over the planet color, at the opacity the document asks for. A
# null texture or an opacity of zero leaves the flat color, which is what a
# document naming no image comes to.
func set_raster(texture: Texture2D, opacity: float) -> void:
	for material in [
		globe.get_surface_override_material(0), map.get_surface_override_material(0)]:
		material.set_shader_parameter("raster_tex", texture)
		material.set_shader_parameter("raster_opacity", 0.0 if texture == null else opacity)


# The map sheet lies in the x-y plane through the middle of the scene, x across
# it and y up it, which is what MAP_BASIS puts it there for. These two hold the
# whole of that convention: PlanetView goes through them to turn a click into a
# point of the sheet and a point of the sheet back into a pixel.
static func map_to_scene(plane: Vector2) -> Vector3:
	return Vector3(plane.x, plane.y, 0.0)


static func scene_to_map(point: Vector3) -> Vector2:
	return Vector2(point.x, point.y)


## Feature geometry rendering


# The flattened geometry of a feature tree, ready for the shader and for the hit
# test. The primitives are in each feature's own frame and change only when the
# tree does; where a feature sits at the current time is one rotation per
# feature, so a step of an animation re-uploads that small part alone and leaves
# the vertices where they were put.
# How wide the data textures are. A texture holds one entry per texel along a
# row and wraps onto the next group of rows past this, so an entry of `rows`
# texels at index i is at (i % TEXTURE_WRAP, i / TEXTURE_WRAP * rows + row);
# see _at(). 16,384 is the widest and tallest a desktop device is required to
# make a texture, which is what a document past it ran into before (GP-0030).
const TEXTURE_WRAP := 4096

# How many primitives one document is drawn with: as many as the two rows of
# each fit into the tallest texture a device has to make. Whatever does not fit
# is left out rather than the window standing still, and the feature tree still
# holds all of it.
const MAX_PRIMITIVES := TEXTURE_WRAP * (16384 / 2)

# The limit collect_geometry() holds a document to. MAX_PRIMITIVES, except in a
# test that wants to reach it without building tens of millions of primitives.
static var primitive_limit := MAX_PRIMITIVES

# How many primitives the shader takes as one block behind one cap. Small enough
# that a block of a large polygon is a small patch of it, large enough that the
# blocks stay few against the primitives; see Docs/Shader.md#skipping-what-is-far.
const BLOCK_SIZE := 32


class Geometry extends RefCounted:
	# One entry per primitive: { "kind": Primitive, "verts": Array of
	# Vector2(latitude, longitude) in degrees in the feature's own frame,
	# "feature": Feature, "index": int into features }. A CIRCLE's verts are
	# its center followed by its ring, which is what the cap is built from, and
	# it carries "radius" in degrees as well. Every
	# primitive of one column is contiguous, which is what lets the shader and
	# the hit test look its rotation up once instead of once per primitive.
	var primitives: Array = []

	# The feature each column of the arrays below belongs to, in the order they
	# were first met, and the column each feature was first given. Where a
	# feature sits, whether it is shown and what colour it comes out are all
	# answered per column. A feature takes one column, except a crust, which
	# takes one per band so that the age ramp can colour each band on its own;
	# `bands` then holds the age of the crust in that band.
	var features: Array[Feature] = []
	var index_of := {}
	var bands := {}

	# How many features were left out because MAX_PRIMITIVES was reached.
	var dropped: int = 0

	# For each column, the first column whose feature moves exactly as this
	# one does: the same keyframes and no coupling. resolve() works a rotation
	# out once for all of them. A GPlates import gives every feature of a plate
	# the plate's whole history, so thousands of features share a few hundred
	# motions (GP-0030). A column that shares with none points at itself.
	var same_motion: Array[int] = []

	# Group the columns by the keyframes they move by; see same_motion.
	func find_same_motion() -> void:
		same_motion.resize(features.size())
		var first := {}
		for index in features.size():
			var node: Feature = features[index]
			same_motion[index] = index
			if not node.couplings.is_empty() or node.keyframes.size() < 2:
				continue
			var motion := node.keyframes.map(func(keyframe: Keyframe) -> Array:
				return [keyframe.time, keyframe.rotation])
			same_motion[index] = first.get_or_add(motion, index)

	# Whether the tree holds a topology or a hotspot, whose vertices move with
	# the time, so a new time needs the geometry collected again rather than
	# only resolved. Worked out once, when the geometry is collected, since the
	# tree cannot change without collecting it again.
	var rebuilt_with_time: bool = false

	# Where each column's primitives sit in the list, as a half open range.
	# Every primitive of one column is contiguous, so the hit test can walk one
	# feature or skip all of it.
	var starts: Array[int] = []
	var ends: Array[int] = []

	# A cap holding every primitive of one column, in that feature's own frame:
	# the centre of the cap, and the cosine of its angular radius. A point whose
	# dot product with the centre falls under the cosine is outside everything
	# that feature draws, so the hit test throws the feature away with one
	# multiply instead of walking its triangles.
	#
	# A cosine of -1 is a cap that holds the whole sphere, which is what a
	# feature wider than a hemisphere gets: no cap smaller than everything would
	# hold it, and the hit test then walks it as it did before caps existed.
	var cap_centres: Array[Vector3] = []
	var cap_cosines: Array[float] = []

	# What the shader skips with (GP-0023): a cap around each column's
	# primitives and around each block of up to BLOCK_SIZE of them, in the
	# feature's own frame, as the centre and the angular radius, with nothing
	# added for the click tolerance. The shader widens them by what a line or a
	# marker is drawn at, which the uniforms say. An angle of PI is a cap that
	# holds the whole sphere. Each column's blocks run from block_starts to
	# block_ends, and each block covers the primitives from block_first to
	# block_last, a half open range, in column order.
	var draw_centres: Array[Vector3] = []
	var draw_angles: Array[float] = []
	var block_starts: Array[int] = []
	var block_ends: Array[int] = []
	var block_centres: Array[Vector3] = []
	var block_angles: Array[float] = []
	var block_first: Array[int] = []
	var block_last: Array[int] = []

	# Where each feature is and whether it is there at all, at the time resolve()
	# was last called for. One entry per column, in the same order.
	var bases: Array[Basis] = []
	var shown: Array[bool] = []
	var time: float = 0.0

	# The color each column is drawn in, as the active style gave it, in sRGB
	# with the opacity in alpha, a band of a crust through the age ramp. One
	# entry per column, in the same order.
	var colors: Array[Color] = []

	# The color each feature's lines are drawn in, which is the color above for
	# everything but a crust; see Styling.line_color_of(). One entry per
	# column, in the same order.
	var line_colors: Array[Color] = []

	# Counts every time the colors above are worked out, so set_feature_state()
	# can tell a frame that only moved the features from one that recolored
	# them, and write the colors again only then.
	var color_version: int = 0

	# The styling the colors were last worked out with, kept so resolve() can
	# work them out again when an age style makes them follow the time.
	var styling: Styling = null

	# Every node of the tree by uuid, which is what a coupled feature finds its
	# parent in, whether or not the parent is drawn.
	var nodes := {}

	func index_for(feature: Feature) -> int:
		return int(index_of[feature]) if index_of.has(feature) else column_for(feature)

	# A column of the rows above, a new one on every call, which is what a
	# feature drawn in more than one color needs: a crust, one per band.
	# index_of keeps pointing at the first column the feature took, so
	# everything that asks where a feature is finds it there.
	func column_for(feature: Feature) -> int:
		var index := features.size()
		features.append(feature)
		if not index_of.has(feature):
			index_of[feature] = index
		bases.append(Basis())
		shown.append(true)
		colors.append(feature.color)
		line_colors.append(feature.color)
		starts.append(primitives.size())
		ends.append(primitives.size())
		cap_centres.append(Vector3.UP)
		cap_cosines.append(-1.0)
		return index

	# Work out the cap around each feature from the primitives collected for it.
	# Called once the geometry is complete; the caps are in each feature's own
	# frame, so moving the feature never invalidates them and a step of an
	# animation does not touch them.
	#
	# The primitives of each column are first put in an order that keeps
	# neighbours together, and then cut into blocks of BLOCK_SIZE, each with a
	# cap of its own, which is what the shader skips with; see _order_column().
	func build_caps(tolerance: float) -> void:
		for index in range(features.size()):
			Planet._order_column(primitives, starts[index], ends[index])
			var units: Array = []
			for i in range(starts[index], ends[index]):
				units.append(Planet._units_of(primitives[i]))
			var cap := Planet._cap_of(units, 0, units.size())
			draw_centres.append(cap[0])
			draw_angles.append(cap[1])
			# Widen the hit test's cap by the click tolerance, so a click just
			# outside a thin line is still offered to the triangle loop. A cap
			# that has grown past a right angle is no cheaper than no cap at all.
			var radius: float = cap[1] + tolerance
			cap_centres[index] = cap[0]
			cap_cosines[index] = -1.0 if radius >= PI * 0.5 else cos(radius)
			block_starts.append(block_centres.size())
			for first in range(0, units.size(), BLOCK_SIZE):
				var last := mini(first + BLOCK_SIZE, units.size())
				var block := Planet._cap_of(units, first, last)
				block_centres.append(block[0])
				block_angles.append(block[1])
				block_first.append(starts[index] + first)
				block_last.append(starts[index] + last)
			block_ends.append(block_centres.size())

	# Work out where every feature sits at a time and whether it is there then.
	# A feature's rotation is its own, composed with its parent's while it
	# follows one; nothing above it in the tree moves it. Parents are worked out before
	# their children and once each, through the cache. A feature colored by its
	# age changes color with the time as well.
	func resolve(_root: Feature, time_: float) -> void:
		time = time_
		var cache := {}
		for index in features.size():
			var node: Feature = features[index]
			var same: int = same_motion[index] if index < same_motion.size() else index
			if same != index:
				bases[index] = bases[same]
			else:
				bases[index] = node.basis_at(time) if node.couplings.is_empty() \
					else Coupling.world_basis(node, time, nodes, cache)
			shown[index] = node.exists_at(time)
		if styling != null and styling.by_age:
			recolor(styling)

	# Work out the color of every column again at the resolved time, without
	# touching the primitives. Without a styling each feature is drawn in the
	# color it carries, and the sea floor in the default view settings' colors.
	# A band of a crust takes the crust palette's color at its age, which is why
	# a change of palette reaches the bands without the geometry being
	# collected again.
	func recolor(styling_: Styling) -> void:
		styling = styling_
		color_version += 1
		var drawing := styling if styling != null else Styling.of(null)
		for index in features.size():
			var node: Feature = features[index]
			var color := drawing.color_of(node, time)
			if bands.has(index):
				color = drawing.crust_color(bands[index])
			colors[index] = color
			line_colors[index] = drawing.line_color_of(node, color)


# Upload the feature geometry to the planet shader. Where the features sit, what
# color they are and which one the pointer rests on come from
# set_feature_state() instead, which a frame of an animation and a change of
# color call on their own.
func set_geometry(geometry: Geometry) -> void:
	var count := geometry.primitives.size()
	var globe_mat: ShaderMaterial = globe.get_surface_override_material(0)
	var map_mat: ShaderMaterial = map.get_surface_override_material(0)

	if count == 0:
		for material in [globe_mat, map_mat]:
			material.set_shader_parameter("geometry_count", 0)
			material.set_shader_parameter("column_count", 0)
		return

	# Data texture: two rows of texels per primitive, wrapped at TEXTURE_WRAP,
	# 32-bit float RGBA
	var img := _wrapped_image(count, 2)
	for i in range(count):
		var texels := _texels(geometry.primitives[i])
		img.set_pixelv(_at(i, 0, 2), texels[0])
		img.set_pixelv(_at(i, 1, 2), texels[1])

	# The caps the shader skips with, and the ranges they cover; see
	# Docs/Shader.md#skipping-what-is-far. Both are in each feature's own frame,
	# so they are uploaded with the geometry and never with a step of an
	# animation.
	var columns := geometry.features.size()
	var column_img := _wrapped_image(columns, 2)
	for i in columns:
		var c: Vector3 = geometry.draw_centres[i]
		column_img.set_pixelv(_at(i, 0, 2), Color(c.x, c.y, c.z, geometry.draw_angles[i]))
		column_img.set_pixelv(_at(i, 1, 2), Color(float(geometry.block_starts[i]),
			float(geometry.block_ends[i]), 0.0, 0.0))
	var blocks := geometry.block_centres.size()
	var block_img := _wrapped_image(blocks, 2)
	for i in blocks:
		var c: Vector3 = geometry.block_centres[i]
		block_img.set_pixelv(_at(i, 0, 2), Color(c.x, c.y, c.z, geometry.block_angles[i]))
		block_img.set_pixelv(_at(i, 1, 2), Color(float(geometry.block_first[i]),
			float(geometry.block_last[i]), 0.0, 0.0))

	var tex := ImageTexture.create_from_image(img)
	var column_tex := ImageTexture.create_from_image(column_img)
	var block_tex := ImageTexture.create_from_image(block_img)
	for material in [globe_mat, map_mat]:
		material.set_shader_parameter("geometry_data", tex)
		material.set_shader_parameter("geometry_count", count)
		material.set_shader_parameter("column_data", column_tex)
		material.set_shader_parameter("block_data", block_tex)
		material.set_shader_parameter("column_count", columns)


# An image for `count` entries of `rows` texels each, wrapped at TEXTURE_WRAP.
static func _wrapped_image(count: int, rows: int) -> Image:
	return Image.create(clampi(count, 1, TEXTURE_WRAP),
		maxi(1, ceili(float(count) / TEXTURE_WRAP)) * rows, false, Image.FORMAT_RGBAF)


# Where row `row` of entry i of a texture of `rows` rows an entry is; the
# counterpart of at() in planet.gdshader.
static func _at(i: int, row: int, rows: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(i % TEXTURE_WRAP, i / TEXTURE_WRAP * rows + row)


# The two texels of the geometry texture one primitive is packed into, rows 0
# and 1; see Docs/Shader.md#data-texture-layout.
static func _texels(primitive: Dictionary) -> Array[Color]:
	var v: Array = primitive["verts"]
	var kind: int = primitive["kind"]
	var a: Vector2 = v[0]
	# Row 0: (lat_a, lon_a, lat_b, lon_b) in radians; b is unused by a point. A
	# circle has its center in a and its radius in radians where lat_b would be.
	var row0 := Color(deg_to_rad(a.x), deg_to_rad(a.y), deg_to_rad(a.x), deg_to_rad(a.y))
	if kind == Primitive.CIRCLE:
		row0.b = deg_to_rad(float(primitive["radius"]))
	elif v.size() > 1:
		row0.b = deg_to_rad(v[1].x)
		row0.a = deg_to_rad(v[1].y)
	# Row 1: (lat_c, lon_c, feature, kind); c is only used by a triangle
	var c: Vector2 = v[2] if v.size() > 2 and kind == Primitive.TRIANGLE else a
	var row1 := Color(deg_to_rad(c.x), deg_to_rad(c.y), float(primitive["index"]), float(kind))
	return [row0, row1]


# Upload where each feature sits, whether it is there at the current time, what
# color it is, which one the pointer rests on, which one is highlighted as
# selected, and how the others are related to it: `related` maps a feature to
# a Relation, a child, the parent or a sibling. This is the whole of what one step of an
# animation, a change of color or a change of selection touches, so it is six
# texels per column rather than anything per triangle. Call geometry.resolve()
# for the wanted time first.
func set_feature_state(geometry: Geometry, hovered_feature: Feature = null,
		selected_feature: Feature = null, related: Dictionary = {}) -> void:
	var count := geometry.features.size()
	if count == 0:
		return

	# Data texture: six rows of texels per column, a crust taking one column per
	# band, wrapped at TEXTURE_WRAP, 32-bit float RGBA. The first three rows
	# carry one column of the rotation each, with the hover, the visibility and
	# the selection in the channels the rotation leaves over; the fourth is the
	# color, the fifth says whether the feature is a child of the selected one
	# and how wide its lines are, and the sixth is the color its lines come out
	# in.
	#
	# This runs on every frame of an animation, so the texels are kept in one
	# packed array between calls and the texture is updated in place (GP-0030).
	# When nothing but the time has changed since the last call, the colors,
	# the hover, the selection and the relations are as they were, and only the
	# three rows of the rotation are written again.
	var width := clampi(count, 1, TEXTURE_WRAP)
	var height := maxi(1, ceili(float(count) / TEXTURE_WRAP)) * 6
	var row := width * 4
	var key := [geometry, geometry.color_version, hovered_feature, selected_feature, related]
	var moved_only := key == _state_key and _state_texels.size() == width * height * 4
	if not moved_only:
		_state_key = key.duplicate(true)
		_state_texels = PackedFloat32Array()
		_state_texels.resize(width * height * 4)
	var texels := _state_texels
	for i in range(count):
		var m: Basis = geometry.bases[i]
		@warning_ignore("integer_division")
		var first := ((i / TEXTURE_WRAP * 6) * width + i % TEXTURE_WRAP) * 4
		texels[first] = m.x.x
		texels[first + 1] = m.x.y
		texels[first + 2] = m.x.z
		texels[first + row] = m.y.x
		texels[first + row + 1] = m.y.y
		texels[first + row + 2] = m.y.z
		texels[first + row + 3] = 1.0 if geometry.shown[i] else 0.0
		texels[first + 2 * row] = m.z.x
		texels[first + 2 * row + 1] = m.z.y
		texels[first + 2 * row + 2] = m.z.z
		if moved_only:
			continue
		var node: Feature = geometry.features[i]
		texels[first + 3] = 1.0 if node == hovered_feature else 0.0
		texels[first + 2 * row + 3] = 1.0 if node == selected_feature else 0.0
		# A Color holds sRGB values, the numbers the picker shows; the shader
		# writes ALBEDO in linear light and the renderer encodes to sRGB on the
		# way out, so the color is linearized here or it comes out paler than
		# it was picked. The alpha is left as it is. See
		# Docs/Shader.md#colour-space.
		_put(texels, first + 3 * row, geometry.colors[i].srgb_to_linear())
		texels[first + 4 * row] = float(related.get(node, Relation.NONE))
		texels[first + 4 * row + 1] = node.line_scale()
		_put(texels, first + 5 * row, geometry.line_colors[i].srgb_to_linear())

	var img := Image.create_from_data(width, height, false, Image.FORMAT_RGBAF,
		texels.to_byte_array())
	if _feature_texture != null and _feature_texture.get_size() == Vector2(width, height):
		_feature_texture.update(img)
		return
	_feature_texture = ImageTexture.create_from_image(img)
	for material in [globe.get_surface_override_material(0), map.get_surface_override_material(0)]:
		material.set_shader_parameter("feature_data", _feature_texture)


# The per feature texture and the texels behind it, kept so a frame of an
# animation updates them rather than making new ones, and what they were last
# written for.
var _feature_texture: ImageTexture = null
var _state_texels := PackedFloat32Array()
var _state_key: Array = []


static func _put(texels: PackedFloat32Array, at: int, color: Color) -> void:
	texels[at] = color.r
	texels[at + 1] = color.g
	texels[at + 2] = color.b
	texels[at + 3] = color.a


# Flatten a feature tree into the primitives that draw it, in the frame of each
# feature. A polygon contributes its cached triangles, a polyline the segments
# between consecutive vertices of each ring, and a multipoint one marker per
# vertex. A circle outline is one CIRCLE per ring instead of the ring's
# segments; the rings stay on the feature for everything else. A hotspot adds a small dot at every sample of its track. The result is resolved for the given time, so it can be drawn or hit
# tested straight away; resolve() again to move it to another time.
#
# A topology borrows its vertices from other features, so it is resolved for the
# time first and then flattened like the polyline it is drawn as. A hotspot's
# track follows its plate, and a crust its half and ridge, so they are rebuilt
# for the time the same way, the crust after the ridge.
#
# The styling says which classes of geometry are drawn at all and what colour a
# feature comes out; without one every feature is drawn in the colour it carries,
# which is what a document said before there were any styles. A feature its class
# is switched off for is left out here, so it is neither drawn nor hit tested.
#
# The ridges and crusts go first, under everything else; see _drawing_order().
static func collect_geometry(root: Feature, time: float = 0.0,
		styling: Styling = null) -> Geometry:
	Topology.rebuild_all(root, time)
	Hotspot.rebuild_all(root, time, Config.get_skip_increment())
	Crust.rebuild_all(root, time, Config.get_skip_increment())
	var geometry := Geometry.new()
	geometry.nodes = Coupling.index(root)
	geometry.rebuilt_with_time = Topology.holds_any(root) or Hotspot.holds_any(root)
	var crust_lines := styling == null or styling.shows_crust_lines()
	for node in _drawing_order(root):
		if styling != null and not styling.shows(node):
			continue
		# A feature is drawn whole or not at all, so what it needs is counted
		# before any of it is added. A later, smaller feature may still fit.
		if geometry.primitives.size() + _primitive_count(node, crust_lines) > primitive_limit:
			geometry.dropped += 1
			continue

		var index := geometry.index_for(node)
		# A topology is drawn as a polyline: Topology.rebuild() has already put
		# one run of resolved vertices per section into its rings.
		match node.drawn_as():
			Feature.GeometryKind.POLYGON when node.is_crust():
				index = _collect_bands(geometry, node, index)
			Feature.GeometryKind.POLYGON:
				var verts := node.triangles
				for j in range(0, verts.size() - 2, 3):
					geometry.primitives.append(_primitive(Primitive.TRIANGLE,
						[verts[j], verts[j + 1], verts[j + 2]], node, index))
			Feature.GeometryKind.POLYLINE when node.draws_true_circles():
				var centers := node.circle_centers()
				for j in centers.size():
					geometry.primitives.append({"kind": Primitive.CIRCLE,
						"verts": [centers[j]] + Array(node.rings[j]), "radius": node.radius,
						"feature": node, "index": index})
			Feature.GeometryKind.POLYLINE:
				for ring in node.rings:
					for j in range(ring.size() - 1):
						geometry.primitives.append(_primitive(
							Primitive.SEGMENT, [ring[j], ring[j + 1]], node, index))
				for v in Hotspot.samples(node):
					geometry.primitives.append(_primitive(Primitive.SAMPLE, [v], node, index))
			Feature.GeometryKind.MULTIPOINT:
				for ring in node.rings:
					for v in ring:
						geometry.primitives.append(
							_primitive(Primitive.POINT, [v], node, index))
		# A crust is filled by its bands above and drawn over by its isochrons
		# and flowlines, which are segments of the same feature in its line
		# color; see Logic/crust.gd. Every band carries that one line color, so
		# they go under the last band's column and stay contiguous with it.
		for ring in node.crust_line_rings:
			for j in range(ring.size() - 1) if crust_lines else []:
				geometry.primitives.append(_primitive(
					Primitive.SEGMENT, [ring[j], ring[j + 1]], node, index))
		geometry.ends[index] = geometry.primitives.size()
	geometry.build_caps(2.0 * asin(maxf(LINE_HIT_WIDTH, POINT_HIT_RADIUS) * 0.5))
	geometry.find_same_motion()
	geometry.resolve(root, time)
	geometry.recolor(styling)
	return geometry


# The features to draw, first drawn first, so each lies over the ones before it
# and is hit tested ahead of them. The first feature of a group is drawn on top.
# Every crust goes under every ridge and the ridges under everything else, so the
# sea floor never hides a feature on the tree and a ridge stays over its bands.
#
# A ridge or crust has no row, so the group it sits in does not hide it: a crust
# shows while its half does and a ridge while either of its halves does, a half
# showing when it and every group above it are enabled.
static func _drawing_order(root: Feature) -> Array[Feature]:
	var rest: Array[Feature] = []
	var shown := {}
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if not node.enabled or node.is_sea_floor():
			continue
		if node.is_group:
			stack.append_array(node.children)
			continue
		shown[node.uuid] = true
		rest.append(node)
	var crusts: Array[Feature] = []
	var ridges: Array[Feature] = []
	stack.assign([root])
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		stack.append_array(node.children)
		if not node.is_sea_floor() or not node.enabled \
				or not Array(node.halves()).any(func(uuid: String) -> bool: return shown.has(uuid)):
			continue
		(crusts if node.is_crust() else ridges).append(node)
	return crusts + ridges + rest


# The bands of a crust, each in a column of its own, so the age ramp can fill
# each one in the color of the crust it holds; see Styling.crust_color(). The
# triangles of ring k are the k-th run of Feature.ring_triangles, and the ages
# run oldest first, the oldest band lying against the continent. Answers with
# the column the last band took, which the isochrons and the flowlines are then
# drawn under.
static func _collect_bands(geometry: Geometry, node: Feature, first: int) -> int:
	var ages := node.band_ages
	var count := mini(node.ring_triangles.size(), ages.size())
	if count == 0:
		return first
	var verts := node.triangles
	var at := 0
	var index := first
	for k in count:
		if k > 0:
			index = geometry.column_for(node)
		geometry.bands[index] = ages[k]
		for _t in node.ring_triangles[k]:
			geometry.primitives.append(_primitive(Primitive.TRIANGLE,
				[verts[at], verts[at + 1], verts[at + 2]], node, index))
			at += 3
		geometry.ends[index] = geometry.primitives.size()
	return index


# How many primitives a feature is drawn with, without building them: a polygon
# ring of n vertices is cut into n - 2 triangles, a polyline ring of n into
# n - 1 segments, and a multipoint into one marker per vertex. A circle drawn
# as curves is one primitive per ring. A hotspot's sample dots and a crust's
# isochrons and flowlines come on top, while they are shown.
static func _primitive_count(node: Feature, crust_lines: bool = true) -> int:
	var total := Hotspot.samples(node).size()
	for ring in node.crust_line_rings:
		total += maxi(0, ring.size() - 1) if crust_lines else 0
	if node.draws_true_circles():
		return node.rings.size()
	match node.drawn_as():
		Feature.GeometryKind.POLYGON:
			total = node.triangles.size() / 3
		Feature.GeometryKind.POLYLINE:
			for ring in node.rings:
				total += maxi(0, ring.size() - 1)
		Feature.GeometryKind.MULTIPOINT:
			for ring in node.rings:
				total += ring.size()
	return total


static func _primitive(kind: Primitive, verts: Array, node: Feature, index: int) -> Dictionary:
	return {"kind": kind, "verts": verts, "feature": node, "index": index}


# Put the primitives of one column in an order that keeps neighbours together,
# so a block of BLOCK_SIZE of them is a small patch with a small cap. Ear
# clipping leaves the triangles of a polygon in no such order.
#
# Only a run of primitives of one kind is reordered, never across kinds. Within
# such a run every primitive is laid over the planet in the same color by the
# same amount, and those blends come out the same in any order, so what is
# drawn does not change; a crust's lines still go over its bands. The key is
# the Morton code of the mean latitude and longitude of the vertices.
static func _order_column(primitives: Array, start: int, end: int) -> void:
	var run_start := start
	for i in range(start + 1, end + 1):
		if i < end and primitives[i]["kind"] == primitives[run_start]["kind"]:
			continue
		if i - run_start > BLOCK_SIZE:
			var run := primitives.slice(run_start, i)
			var keyed := run.map(func(primitive: Dictionary) -> Array:
				var mean := Vector2.ZERO
				for v: Vector2 in primitive["verts"]:
					mean += v
				return [_morton(mean / (primitive["verts"] as Array).size()), primitive])
			keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			for j in keyed.size():
				primitives[run_start + j] = keyed[j][1]
		run_start = i


# Latitude and longitude in degrees, each cut to 1024 steps, their bits
# interleaved: points close on the sphere mostly get close codes.
static func _morton(v: Vector2) -> int:
	var y := clampi(int((v.x + 90.0) / 180.0 * 1023.0), 0, 1023)
	var x := clampi(int(fposmod(v.y + 180.0, 360.0) / 360.0 * 1023.0), 0, 1023)
	var code := 0
	for bit in 10:
		code |= ((x >> bit) & 1) << (2 * bit)
		code |= ((y >> bit) & 1) << (2 * bit + 1)
	return code


# The points on the unit sphere a primitive reaches: its vertices, and for a
# circle its ring as well as its centre.
static func _units_of(primitive: Dictionary) -> Array[Vector3]:
	var units: Array[Vector3] = []
	for v in (primitive["verts"] as Array):
		units.append(_latlon_to_unit(deg_to_rad(v.x), deg_to_rad(v.y)))
	return units


# The smallest cap this method finds around the points of units[first] to
# units[last - 1], each an Array of points: [centre, angular radius]. The centre
# is their normalized mean. An angle of PI holds the whole sphere, which is what
# nothing at all and points that cancel out get.
static func _cap_of(units: Array, first: int, last: int) -> Array:
	var sum := Vector3.ZERO
	var count := 0
	for i in range(first, last):
		for unit: Vector3 in units[i]:
			sum += unit
			count += 1
	if count == 0 or sum.length_squared() < 1e-12:
		return [Vector3.UP, PI]
	var centre := sum.normalized()
	var smallest := 1.0
	for i in range(first, last):
		for unit: Vector3 in units[i]:
			smallest = minf(smallest, centre.dot(unit))
	return [centre, acos(clampf(smallest, -1.0, 1.0))]


## Hit test: find which feature covers the given lat/lon point.
## Uses the same great-circle tests as the shader, with a click tolerance around
## the lines and the point markers. Returns null when nothing is there.
##
## The primitives are in each feature's own frame, so the point being asked
## about is carried into that frame rather than the geometry out of it: one
## rotation of one point per feature instead of one per vertex.
static func hit_test(lat: float, lon: float, geometry: Geometry) -> Feature:
	var p := _latlon_to_unit(deg_to_rad(lat), deg_to_rad(lon))
	# Walk the features in reverse, so the topmost, last drawn one wins, and
	# every primitive of a feature together, since they are contiguous.
	for index in range(geometry.features.size() - 1, -1, -1):
		if not geometry.shown[index]:
			continue
		var local := geometry.bases[index].transposed() * p
		# One multiply against the feature's cap throws out everything the
		# point cannot be inside, before a single triangle is looked at.
		if local.dot(geometry.cap_centres[index]) < geometry.cap_cosines[index]:
			continue

		for i in range(geometry.ends[index] - 1, geometry.starts[index] - 1, -1):
			var primitive: Dictionary = geometry.primitives[i]
			var v: Array = primitive["verts"]
			var a := _latlon_to_unit(deg_to_rad(v[0].x), deg_to_rad(v[0].y))

			match int(primitive["kind"]):
				Primitive.TRIANGLE:
					var b := _latlon_to_unit(deg_to_rad(v[1].x), deg_to_rad(v[1].y))
					var c := _latlon_to_unit(deg_to_rad(v[2].x), deg_to_rad(v[2].y))
					if a.cross(b).normalized().dot(local) > 0.0 \
						and b.cross(c).normalized().dot(local) > 0.0 \
						and c.cross(a).normalized().dot(local) > 0.0:
						return primitive["feature"] as Feature
				Primitive.SEGMENT:
					var b := _latlon_to_unit(deg_to_rad(v[1].x), deg_to_rad(v[1].y))
					if arc_distance(a, b, local) <= LINE_HIT_WIDTH:
						return primitive["feature"] as Feature
				Primitive.POINT, Primitive.SAMPLE:
					if _chord(a, local) <= POINT_HIT_RADIUS:
						return primitive["feature"] as Feature
				Primitive.CIRCLE:
					if circle_distance(a, deg_to_rad(float(primitive["radius"])), local) 							<= LINE_HIT_WIDTH:
						return primitive["feature"] as Feature
	return null


# Distance from p to the great-circle arc from a to b, as a chord length.
# The counterpart of arc_distance() in planet.gdshader.
static func arc_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var cross := a.cross(b)
	if cross.length_squared() < 1e-12:
		# The two ends coincide, so the arc is a single point.
		return _chord(a, p)
	var n := cross.normalized()
	if n.cross(a).dot(p) >= 0.0 and b.cross(n).dot(p) >= 0.0:
		return absf(n.dot(p))
	return minf(_chord(a, p), _chord(b, p))


# Distance from p to the circle of the given angular radius around axis, as an
# angle, which is as good as a chord at the width of a line. The counterpart
# of circle_distance() in planet.gdshader.
static func circle_distance(axis: Vector3, radius_rad: float, p: Vector3) -> float:
	return absf(axis.angle_to(p) - radius_rad)


static func _chord(a: Vector3, b: Vector3) -> float:
	return sqrt(2.0 * maxf(0.0, 1.0 - a.dot(b)))


static func _latlon_to_unit(lat_rad: float, lon_rad: float) -> Vector3:
	var cos_lat := cos(lat_rad)
	return Vector3(cos_lat * cos(lon_rad), sin(lat_rad), cos_lat * sin(lon_rad))


## Outline overlay: the shape being drawn, and the outline of the selected feature

# How large the outline overlay draws its vertex markers and its lines, as a
# multiple of what planet.gdshader has them at. The preferences set this; see
# Config.get_vertex_marker_scale().
func set_outline_scale(marker: float, line: float) -> void:
	for material in [globe.get_surface_override_material(0), map.get_surface_override_material(0)]:
		material.set_shader_parameter("outline_dot_radius", DEFAULT_DOT_RADIUS * marker)
		material.set_shader_parameter("outline_line_width", DEFAULT_LINE_WIDTH * line)


# Upload the outline overlay, drawn over the geometry in white.
# Each part: { "vertices": PackedVector2Array of (lat_deg, lon_deg),
#              "style": OutlineStyle }. Pass an empty array to clear it.
func set_outline(parts: Array) -> void:
	var count := 0
	for part in parts:
		count += (part["vertices"] as PackedVector2Array).size()

	var globe_mat: ShaderMaterial = globe.get_surface_override_material(0)
	var map_mat: ShaderMaterial = map.get_surface_override_material(0)

	if count == 0:
		globe_mat.set_shader_parameter("outline_vertex_count", 0)
		map_mat.set_shader_parameter("outline_vertex_count", 0)
		return

	# Every vertex carries the index its part starts at and how the part is
	# drawn, so several parts fit in one texture.
	var img := Image.create(count, 1, false, Image.FORMAT_RGBAF)
	var i := 0
	for part in parts:
		var vertices: PackedVector2Array = part["vertices"]
		var style := float(part.get("style", OutlineStyle.OPEN))
		var start := float(i)
		for v in vertices:
			img.set_pixel(i, 0, Color(deg_to_rad(v.x), deg_to_rad(v.y), start, style))
			i += 1

	var tex := ImageTexture.create_from_image(img)
	for material in [globe_mat, map_mat]:
		material.set_shader_parameter("outline_data", tex)
		material.set_shader_parameter("outline_vertex_count", count)
