extends Node3D
class_name Planet

signal input_event_outside(event: InputEvent)
signal input_event_globe(lat: float, lon: float, event: InputEvent)
signal input_event_map(lat: float, lon: float, event: InputEvent)

# What one entry of the geometry data texture draws. The values are the ones
# the shader switches on, so they must match the kinds listed in planet.gdshader.
enum Primitive { TRIANGLE = 0, SEGMENT = 1, POINT = 2 }

# Radius of the globe, in the units planet.tscn is laid out in. The SphereMesh
# that is drawn and the SphereShape3D that clicks are picked against are both
# set to it in _ready(), so the surface the pointer meets is the surface the
# pixel shows.
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

# Style of one part of the outline overlay. Matches planet.gdshader.
enum OutlineStyle {
	OPEN = 0,           # a line from the first vertex to the last
	CLOSED_PREVIEW = 1, # closed, with the closing segment drawn faintly
	POINTS = 2,         # the vertex markers only, no segments
	CLOSED = 3,         # closed, with every segment drawn the same
}

@export var show_map: bool = false;
@export_range(-90, 90, 1.0, "Latitude") var lat: float = 0.0;
@export_range(-180, 180, 1.0, "Longitude") var lon: float = 0.0;
@export_range(-180, 180, 1.0, "Angle") var angle: float = 0.0;

@onready var globe = $Globe;
@onready var map = $Map;
@onready var globe_shape: CollisionShape3D = $Globe/GlobePhysicsBody/CollisionShape3D;


func _ready() -> void:
	var sphere: SphereMesh = globe.mesh
	sphere.radius = GLOBE_RADIUS
	sphere.height = GLOBE_RADIUS * 2.0
	(globe_shape.shape as SphereShape3D).radius = GLOBE_RADIUS


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	globe.visible = not show_map
	map.visible = show_map

	if globe:
		globe.rotation = Vector3(deg_to_rad(lat), deg_to_rad(180 - lon), deg_to_rad(angle))


func _on_background_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	input_event_outside.emit(event)


# The globe and the map both keep their collision bodies whatever is being
# shown, so both report a pointer that moves over them. Only the one on screen
# is listened to: the map works out its latitude and longitude by scaling the
# point, without the bounds a sphere gives, so the hidden one answers with
# nonsense like 539 degrees of longitude and whoever is listening believes it.
func _on_globe_physics_body_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if show_map:
		return
	var local_pos = globe.transform.inverse() * event_position
	var rad = Vector2(local_pos.x, local_pos.z).length()
	var lat = rad_to_deg(atan2(local_pos.y, rad))
	var lon = rad_to_deg(atan2(-local_pos.x, -local_pos.z))
	input_event_globe.emit(lat, lon, event)


func _on_map_physics_body_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if not show_map:
		return
	var local_pos = map.transform.inverse() * event_position
	var lat = local_pos.y * 90
	var lon = local_pos.x * 180
	input_event_map.emit(lat, lon, event)


## Feature geometry rendering


# The flattened geometry of a feature tree, ready for the shader and for the hit
# test. The primitives are in each feature's own frame and change only when the
# tree does; where a feature sits at the current time is one rotation per
# feature, so a step of an animation re-uploads that small part alone and leaves
# the vertices where they were put.
class Geometry extends RefCounted:
	# One entry per primitive: { "kind": Primitive, "verts": Array of
	# Vector2(latitude, longitude) in degrees in the feature's own frame,
	# "color": Color, "feature": Feature, "index": int into features }. Every
	# primitive of one feature is contiguous, which is what lets the shader and
	# the hit test look its rotation up once instead of once per primitive.
	var primitives: Array = []

	# The features the primitives belong to, in the order they were first met.
	var features: Array[Feature] = []
	var index_of := {}

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

	func index_for(feature: Feature) -> int:
		if index_of.has(feature):
			return int(index_of[feature])
		var index := features.size()
		features.append(feature)
		index_of[feature] = index
		bases.append(Basis())
		shown.append(true)
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
	# The tree is walked from the root down so that each node composes its own
	# rotation with what its ancestors already gave it, which is how a group
	# carries everything under it along.
	func resolve(root: Feature, time_: float) -> void:
		time = time_
		var stack: Array = [[root, Basis()]]
		while not stack.is_empty():
			var entry: Array = stack.pop_back()
			var node: Feature = entry[0]
			var m: Basis = (entry[1] as Basis) * node.basis_at(time)
			if index_of.has(node):
				var index := int(index_of[node])
				bases[index] = m
				shown[index] = node.exists_at(time)
			for child in node.children:
				stack.append([child, m])


