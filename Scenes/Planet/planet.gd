@tool
extends Node3D
class_name Planet

@export var show_map: bool = false;
@export_range(-90, 90, 1.0, "Latitude") var lat: float = 0.0;
@export_range(-180, 180, 1.0, "Longitude") var lon: float = 0.0;
@export_range(-180, 180, 1.0, "Angle") var angle: float = 0.0;

@onready var globe = $Globe;
@onready var map = $Map;


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	globe.visible = not show_map
	map.visible = show_map
	
	if globe:
		globe.rotation = Vector3(deg_to_rad(lat), deg_to_rad(180 - lon), deg_to_rad(angle))
