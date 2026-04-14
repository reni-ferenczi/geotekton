extends SubViewportContainer
class_name PlanetView

signal move_started(anchor_lat: float, anchor_lon: float)
signal move_to(lat: float, lon: float)
signal move_ended()
signal move_cancelled()
signal craton_clicked(lat: float, lon: float)
signal craton_hovered(lat: float, lon: float)
signal rotate_started()
signal rotate_by(delta: Vector2)
signal rotate_ended()

@onready var viewport: SubViewport = %SubViewport
@onready var planet: Planet = %Planet
@onready var camera: Camera3D = %Camera3D
@onready var rotation_handler: PlanetViewRotation = PlanetViewRotation.new(planet, camera)

var drawing_mode: bool = false
var move_enabled: bool = false
var is_moving: bool = false
var move_rotating: bool = false
var move_on_globe: bool = false
var is_rotating_craton: bool = false


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
	if event is InputEventMouseButton:
		var p = event.position
		print("Outside click: x=%+d, y=%+d" % [roundi(p.x), roundi(p.y)])


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
		if not drawing_mode:
			craton_hovered.emit(lat, lon)


func _on_gui_input(event: InputEvent) -> void:
	# Mouse wheel always works (zoom)
	if event is InputEventMouseButton and event.is_pressed():
		rotation_handler.handle_mouse_wheel(event.button_index)

	if is_rotating_craton:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_released():
			is_rotating_craton = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			rotate_ended.emit()
		elif event is InputEventMouseMotion:
			rotate_by.emit(event.relative)
		return

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

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed() and move_enabled:
		is_rotating_craton = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		rotate_started.emit()
		return

	if event is InputEventMouseMotion:
		rotation_handler.handle_mouse_motion(event.relative)
	if event is InputEventMouseButton and event.is_released():
		rotation_handler.handle_mouse_button_released()