# Upload the feature geometry to the planet shader. Where the features sit and
# which one the pointer rests on come from set_feature_state() instead, which a
# frame of an animation calls on its own.
func set_geometry(geometry: Geometry) -> void:
	var count := geometry.primitives.size()
	var globe_mat: ShaderMaterial = globe.get_surface_override_material(0)
	var map_mat: ShaderMaterial = map.get_surface_override_material(0)

	if count == 0:
		globe_mat.set_shader_parameter("geometry_count", 0)
		map_mat.set_shader_parameter("geometry_count", 0)
		return

	# Data texture: width = primitive count, height = 3, 32-bit float RGBA
	var img := Image.create(count, 3, false, Image.FORMAT_RGBAF)

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
		# Row 2: color (r, g, b, a)
		img.set_pixel(i, 2, primitive["color"])

	var tex := ImageTexture.create_from_image(img)
	for material in [globe_mat, map_mat]:
		material.set_shader_parameter("geometry_data", tex)
		material.set_shader_parameter("geometry_count", count)


# Upload where each feature sits, whether it is there at the current time, and
# which one the pointer rests on. This is the whole of what one step of an
# animation changes, so it is three texels per feature rather than three rows
# per triangle. Call geometry.resolve() for the wanted time first.
func set_feature_state(geometry: Geometry, hovered_feature: Feature = null) -> void:
	var count := geometry.features.size()
	if count == 0:
		return

	# Data texture: width = feature count, height = 3, 32-bit float RGBA. Each
	# row carries one column of the rotation, with the hover and the visibility
	# in the two channels the rotation leaves over.
	var img := Image.create(count, 3, false, Image.FORMAT_RGBAF)
	for i in range(count):
		var m: Basis = geometry.bases[i]
		var hovered := 1.0 if geometry.features[i] == hovered_feature else 0.0
		img.set_pixel(i, 0, Color(m.x.x, m.x.y, m.x.z, hovered))
		img.set_pixel(i, 1, Color(m.y.x, m.y.y, m.y.z, 1.0 if geometry.shown[i] else 0.0))
		img.set_pixel(i, 2, Color(m.z.x, m.z.y, m.z.z, 0.0))

	var tex := ImageTexture.create_from_image(img)
	for material in [globe.get_surface_override_material(0), map.get_surface_override_material(0)]:
		material.set_shader_parameter("feature_data", tex)


# Flatten a feature tree into the primitives that draw it, in the frame of each
# feature. A polygon contributes its cached triangles, a polyline the segments
# between consecutive vertices of each ring, and a multipoint one marker per
# vertex. The result is resolved for the given time, so it can be drawn or hit
# tested straight away; resolve() again to move it to another time.
static func collect_geometry(root: Feature, time: float = 0.0) -> Geometry:
	var geometry := Geometry.new()
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if not node.enabled:
			continue
		if node.is_group:
			stack.append_array(node.children)
			continue

		var index := geometry.index_for(node)
		match node.geometry_kind:
			Feature.GeometryKind.POLYGON:
				var verts := node.triangles
				for j in range(0, verts.size() - 2, 3):
					geometry.primitives.append(_primitive(
						Primitive.TRIANGLE, [verts[j], verts[j + 1], verts[j + 2]], node, index))
			Feature.GeometryKind.POLYLINE:
				for ring in node.rings:
					for j in range(ring.size() - 1):
						geometry.primitives.append(_primitive(
							Primitive.SEGMENT, [ring[j], ring[j + 1]], node, index))
			Feature.GeometryKind.MULTIPOINT:
				for ring in node.rings:
					for v in ring:
						geometry.primitives.append(_primitive(Primitive.POINT, [v], node, index))
		geometry.ends[index] = geometry.primitives.size()
	geometry.build_caps(2.0 * asin(maxf(LINE_HIT_WIDTH, POINT_HIT_RADIUS) * 0.5))
	geometry.resolve(root, time)
	return geometry


static func _primitive(kind: Primitive, verts: Array, node: Feature, index: int) -> Dictionary:
	return {"kind": kind, "verts": verts, "color": node.color, "feature": node, "index": index}


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
