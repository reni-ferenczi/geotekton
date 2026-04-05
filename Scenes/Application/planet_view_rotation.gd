class_name PlanetViewRotation

var planet: Planet
var camera: Camera3D

var is_dragging: bool
var is_rotating: bool
var drag_start_lat: float
var drag_start_lon: float
var drag_start_pos: Vector2
var previous_lat: float
var previous_lon: float

const ENABLE_ANGLE: bool = false
const MIN_FOV: float = 15.0
const MAX_FOV: float = 90.0
const FOV_STEP: float = 3.0
const ROTATION_SENSITIVITY: Vector2 = Vector2(0.5, 0.5)


func _init(planet: Planet, camera: Camera3D):
	self.planet = planet
	self.camera = camera

func start_dragging(lat: float, lon: float):
	print('Start dragging from: ', lat, ', ', lon)
	is_dragging = true
	drag_start_lat = lat
	drag_start_lon = lon
	previous_lat = lat
	previous_lon = lon


func handle_dragging(lat: float, lon: float):
	planet.lat = drag_start_lat + planet.lat - lat
	planet.lon = drag_start_lon + planet.lon - lon
	previous_lat = lat
	previous_lon = lon


func start_rotating(lat: float, lon: float, pos: Vector2):
	print('Start rotating from: ', lat, ', ', lon)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	is_rotating = true


func handle_rotating(rel: Vector2):
	var delta = rel * ROTATION_SENSITIVITY
	planet.lat += delta.y
	planet.lon -= delta.x

	# Clamp latitude to -90..90 degrees
	planet.lat = clamp(planet.lat, -90.0, 90.0)

	# Wrap longitude to -180..180 degrees
	planet.lon = fmod(planet.lon + 180.0, 360.0) - 180.0


func handle_rotating_angle(rel: Vector2):
	var delta = rel * ROTATION_SENSITIVITY
	planet.angle += delta.x

	# Wrap angle to -180..180 degrees
	planet.angle = fmod(planet.angle + 180.0, 360.0) - 180.0


func cancel():
	if is_dragging:
		print('Stopped dragging')
		is_dragging = false
	if is_rotating:
		print('Stopped rotating')
		is_rotating = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func handle_mouse_wheel(button_index: int):
	if button_index == MOUSE_BUTTON_WHEEL_UP:
		camera.fov = clamp(camera.fov - FOV_STEP, MIN_FOV, MAX_FOV)
	elif button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera.fov = clamp(camera.fov + FOV_STEP, MIN_FOV, MAX_FOV)


func handle_mouse_motion(rel: Vector2):
	if is_rotating:
		if ENABLE_ANGLE and Input.is_key_pressed(KEY_SHIFT):
			handle_rotating_angle(rel)
		else:
			handle_rotating(rel)


func handle_mouse_button_released():
	cancel()
