extends Node3D
class_name Planet

signal input_event_outside(event: InputEvent)
signal input_event_globe(lat: float, lon: float, event: InputEvent)
signal input_event_map(lat: float, lon: float, event: InputEvent)

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


## Craton rendering

# Set craton triangles on the planet shader.
# Each entry: { "verts": [Vector2, Vector2, Vector2], "color": Color }
# Vertices are Vector2(latitude_deg, longitude_deg).
func set_cratons(triangles: Array, hovered_feature: Feature = null) -> void:
	var count := triangles.size()
	var globe_mat: ShaderMaterial = globe.get_surface_override_material(0)
	var map_mat: ShaderMaterial = map.get_surface_override_material(0)

	if count == 0:
		globe_mat.set_shader_parameter("craton_count", 0)
		map_mat.set_shader_parameter("craton_count", 0)
		return

	# Data texture: width = count, height = 3, 32-bit float RGBA
	var img := Image.create(count, 3, false, Image.FORMAT_RGBAF)

	for i in range(count):
		var tri: Dictionary = triangles[i]
		var v: Array = tri["verts"]
		var c: Color = tri["color"]

		# Row 0: (lat_a, lon_a, lat_b, lon_b) in radians
		img.set_pixel(i, 0, Color(
			deg_to_rad(v[0].x), deg_to_rad(v[0].y),
			deg_to_rad(v[1].x), deg_to_rad(v[1].y)
		))
		# Row 1: (lat_c, lon_c, hovered, 0)
		var hovered := 1.0 if (hovered_feature != null and tri.get("feature") == hovered_feature) else 0.0
		img.set_pixel(i, 1, Color(
			deg_to_rad(v[2].x), deg_to_rad(v[2].y),
			hovered, 0.0
		))
		# Row 2: color (r, g, b, a)
		img.set_pixel(i, 2, c)

	var tex := ImageTexture.create_from_image(img)
	globe_mat.set_shader_parameter("craton_data", tex)
	globe_mat.set_shader_parameter("craton_count", count)
	map_mat.set_shader_parameter("craton_data", tex)
	map_mat.set_shader_parameter("craton_count", count)


# Extract craton triangles from a feature tree.
# Every 3 consecutive vertices in a leaf feature's derived triangle soup form
# one triangle. The soup is rebuilt from outlines whenever outlines change.
static func collect_triangles(root: Feature) -> Array:
	var triangles: Array = []
	var stack: Array[Feature] = [root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if not node.enabled:
			continue
		if node.is_group:
			stack.append_array(node.children)
		else:
			var verts := Feature.apply_rotation(node.triangles, node.rotation_angles)
			for j in range(0, verts.size() - 2, 3):
				triangles.append({
					"verts": [verts[j], verts[j + 1], verts[j + 2]],
					"color": node.color,
					"feature": node,
				})
	return triangles


## Hit-test: find which feature's craton contains the given lat/lon point.
## Uses the same great-circle half-plane test as the shader.
## Returns null if no craton is hit.
static func hit_test_craton(lat: float, lon: float, triangles: Array) -> Feature:
	var p := _latlon_to_unit(deg_to_rad(lat), deg_to_rad(lon))
	# Iterate in reverse so topmost (last-drawn) triangle wins
	for i in range(triangles.size() - 1, -1, -1):
		var tri: Dictionary = triangles[i]
		var v: Array = tri["verts"]
		var a := _latlon_to_unit(deg_to_rad(v[0].x), deg_to_rad(v[0].y))
		var b := _latlon_to_unit(deg_to_rad(v[1].x), deg_to_rad(v[1].y))
		var c := _latlon_to_unit(deg_to_rad(v[2].x), deg_to_rad(v[2].y))

		var d_ab := a.cross(b).normalized().dot(p)
		var d_bc := b.cross(c).normalized().dot(p)
		var d_ca := c.cross(a).normalized().dot(p)

		if d_ab > 0.0 and d_bc > 0.0 and d_ca > 0.0:
			return tri["feature"] as Feature
	return null


static func _latlon_to_unit(lat_rad: float, lon_rad: float) -> Vector3:
	var cos_lat := cos(lat_rad)
	return Vector3(cos_lat * cos(lon_rad), sin(lat_rad), cos_lat * sin(lon_rad))


## Axis marker rendering

# Show or hide the rotation axis marker at the given lat/lon.
func set_axis(lat: float, lon: float, enabled: bool) -> void:
	var globe_mat: ShaderMaterial = globe.get_surface_override_material(0)
	var map_mat: ShaderMaterial = map.get_surface_override_material(0)
	globe_mat.set_shader_parameter("axis_enabled", enabled)
	map_mat.set_shader_parameter("axis_enabled", enabled)
	if enabled:
		var p := Vector2(deg_to_rad(lat), deg_to_rad(lon))
		globe_mat.set_shader_parameter("axis_latlon", p)
		map_mat.set_shader_parameter("axis_latlon", p)


## Outline rendering (drawing preview)

# Set outline vertices for the polygon drawing preview.
# vertices: ordered Array[Vector2] of (lat_deg, lon_deg).
# closed: if true, draws a closing line from last vertex back to first.
func set_outline(vertices: Array[Vector2], closed: bool = false, triangles_mode: bool = false) -> void:
	var count := vertices.size()
	var globe_mat: ShaderMaterial = globe.get_surface_override_material(0)
	var map_mat: ShaderMaterial = map.get_surface_override_material(0)

	if count == 0:
		globe_mat.set_shader_parameter("outline_vertex_count", 0)
		map_mat.set_shader_parameter("outline_vertex_count", 0)
		return

	var img := Image.create(count, 1, false, Image.FORMAT_RGBAF)
	for i in range(count):
		img.set_pixel(i, 0, Color(
			deg_to_rad(vertices[i].x), deg_to_rad(vertices[i].y),
			0.0, 0.0
		))

	var tex := ImageTexture.create_from_image(img)
	globe_mat.set_shader_parameter("outline_data", tex)
	globe_mat.set_shader_parameter("outline_vertex_count", count)
	globe_mat.set_shader_parameter("outline_closed", closed)
	globe_mat.set_shader_parameter("outline_triangles_mode", triangles_mode)
	map_mat.set_shader_parameter("outline_data", tex)
	map_mat.set_shader_parameter("outline_vertex_count", count)
	map_mat.set_shader_parameter("outline_closed", closed)
	map_mat.set_shader_parameter("outline_triangles_mode", triangles_mode)
