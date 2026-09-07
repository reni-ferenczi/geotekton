extends Node3D
class_name Planet

signal input_event_outside(event: InputEvent)
signal input_event_globe(lat: float, lon: float, event: InputEvent)
signal input_event_map(lat: float, lon: float, event: InputEvent)

# What one entry of the geometry data texture draws. The values are the ones
# the shader switches on, so they must match the kinds listed in planet.gdshader.
enum Primitive { TRIANGLE = 0, SEGMENT = 1, POINT = 2 }

# How close a click counts as a hit on a polyline or a multipoint, as a chord
# length on the unit sphere. A little wider than what is drawn, so a thin line
# and a small marker stay easy to pick.
const LINE_HIT_WIDTH := 0.02
const POINT_HIT_RADIUS := 0.025

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


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	globe.visible = not show_map
	map.visible = show_map

	if globe:
		globe.rotation = Vector3(deg_to_rad(lat), deg_to_rad(180 - lon), deg_to_rad(angle))


func _on_background_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	input_event_outside.emit(event)


func _on_globe_physics_body_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	var local_pos = globe.transform.inverse() * event_position
	var rad = Vector2(local_pos.x, local_pos.z).length()
	var lat = rad_to_deg(atan2(local_pos.y, rad))
	var lon = rad_to_deg(atan2(-local_pos.x, -local_pos.z))
	input_event_globe.emit(lat, lon, event)


func _on_map_physics_body_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	var local_pos = map.transform.inverse() * event_position
	var lat = local_pos.y * 90
	var lon = local_pos.x * 180
	input_event_map.emit(lat, lon, event)


## Feature geometry rendering

# Upload the feature geometry to the planet shader.
# Each entry: { "kind": Primitive, "verts": Array[Vector2], "color": Color,
#               "feature": Feature }. A triangle carries three vertices, a
# segment two and a point one, as Vector2(latitude_deg, longitude_deg).
func set_geometry(primitives: Array, hovered_feature: Feature = null) -> void:
	var count := primitives.size()
	var globe_mat: ShaderMaterial = globe.get_surface_override_material(0)
	var map_mat: ShaderMaterial = map.get_surface_override_material(0)

	if count == 0:
		globe_mat.set_shader_parameter("geometry_count", 0)
		map_mat.set_shader_parameter("geometry_count", 0)
		return

	# Data texture: width = primitive count, height = 3, 32-bit float RGBA
	var img := Image.create(count, 3, false, Image.FORMAT_RGBAF)

	for i in range(count):
		var primitive: Dictionary = primitives[i]
		var v: Array = primitive["verts"]
		var kind: int = primitive["kind"]

		# Row 0: (lat_a, lon_a, lat_b, lon_b) in radians; b is unused by a point
		var b: Vector2 = v[1] if v.size() > 1 else v[0]
		img.set_pixel(i, 0, Color(
			deg_to_rad(v[0].x), deg_to_rad(v[0].y),
			deg_to_rad(b.x), deg_to_rad(b.y)
		))
		# Row 1: (lat_c, lon_c, hovered, kind); c is only used by a triangle
		var c: Vector2 = v[2] if v.size() > 2 else v[0]
		var hovered := 1.0 if (hovered_feature != null and primitive.get("feature") == hovered_feature) else 0.0
		img.set_pixel(i, 1, Color(
			deg_to_rad(c.x), deg_to_rad(c.y),
			hovered, float(kind)
		))
		# Row 2: color (r, g, b, a)
		img.set_pixel(i, 2, primitive["color"])

	var tex := ImageTexture.create_from_image(img)
	for material in [globe_mat, map_mat]:
		material.set_shader_parameter("geometry_data", tex)
		material.set_shader_parameter("geometry_count", count)


# Flatten a feature tree into the primitives that draw it, in world space.
# A polygon contributes its cached triangles, a polyline the segments between
# consecutive vertices of each ring, and a multipoint one marker per vertex.
static func collect_geometry(root: Feature) -> Array:
	var primitives: Array = []
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if not node.enabled:
			continue
		if node.is_group:
			stack.append_array(node.children)
			continue

		match node.geometry_kind:
			Feature.GeometryKind.POLYGON:
				var verts := Feature.apply_rotation(node.triangles, node.rotation_angles)
				for j in range(0, verts.size() - 2, 3):
					primitives.append(_primitive(
						Primitive.TRIANGLE, [verts[j], verts[j + 1], verts[j + 2]], node))
			Feature.GeometryKind.POLYLINE:
				for ring in node.rings:
					var verts := Feature.apply_rotation(ring, node.rotation_angles)
					for j in range(verts.size() - 1):
						primitives.append(_primitive(
							Primitive.SEGMENT, [verts[j], verts[j + 1]], node))
			Feature.GeometryKind.MULTIPOINT:
				for ring in node.rings:
					for v in Feature.apply_rotation(ring, node.rotation_angles):
						primitives.append(_primitive(Primitive.POINT, [v], node))
	return primitives


static func _primitive(kind: Primitive, verts: Array, node: Feature) -> Dictionary:
	return {"kind": kind, "verts": verts, "color": node.color, "feature": node}


## Hit test: find which feature covers the given lat/lon point.
## Uses the same great-circle tests as the shader, with a click tolerance around
## the lines and the point markers. Returns null when nothing is there.
static func hit_test(lat: float, lon: float, primitives: Array) -> Feature:
	var p := _latlon_to_unit(deg_to_rad(lat), deg_to_rad(lon))
	# Iterate in reverse so topmost (last-drawn) geometry wins
	for i in range(primitives.size() - 1, -1, -1):
		var primitive: Dictionary = primitives[i]
		var v: Array = primitive["verts"]
		var a := _latlon_to_unit(deg_to_rad(v[0].x), deg_to_rad(v[0].y))

		match int(primitive["kind"]):
			Primitive.TRIANGLE:
				var b := _latlon_to_unit(deg_to_rad(v[1].x), deg_to_rad(v[1].y))
				var c := _latlon_to_unit(deg_to_rad(v[2].x), deg_to_rad(v[2].y))
				if a.cross(b).normalized().dot(p) > 0.0 \
					and b.cross(c).normalized().dot(p) > 0.0 \
					and c.cross(a).normalized().dot(p) > 0.0:
					return primitive["feature"] as Feature
			Primitive.SEGMENT:
				var b := _latlon_to_unit(deg_to_rad(v[1].x), deg_to_rad(v[1].y))
				if arc_distance(a, b, p) <= LINE_HIT_WIDTH:
					return primitive["feature"] as Feature
			Primitive.POINT:
				if _chord(a, p) <= POINT_HIT_RADIUS:
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
