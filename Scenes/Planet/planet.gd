extends Node3D
class_name Planet

# What one entry of the geometry data texture draws. The values are the ones
# the shader switches on, so they must match the kinds listed in planet.gdshader.
enum Primitive { TRIANGLE = 0, SEGMENT = 1, POINT = 2 }

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
const DEFAULT_DOT_RADIUS := 0.006
const DEFAULT_LINE_WIDTH := 0.002

# What a feature riding on the selected one is traced in, when the View menu
# asks for it, and what tints its row in the tree. planet.gdshader
# holds the same color, linearized, as RIDER_COLOR.
const RIDER_COLOR := Color(1.0, 0.5, 0.0)

# Style of one part of the outline overlay. Matches planet.gdshader.
enum OutlineStyle {
	OPEN = 0,           # a line from the first vertex to the last
	CLOSED_PREVIEW = 1, # closed, with the closing segment drawn faintly
	POINTS = 2,         # the vertex markers only, no segments
	CLOSED = 3,         # closed, with every segment drawn the same
	OUTLINE = 4,        # closed like CLOSED, with no vertex markers
	MARKERS = 5,        # the vertex markers only, drawn larger
	RIDER = 6,          # closed like OUTLINE, in RIDER_COLOR
	BOLD = 7,           # open like OPEN, as wide as a feature line, no markers
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
# How many primitives one document is drawn with. The geometry texture is one
# texel per primitive wide and 16384 is the widest a desktop device is required
# to make one, so past this the texture cannot be created at all. The shader
# also loops over every primitive for every fragment, so a frame is long before
# then; see Docs/Shader.md#measured. Whatever does not fit is left out rather
# than the window standing still, and the feature tree still holds all of it.
const MAX_PRIMITIVES := 16384


class Geometry extends RefCounted:
	# One entry per primitive: { "kind": Primitive, "verts": Array of
	# Vector2(latitude, longitude) in degrees in the feature's own frame,
	# "feature": Feature, "index": int into features }. Every
	# primitive of one feature is contiguous, which is what lets the shader and
	# the hit test look its rotation up once instead of once per primitive.
	var primitives: Array = []

	# The features the primitives belong to, in the order they were first met.
	var features: Array[Feature] = []
	var index_of := {}

	# How many features were left out because MAX_PRIMITIVES was reached.
	var dropped: int = 0

	# Where each feature's primitives sit in the list, as a half open range.
	# Every primitive of one feature is contiguous, so the hit test can walk one
	# feature or skip all of it.
	var starts: Array[int] = []
	var ends: Array[int] = []

	# A cap holding every primitive of one feature, in that feature's own frame:
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

	# Where each feature is and whether it is there at all, at the time resolve()
	# was last called for. One entry per feature, in the same order.
	var bases: Array[Basis] = []
	var shown: Array[bool] = []
	var time: float = 0.0

	# The color each feature is drawn in, as the active style gave it, in sRGB
	# with the opacity in alpha. One entry per feature, in the same order.
	var colors: Array[Color] = []

	# The styling the colors were last worked out with, kept so resolve() can
	# work them out again when an age style makes them follow the time.
	var styling: Styling = null

	# Every node of the tree by uuid, which is what a coupled feature finds its
	# parent in, whether or not the parent is drawn.
	var nodes := {}

	func index_for(feature: Feature) -> int:
		if index_of.has(feature):
			return int(index_of[feature])
		var index := features.size()
		features.append(feature)
		index_of[feature] = index
		bases.append(Basis())
		shown.append(true)
		colors.append(feature.color)
		starts.append(primitives.size())
		ends.append(primitives.size())
		cap_centres.append(Vector3.UP)
		cap_cosines.append(-1.0)
		return index

