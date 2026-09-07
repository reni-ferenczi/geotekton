extends SubViewportContainer
class_name PlanetView

# Radius of the globe mesh (SphereMesh in planet.tscn).
const GLOBE_RADIUS: float = 0.5

signal move_started(anchor_lat: float, anchor_lon: float)
signal move_to(lat: float, lon: float)
signal move_ended()
signal move_cancelled()
signal craton_clicked(lat: float, lon: float)
signal craton_hovered(lat: float, lon: float)
# Where the mouse is on the planet, NAN when it is not over the planet.
signal cursor_moved(lat: float, lon: float)

@onready var viewport: SubViewport = %SubViewport
@onready var planet: Planet = %Planet
@onready var camera: Camera3D = %Camera3D
@onready var rotation_handler: PlanetViewRotation = PlanetViewRotation.new(planet, camera)

var drawing_mode: bool = false
var move_enabled: bool = false
var is_moving: bool = false
var move_rotating: bool = false
var move_on_globe: bool = false


func start_moving(anchor_lat: float, anchor_lon: float) -> void:
	is_moving = true
	move_rotating = false
	move_on_globe = true
	move_started.emit(anchor_lat, anchor_lon)


func stop_moving() -> void:
	is_moving = false
	move_rotating = false
	move_ended.emit()


func cancel_moving() -> void:
	is_moving = false
	move_rotating = false
	move_cancelled.emit()


func _on_planet_input_event_outside(event: InputEvent) -> void:
	if is_moving:
		if event is InputEventMouseMotion:
			move_on_globe = false
		return
	if event is InputEventMouseMotion:
		craton_hovered.emit(NAN, NAN)
		cursor_moved.emit(NAN, NAN)
	if event is InputEventMouseButton:
		var p = event.position
		print("Outside click: x=%+d, y=%+d" % [roundi(p.x), roundi(p.y)])


# The background behind the globe reports the pointer as long as it is in the
# window, so moving off a craton ends the hover by itself there. Nothing
# reports it once the pointer is out of the window or over another one, and the
# view is what learns that, so end the hover here too. Without it the craton the
# pointer left stays highlighted until it comes back.
func _on_mouse_exited() -> void:
	craton_hovered.emit(NAN, NAN)
	cursor_moved.emit(NAN, NAN)


func _on_planet_input_event_globe(lat: float, lon: float, event: InputEvent) -> void:
	if is_moving:
		if event is InputEventMouseMotion and not move_rotating:
			move_on_globe = true
			move_to.emit(lat, lon)
		return
	if event is InputEventMouseButton:
		print("Globe click: lat=%+d, lon=%+d" % [roundi(lat), roundi(lon)])
		if drawing_mode and event.button_index != MOUSE_BUTTON_MIDDLE:
			return
		if not drawing_mode and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT and not Input.is_key_pressed(KEY_CTRL):
			craton_clicked.emit(lat, lon)
			return
		if event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_CTRL):
			rotation_handler.start_dragging(lat, lon)
		elif event.is_pressed() and event.button_index == MOUSE_BUTTON_MIDDLE:
			rotation_handler.start_rotating(lat, lon, event.position)
	if event is InputEventMouseMotion:
		cursor_moved.emit(lat, lon)
		if rotation_handler.is_dragging:
			rotation_handler.handle_dragging(lat, lon)
		elif not drawing_mode:
			craton_hovered.emit(lat, lon)


func _on_planet_input_event_map(lat: float, lon: float, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print("Map click: lat=%+d, lon=%+d" % [roundi(lat), roundi(lon)])
		if not drawing_mode and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT and not Input.is_key_pressed(KEY_CTRL):
			craton_clicked.emit(lat, lon)
			return
	if event is InputEventMouseMotion:
		cursor_moved.emit(lat, lon)
		if not drawing_mode:
			craton_hovered.emit(lat, lon)


func _on_gui_input(event: InputEvent) -> void:
	# Mouse wheel always works (zoom)
	if event is InputEventMouseButton and event.is_pressed():
		rotation_handler.handle_mouse_wheel(event.button_index)

	if is_moving:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_MIDDLE:
				if event.is_pressed():
					move_rotating = true
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				else:
					move_rotating = false
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif event.button_index == MOUSE_BUTTON_LEFT and event.is_released():
				if move_on_globe:
					stop_moving()
				else:
					cancel_moving()
		elif event is InputEventMouseMotion:
			if move_rotating:
				rotation_handler.handle_rotating(event.relative)
		return

	if event is InputEventMouseMotion:
		rotation_handler.handle_mouse_motion(event.relative)
	if event is InputEventMouseButton and event.is_released():
		rotation_handler.handle_mouse_button_released()


### Screen and world coordinates

# Window pixels for a point on the globe, or null when it is not visible.
# Returns null in map mode and when the point is on the far side of the globe.
func latlon_to_screen(lat: float, lon: float) -> Variant:
	if planet.show_map:
		return null

	var lat_rad := deg_to_rad(lat)
	var lon_rad := deg_to_rad(lon)
	var cos_lat := cos(lat_rad)
	var local := Vector3(-cos_lat * sin(lon_rad), sin(lat_rad), -cos_lat * cos(lon_rad)) * GLOBE_RADIUS

	var globe_transform: Transform3D = planet.globe.global_transform
	var world: Vector3 = globe_transform * local
	if (world - globe_transform.origin).dot(camera.global_position - world) <= 0.0:
		return null
	if camera.is_position_behind(world):
		return null

	var sub := camera.unproject_position(world)
	return get_viewport().get_final_transform() * (get_global_transform_with_canvas() * sub)


# Lat/lon degrees under a window pixel, or null when the ray misses the globe.
# Returns null in map mode.
func screen_to_latlon(screen: Vector2) -> Variant:
	if planet.show_map:
		return null

	var canvas: Vector2 = get_viewport().get_final_transform().affine_inverse() * screen
	var sub: Vector2 = get_global_transform_with_canvas().affine_inverse() * canvas

	var origin := camera.project_ray_origin(sub)
	var direction := camera.project_ray_normal(sub)
	var globe_transform: Transform3D = planet.globe.global_transform
	var offset: Vector3 = origin - globe_transform.origin

	# Nearest intersection of the ray with the globe sphere.
	var half_b: float = offset.dot(direction)
	var c: float = offset.length_squared() - GLOBE_RADIUS * GLOBE_RADIUS
	var discriminant: float = half_b * half_b - c
	if discriminant < 0.0:
		return null
	var root := sqrt(discriminant)
	var distance: float = -half_b - root
	if distance < 0.0:
		distance = -half_b + root
	if distance < 0.0:
		return null

	var local: Vector3 = globe_transform.affine_inverse() * (origin + direction * distance)
	var rad := Vector2(local.x, local.z).length()
	return Vector2(rad_to_deg(atan2(local.y, rad)), rad_to_deg(atan2(-local.x, -local.z)))
