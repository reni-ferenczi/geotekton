class_name Project


var id: String
var name: String
var features: Dictionary[String, Feature] = {}
var full_time_range: int = 2000


func _init(name: String, color: Color) -> void:
	self.id = Helpers.generate_uuid_v4()
	self.name = name
