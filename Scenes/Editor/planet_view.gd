extends SubViewportContainer
class_name PlanetView

const PlanetViewRotation = preload("res://Scenes/Editor/planet_view_rotation.gd")

@onready var viewport: SubViewport = %SubViewport
@onready var planet: Planet = %Planet
@onready var camera: Camera3D = %Camera3D
@onready var rotation_handler: PlanetViewRotation = PlanetViewRotation.new(planet, camera)


func _on_planet_input_event_outside(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var p = event.position
		print("Outside click: x=%+d, y=%+d" % [roundi(p.x), roundi(p.y)])
		

func _on_planet_input_event_globe(lat: float, lon: float, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print("Globe click: lat=%+d, lon=%+d" % [roundi(lat), roundi(lon)])
		if event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_CTRL):
			rotation_handler.start_dragging(lat, lon)
		elif event.is_pressed() and event.button_index == MOUSE_BUTTON_MIDDLE:
			rotation_handler.start_rotating(lat, lon, event.position)
	if event is InputEventMouseMotion:
		if rotation_handler.is_dragging:
			rotation_handler.handle_dragging(lat, lon)


func _on_planet_input_event_map(lat: float, lon: float, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print("Map click: lat=%+d, lon=%+d" % [roundi(lat), roundi(lon)])


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		rotation_handler.handle_mouse_wheel(event.button_index)
	if event is InputEventMouseMotion:
		rotation_handler.handle_mouse_motion(event.relative)
	if event is InputEventMouseButton and event.is_released():
		rotation_handler.handle_mouse_button_released()
