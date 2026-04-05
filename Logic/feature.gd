class_name Feature


# Node ID, unique only during the runtime of the application (not persisted)
var pnid: int = -1

# For human identification
var title: String

# Flags
var enabled: bool = true
var repeat: bool

# Whether this is a group (container) or a leaf feature
var is_group: bool

# Group-only fields
var children: Array[Feature] = []
var collapsed: bool
var is_root: bool

# Feature-only fields
var color: Color = Color.CHOCOLATE
var invert: bool
var single: bool
var wrap_: bool
var resize: int

# Geographic data
var vertices: Array[Vector2] = []
var position: Vector3 = Vector3()
var time_range: Vector2i = Vector2i(0, 2000)

# Numbering
static var next_pnid: int = 1


func _init():
	pass


static func create_group(title_: String = "Group") -> Feature:
	var group := Feature.new()
	group.init_pnid()
	group.title = title_
	group.is_group = true
	return group


static func create_feature(title_: String = "Feature", color_: Color = Color.CHOCOLATE) -> Feature:
	var feature := Feature.new()
	feature.init_pnid()
	feature.title = title_
	feature.color = color_
	feature.is_group = false
	return feature


func init_pnid():
	pnid = next_pnid
	next_pnid += 1


### Clone (preserves pnid) and Duplicate (new pnid)


func clone() -> Feature:
	var node := Feature.new()
	node.pnid = pnid
	node.title = title
	node.enabled = enabled
	node.repeat = repeat
	node.is_group = is_group
	node.collapsed = collapsed
	node.is_root = is_root
	node.color = color
	node.invert = invert
	node.single = single
	node.wrap_ = wrap_
	node.resize = resize
	node.vertices = vertices.duplicate()
	node.position = position
	node.time_range = time_range
	for child in children:
		node.children.append(child.clone())
	return node


func duplicate() -> Feature:
	var node := clone()
	node.init_pnid()
	node.is_root = false
	for i in range(node.children.size()):
		node.children[i] = node.children[i].duplicate()
	return node


### Tree queries


func child_count() -> int:
	return len(children)


func has_children() -> bool:
	return not children.is_empty()


func find_child(node: Feature) -> int:
	return children.find(node)


func find_parent(node: Feature) -> Feature:
	if is_same(self, node):
		return null

	var stack: Array[Feature] = [self]
	while not stack.is_empty():
		var parent: Feature = stack.pop_back()
		if not parent.is_group:
			continue
		for child in parent.children:
			if is_same(child, node):
				return parent
		stack.append_array(parent.children)

	return null


func contains_node_at_any_depth(node: Feature) -> bool:
	var stack: Array[Feature] = [self]
	while not stack.is_empty():
		var n: Feature = stack.pop_back()
		if is_same(n, node):
			return true
		if n.is_group:
			stack.append_array(n.children)
	return false


func get_node_by_pnid(pnid_: int) -> Feature:
	var stack: Array[Feature] = [self]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if node.pnid == pnid_:
			return node
		if node.is_group:
			stack.append_array(node.children)
	return null


### JSON serialization


func to_json() -> Variant:
	var data := {
		"title": title,
		"enabled": enabled,
		"repeat": repeat,
		"is_group": is_group,
	}
	if is_group:
		data["type"] = "Group"
		var children_data: Array[Variant] = []
		for child in children:
			children_data.append(child.to_json())
		data["children"] = children_data
	else:
		data["type"] = "Feature"
		data["color"] = [color.r, color.g, color.b, color.a]
		data["invert"] = invert
		data["single"] = single
		data["wrap"] = wrap_
		data["resize"] = resize
		data["vertices"] = _vertices_to_json()
		data["position"] = [position.x, position.y, position.z]
		data["time_range"] = [time_range.x, time_range.y]
	return data


static func from_json(data: Variant) -> Feature:
	var node := Feature.new()
	node.init_pnid()
	node.title = data["title"]
	node.enabled = data.get("enabled", true)
	node.repeat = data.get("repeat", false)
	node.is_group = data.get("is_group", data.get("type") == "Group")
	if node.is_group:
		node.collapsed = true
		for child_data in data.get("children", []):
			node.children.append(Feature.from_json(child_data))
	else:
		var c: Array = data.get("color", [0.82, 0.41, 0.12, 1.0])
		node.color = Color(c[0], c[1], c[2], c[3])
		node.invert = data.get("invert", false)
		node.single = data.get("single", false)
		node.wrap_ = data.get("wrap", false)
		node.resize = data.get("resize", 0)
		node._vertices_from_json(data.get("vertices", []))
		var p: Array = data.get("position", [0, 0, 0])
		node.position = Vector3(p[0], p[1], p[2])
		var tr: Array = data.get("time_range", [0, 2000])
		node.time_range = Vector2i(tr[0], tr[1])
	return node


func _vertices_to_json() -> Array:
	var result: Array = []
	for v in vertices:
		result.append([v.x, v.y])
	return result


func _vertices_from_json(data: Array) -> void:
	vertices.clear()
	for v in data:
		vertices.append(Vector2(v[0], v[1]))
