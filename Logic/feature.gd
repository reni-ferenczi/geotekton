class_name Feature


var id: String
var name: String
var enabled: bool = true
var color: Color = Color.CHOCOLATE
var vertices: Array[Vector2] = []
var parent: String = ""
var position: Vector3 = Vector3()
var time_range: Vector2i = Vector2i(0, 2000)


func _init(name: String, color: Color) -> void:
	self.id = Helpers.generate_uuid_v4()
	self.name = name
