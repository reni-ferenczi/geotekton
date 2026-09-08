extends SubViewportContainer
class_name PlanetView

# Radius of the globe, the one Planet gives to both the mesh and the collision
# shape, so the maths here agrees with what a click is picked against.
const GLOBE_RADIUS: float = Planet.GLOBE_RADIUS

# The field of view planet_view.tscn lays the camera out with. Zoom 1 shows the
# globe through exactly that, which is the space the view has always given it.
# The globe and a map sheet both sit at the middle of the scene, the same
# distance from the camera, so fitting a sheet into that same space is a matter
# of the ratio of what has to fit and the distance never comes into it.
const BASE_FOV := 60.0

# What the zoom may be, and what one press of zoom in or out multiplies it by.
# One is the whole planet in view and a hundred is a few degrees across the
# window; a little over four presses double it.
const MIN_ZOOM := 1.0
const MAX_ZOOM := 100.0
const DEFAULT_ZOOM := 1.0
const ZOOM_STEP := 1.2

# The mouse on the planet, and off it. Where the pointer is is worked out from
# the pixel it is over, by the same screen_to_latlon() the automation port and
# the tests use, so a click and a scripted click cannot disagree.
signal input_event_globe(lat: float, lon: float, event: InputEvent)
signal input_event_map(lat: float, lon: float, event: InputEvent)
signal input_event_outside(event: InputEvent)

signal move_started(anchor_lat: float, anchor_lon: float)
signal move_to(lat: float, lon: float)
signal move_ended()
signal move_cancelled()
signal craton_clicked(lat: float, lon: float)
# A right click asking for the Edit commands on whatever is under the pointer.
signal craton_context_menu(lat: float, lon: float)
signal craton_hovered(lat: float, lon: float)
# Where the mouse is on the planet, NAN when it is not over the planet.
signal cursor_moved(lat: float, lon: float)

@onready var viewport: SubViewport = %SubViewport
@onready var planet: Planet = %Planet
@onready var camera: Camera3D = %Camera3D
@onready var rotation_handler: PlanetViewRotation = PlanetViewRotation.new(planet)

# True while a tool takes the clicks on the planet for itself: Draw placing
# vertices, Vertex editing them, Measure marking points. Selecting a feature,
# moving one and the right click menu are all left alone until it is false
# again. Rotating the globe with the middle button always works.
var tool_handles_clicks: bool = false

# How far the view is zoomed in, 1 being the whole planet. The camera's field of
# view is worked out from it every frame, together with what is being shown, so
# nothing else has to remember which projection is on screen.
var zoom: float = DEFAULT_ZOOM

var move_enabled: bool = false
var is_moving: bool = false
var move_rotating: bool = false
var move_on_globe: bool = false


func _process(_delta: float) -> void:
	camera.fov = _fov_for_view()
	# The camera is what turns and slides; the globe turns to face the latitude
	# and longitude it is pointed at, and a map re-projects about them.
	camera.rotation.z = deg_to_rad(planet.angle)
	camera.position.y = _camera_offset()


### Zoom and camera


func set_zoom(value: float) -> void:
	zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)


func zoom_in() -> void:
	set_zoom(zoom * ZOOM_STEP)


func zoom_out() -> void:
	set_zoom(zoom / ZOOM_STEP)


func reset_zoom() -> void:
	set_zoom(DEFAULT_ZOOM)


# Point the camera back at the middle of the planet, the right way up.
func reset_camera() -> void:
	planet.lat = 0.0
	planet.lon = 0.0
	planet.angle = 0.0


# How far up the camera stands, so that the latitude it is pointed at is in the
# middle of the view. Only a map needs it: the globe turns to face that latitude
# and an orthographic map centres its whole hemisphere on it, so both of those
# leave the camera where the scene puts it.
#
# The offset stops where the edge of the sheet would come inside the view, so at
# zoom 1, with the whole of the sheet on screen, there is nowhere to slide to and
# the latitude is only worth typing once the view is zoomed in.
func _camera_offset() -> float:
	if not planet.show_map or planet.projection == MapProjection.Kind.ORTHOGRAPHIC:
		return 0.0
	var extent := MapProjection.extent(planet.projection)
	var centre := Vector2(planet.lat, planet.lon)
	var plane = MapProjection.forward(planet.projection, centre, centre)
	# A latitude the projection does not reach at all, which is what Mercator
	# answers near a pole; the top of the sheet is as far as the view can go.
	var wanted: float = signf(planet.lat) * extent if plane == null else plane.y
	var visible := camera.position.z * tan(deg_to_rad(camera.fov) * 0.5)
	var room := maxf(extent - visible, 0.0)
	return clampf(wanted, -room, room)


# The field of view that fits what is on screen into the window at the current
# zoom. The globe needs its radius; a map needs half the height of the
# projection's sheet, or half its width divided by the aspect ratio when the
# sheet is the wider of the two, which is what a rectangular one is. Both are
# measured against the globe, so that zoom 1 on the globe is the field of view
# the scene was laid out with and every other view gets the same margin.
func _fov_for_view() -> float:
	var needed := GLOBE_RADIUS
	if planet.show_map:
		var size := viewport.size
		var aspect := float(size.x) / float(maxi(size.y, 1))
		needed = maxf(MapProjection.extent(planet.projection), 1.0 / aspect)
	var half_height := tan(deg_to_rad(BASE_FOV) * 0.5) * needed / GLOBE_RADIUS / zoom
	return rad_to_deg(2.0 * atan(half_height))


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
		if tool_handles_clicks and event.button_index != MOUSE_BUTTON_MIDDLE:
			return
		if not tool_handles_clicks and event.is_pressed() and event.button_index == MOUSE_BUTTON_RIGHT:
			craton_context_menu.emit(lat, lon)
			return
		if not tool_handles_clicks and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT and not Input.is_key_pressed(KEY_CTRL):
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
		elif not tool_handles_clicks:
			craton_hovered.emit(lat, lon)


