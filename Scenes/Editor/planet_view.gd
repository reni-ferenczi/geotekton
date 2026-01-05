extends SubViewportContainer
class_name PlanetView

@onready var viewport: SubViewport = %SubViewport
@onready var planet: Planet = %Planet


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
		if event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			planet.lat = lat
			planet.lon = lon


func _on_planet_input_event_map(lat: float, lon: float, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print("Map click: lat=%+d, lon=%+d" % [roundi(lat), roundi(lon)])
