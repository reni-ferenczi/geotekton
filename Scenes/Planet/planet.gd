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
func set_cratons(triangles: Array) -> void:
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
		# Row 1: (lat_c, lon_c, 0, 0)
		img.set_pixel(i, 1, Color(
			deg_to_rad(v[2].x), deg_to_rad(v[2].y),
			0.0, 0.0
		))
		# Row 2: color (r, g, b, a)
		img.set_pixel(i, 2, c)

	var tex := ImageTexture.create_from_image(img)
	globe_mat.set_shader_parameter("craton_data", tex)
	globe_mat.set_shader_parameter("craton_count", count)
	map_mat.set_shader_parameter("craton_data", tex)
	map_mat.set_shader_parameter("craton_count", count)


# Extract craton triangles from a feature tree.
# Every 3 consecutive vertices in a leaf feature form one triangle.
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
			var verts := Feature.apply_rotation(node.vertices, node.rotation_angles)
			for j in range(0, verts.size() - 2, 3):
				triangles.append({
					"verts": [verts[j], verts[j + 1], verts[j + 2]],
					"color": node.color,
				})
	return triangles


## Outline rendering (drawing preview)

# Set outline vertices for the polygon drawing preview.
# vertices: ordered Array[Vector2] of (lat_deg, lon_deg).
# closed: if true, draws a closing line from last vertex back to first.
func set_outline(vertices: Array[Vector2], closed: bool = false) -> void:
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
	map_mat.set_shader_parameter("outline_data", tex)
	map_mat.set_shader_parameter("outline_vertex_count", count)
	map_mat.set_shader_parameter("outline_closed", closed)