func _on_planet_input_event_map(lat: float, lon: float, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print("Map click: lat=%+d, lon=%+d" % [roundi(lat), roundi(lon)])
		if not tool_handles_clicks and event.is_pressed() and event.button_index == MOUSE_BUTTON_RIGHT:
			craton_context_menu.emit(lat, lon)
			return
		if not tool_handles_clicks and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT and not Input.is_key_pressed(KEY_CTRL):
			craton_clicked.emit(lat, lon)
			return
	if event is InputEventMouseMotion:
		cursor_moved.emit(lat, lon)
		if not tool_handles_clicks:
			craton_hovered.emit(lat, lon)


func _on_gui_input(event: InputEvent) -> void:
	# Mouse wheel always works (zoom)
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()

	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_report_pointer(event)

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


# Hand one mouse event to whatever is under the pointer: the globe, the map, or
# neither. The view answers it first, for the selection, the hover and the drags
# it owns, and then passes it on to the Application for the tool that is armed.
func _report_pointer(event: InputEvent) -> void:
	var point = _view_to_latlon(event.position)
	if point == null:
		_on_planet_input_event_outside(event)
		input_event_outside.emit(event)
	elif planet.show_map:
		_on_planet_input_event_map(point.x, point.y, event)
		input_event_map.emit(point.x, point.y, event)
	else:
		_on_planet_input_event_globe(point.x, point.y, event)
		input_event_globe.emit(point.x, point.y, event)


### Screen and world coordinates
#
# Every click, every hover and every scripted check goes through these two, on
# the globe and on the map alike. The globe is met by a ray against a sphere of
# the drawn radius; the map by the same ray meeting the sheet, with
# MapProjection saying which point of the planet a place of the sheet shows.
# "View" here is a pixel of the planet view; "screen" is a window pixel, which
# is what the automation port and the tests speak in.


# Window pixels for a point on the planet, or null when it is not on screen: the
# far side of the globe, or a latitude and longitude the projection does not
# draw.
func latlon_to_screen(lat: float, lon: float) -> Variant:
	var point = _latlon_to_view(lat, lon)
	if point == null:
		return null
	return get_viewport().get_final_transform() * (get_global_transform_with_canvas() * point)


# Lat/lon degrees under a window pixel, or null when there is no planet there.
func screen_to_latlon(screen: Vector2) -> Variant:
	var canvas: Vector2 = get_viewport().get_final_transform().affine_inverse() * screen
	return _view_to_latlon(get_global_transform_with_canvas().affine_inverse() * canvas)


# Where a point of the planet lands in the view, or null when it is not drawn.
func _latlon_to_view(lat: float, lon: float) -> Variant:
	var scene = _latlon_to_scene(lat, lon)
	if scene == null:
		return null
	var world: Vector3 = planet.global_transform * (scene as Vector3)
	if camera.is_position_behind(world):
		return null
	return camera.unproject_position(world)


# Where a point of the planet sits in the scene, in the planet's own frame, or
# null when what is being shown does not reach it.
func _latlon_to_scene(lat: float, lon: float) -> Variant:
	if planet.show_map:
		var plane = MapProjection.forward(
			planet.projection, Vector2(lat, lon), Vector2(planet.lat, planet.lon))
		return null if plane == null else Planet.map_to_scene(plane)

	var lat_rad := deg_to_rad(lat)
	var lon_rad := deg_to_rad(lon)
	var cos_lat := cos(lat_rad)
	var on_globe := Vector3(
		-cos_lat * sin(lon_rad), sin(lat_rad), -cos_lat * cos(lon_rad)) * GLOBE_RADIUS
	var globe_transform: Transform3D = planet.globe.transform
	var scene: Vector3 = globe_transform * on_globe
	# The far side of the globe, which the near side hides.
	var eye: Vector3 = planet.global_transform.affine_inverse() * camera.global_position
	if (scene - globe_transform.origin).dot(eye - scene) <= 0.0:
		return null
	return scene


# Lat/lon degrees under a point of the view, or null when there is no planet
# under it.
func _view_to_latlon(point: Vector2) -> Variant:
	var to_planet := planet.global_transform.affine_inverse()
	var origin: Vector3 = to_planet * camera.project_ray_origin(point)
	var direction: Vector3 = to_planet.basis * camera.project_ray_normal(point)
	if planet.show_map:
		return _map_latlon(origin, direction)
	return _globe_latlon(origin, direction)


# Where a ray meets the map sheet, and which point of the planet the projection
# draws there. The sheet is a plane, so the ray meets it at most once.
func _map_latlon(origin: Vector3, direction: Vector3) -> Variant:
	if absf(direction.z) < 1e-9:
		return null
	var distance := -origin.z / direction.z
	if distance < 0.0:
		return null
	return MapProjection.inverse(
		planet.projection,
		Planet.scene_to_map(origin + direction * distance),
		Vector2(planet.lat, planet.lon))


# Where a ray meets the globe, at the nearer of the two crossings.
func _globe_latlon(origin: Vector3, direction: Vector3) -> Variant:
	var globe_transform: Transform3D = planet.globe.transform
	var offset: Vector3 = origin - globe_transform.origin

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