	# Work out the cap around each feature from the primitives collected for it.
	# Called once the geometry is complete; the caps are in each feature's own
	# frame, so moving the feature never invalidates them and a step of an
	# animation does not touch them.
	func build_caps(tolerance: float) -> void:
		for index in range(features.size()):
			var sum := Vector3.ZERO
			var points: Array[Vector3] = []
			for i in range(starts[index], ends[index]):
				for v in (primitives[i]["verts"] as Array):
					var unit := Planet._latlon_to_unit(deg_to_rad(v.x), deg_to_rad(v.y))
					points.append(unit)
					sum += unit
			if points.is_empty() or sum.length_squared() < 1e-12:
				cap_cosines[index] = -1.0
				continue
			var centre := sum.normalized()
			var smallest := 1.0
			for point in points:
				smallest = minf(smallest, centre.dot(point))
			# Widen the cap by the click tolerance, so a click just outside a
			# thin line is still offered to the triangle loop. A cap that has
			# grown past a right angle is no cheaper than no cap at all.
			var radius := acos(clampf(smallest, -1.0, 1.0)) + tolerance
			cap_centres[index] = centre
			cap_cosines[index] = -1.0 if radius >= PI * 0.5 else cos(radius)

	# Work out where every feature sits at a time and whether it is there then.
	# A feature's rotation is its own, composed with its parent's while it rides
	# on one; nothing above it in the tree moves it. Parents are worked out before
	# their children and once each, through the cache. A feature colored by its
	# age changes color with the time as well.
	func resolve(_root: Feature, time_: float) -> void:
		time = time_
		var cache := {}
		for index in features.size():
			var node: Feature = features[index]
			bases[index] = node.basis_at(time) if node.couplings.is_empty() \
				else Coupling.world_basis(node, time, nodes, cache)
			shown[index] = node.exists_at(time)
		if styling != null and styling.by_age:
			recolor(styling)

	# Work out the color of every feature again at the resolved time, without
	# touching the primitives. Without a styling each feature is drawn in the
	# color it carries.
	func recolor(styling_: Styling) -> void:
		styling = styling_
		for index in features.size():
			var node: Feature = features[index]
			colors[index] = styling.color_of(node, time) if styling != null else node.color


# Upload the feature geometry to the planet shader. Where the features sit, what
# color they are and which one the pointer rests on come from
# set_feature_state() instead, which a frame of an animation and a change of
# color call on their own.
func set_geometry(geometry: Geometry) -> void:
	var count := geometry.primitives.size()
	var globe_mat: ShaderMaterial = globe.get_surface_override_material(0)
	var map_mat: ShaderMaterial = map.get_surface_override_material(0)

	if count == 0:
		globe_mat.set_shader_parameter("geometry_count", 0)
		map_mat.set_shader_parameter("geometry_count", 0)
		return

	# Data texture: width = primitive count, height = 2, 32-bit float RGBA
	var img := Image.create(count, 2, false, Image.FORMAT_RGBAF)

	for i in range(count):
		var primitive: Dictionary = geometry.primitives[i]
		var v: Array = primitive["verts"]
		var kind: int = primitive["kind"]

		# Row 0: (lat_a, lon_a, lat_b, lon_b) in radians; b is unused by a point
		var b: Vector2 = v[1] if v.size() > 1 else v[0]
		img.set_pixel(i, 0, Color(
			deg_to_rad(v[0].x), deg_to_rad(v[0].y),
			deg_to_rad(b.x), deg_to_rad(b.y)
		))
		# Row 1: (lat_c, lon_c, feature, kind); c is only used by a triangle
		var c: Vector2 = v[2] if v.size() > 2 else v[0]
		img.set_pixel(i, 1, Color(
			deg_to_rad(c.x), deg_to_rad(c.y),
			float(primitive["index"]), float(kind)
		))

	var tex := ImageTexture.create_from_image(img)
	for material in [globe_mat, map_mat]:
		material.set_shader_parameter("geometry_data", tex)
		material.set_shader_parameter("geometry_count", count)


# Upload where each feature sits, whether it is there at the current time, what
# color it is, which one the pointer rests on, which one is highlighted as
# selected and which ones ride on that one. This is the whole of what one step of an
# animation, a change of color or a change of selection touches, so it is five
# texels per feature rather than anything per triangle. Call geometry.resolve()
# for the wanted time first.
func set_feature_state(geometry: Geometry, hovered_feature: Feature = null,
		selected_feature: Feature = null, related: Array[Feature] = []) -> void:
	var count := geometry.features.size()
	if count == 0:
		return

