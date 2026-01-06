extends SubViewportContainer
class_name PlanetView

@onready var viewport: SubViewport = %SubViewport
@onready var planet: Planet = %Planet

var is_dragging: bool
var drag_start_lat: float
var drag_start_lon: float
var previous_lat: float
var previous_lon: float


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_planet_input_event_outside(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var p = event.position
		print("Outside click: x=%+d, y=%+d" % [roundi(p.x), roundi(p.y)])
		

func _on_planet_input_event_globe(lat: float, lon: float, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print("Globe click: lat=%+d, lon=%+d" % [roundi(lat), roundi(lon)])
		if event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_CTRL):
			drag_start_lat = lat
			drag_start_lon = lon
			previous_lat = lat
			previous_lon = lon
			is_dragging = true
			print('Start dragging from: ', lat, ', ', lon)
		else:
			is_dragging = false
			print('Stopped dragging')
	if event is InputEventMouseMotion:
		if is_dragging:
			planet.lat = drag_start_lat + planet.lat - lat
			planet.lon = drag_start_lon + planet.lon - lon
			previous_lat = lat
			previous_lon = lon


func _on_planet_input_event_map(lat: float, lon: float, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print("Map click: lat=%+d, lon=%+d" % [roundi(lat), roundi(lon)])
