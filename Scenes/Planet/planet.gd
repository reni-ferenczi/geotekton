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
