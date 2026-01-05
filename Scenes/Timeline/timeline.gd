extends PanelContainer
class_name Timeline

@export_range(100, 10000, 100, "Full duration (maximum age)") var full_duration: int = 2000

@onready var timestamp_slider: HSlider = %TimestampSlider

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	timestamp_slider.max_value = full_duration
	timestamp_slider.value = 2000
