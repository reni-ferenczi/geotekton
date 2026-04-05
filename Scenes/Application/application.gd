extends VBoxContainer
class_name Application


static var DEBUG: bool = true
const ui_scale: float = 1.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var root := get_tree().root
	root.content_scale_factor = Application.ui_scale


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