	# Data texture: width = feature count, height = 5, 32-bit float RGBA. The
	# first three rows carry one column of the rotation each, with the hover,
	# the visibility and the selection in the channels the rotation leaves over;
	# the fourth is the color and the fifth says whether the feature rides on the
	# selected one.
	var img := Image.create(count, 5, false, Image.FORMAT_RGBAF)
	for i in range(count):
		var m: Basis = geometry.bases[i]
		var hovered := 1.0 if geometry.features[i] == hovered_feature else 0.0
		var selected := 1.0 if geometry.features[i] == selected_feature else 0.0
		img.set_pixel(i, 0, Color(m.x.x, m.x.y, m.x.z, hovered))
		img.set_pixel(i, 1, Color(m.y.x, m.y.y, m.y.z, 1.0 if geometry.shown[i] else 0.0))
		img.set_pixel(i, 2, Color(m.z.x, m.z.y, m.z.z, selected))
		# A Color holds sRGB values, the numbers the picker shows; the shader
		# writes ALBEDO in linear light and the renderer encodes to sRGB on the
		# way out, so the color is linearized here or it comes out paler than
		# it was picked. The alpha is left as it is. See
		# Docs/Shader.md#colour-space.
		img.set_pixel(i, 3, geometry.colors[i].srgb_to_linear())
		img.set_pixel(i, 4, Color(1.0 if geometry.features[i] in related else 0.0, 0.0, 0.0))

	var tex := ImageTexture.create_from_image(img)
	for material in [globe.get_surface_override_material(0), map.get_surface_override_material(0)]:
		material.set_shader_parameter("feature_data", tex)


# Flatten a feature tree into the primitives that draw it, in the frame of each
# feature. A polygon contributes its cached triangles, a polyline the segments
# between consecutive vertices of each ring, and a multipoint one marker per
# vertex. The result is resolved for the given time, so it can be drawn or hit
# tested straight away; resolve() again to move it to another time.
#
# A topology borrows its vertices from other features, so it is resolved for the
# time first and then flattened like the polyline it is drawn as. A hotspot's
# track follows its plate, so it is rebuilt for the time the same way.
#
# The styling says which classes of geometry are drawn at all and what colour a
# feature comes out; without one every feature is drawn in the colour it carries,
# which is what a document said before there were any styles. A feature its class
# is switched off for is left out here, so it is neither drawn nor hit tested.
static func collect_geometry(root: Feature, time: float = 0.0,
		styling: Styling = null) -> Geometry:
	Topology.rebuild_all(root, time)
	Hotspot.rebuild_all(root, time)
	var geometry := Geometry.new()
	geometry.nodes = Coupling.index(root)
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if not node.enabled:
			continue
		if node.is_group:
			stack.append_array(node.children)
			continue
		if styling != null and not styling.shows(node):
			continue
		# A feature is drawn whole or not at all, so what it needs is counted
		# before any of it is added. A later, smaller feature may still fit.
		if geometry.primitives.size() + _primitive_count(node) > MAX_PRIMITIVES:
			geometry.dropped += 1
			continue

		var index := geometry.index_for(node)
		# A topology is drawn as a polyline: Topology.rebuild() has already put
		# one run of resolved vertices per section into its rings.
		match node.drawn_as():
			Feature.GeometryKind.POLYGON:
				var verts := node.triangles
				for j in range(0, verts.size() - 2, 3):
					geometry.primitives.append(_primitive(Primitive.TRIANGLE,
						[verts[j], verts[j + 1], verts[j + 2]], node, index))
			Feature.GeometryKind.POLYLINE:
				for ring in node.rings:
					for j in range(ring.size() - 1):
						geometry.primitives.append(_primitive(
							Primitive.SEGMENT, [ring[j], ring[j + 1]], node, index))
			Feature.GeometryKind.MULTIPOINT:
				for ring in node.rings:
					for v in ring:
						geometry.primitives.append(
							_primitive(Primitive.POINT, [v], node, index))
		geometry.ends[index] = geometry.primitives.size()
	geometry.build_caps(2.0 * asin(maxf(LINE_HIT_WIDTH, POINT_HIT_RADIUS) * 0.5))
	geometry.resolve(root, time)
	geometry.recolor(styling)
	return geometry


# How many primitives a feature is drawn with, without building them: a polygon
# ring of n vertices is cut into n - 2 triangles, a polyline ring of n into
# n - 1 segments, and a multipoint into one marker per vertex.
static func _primitive_count(node: Feature) -> int:
	var total := 0
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
				Primitive.POINT:
					if _chord(a, local) <= POINT_HIT_RADIUS:
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


# Upload the outline overlay, drawn over the geometry in yellow.
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
