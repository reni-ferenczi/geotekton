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
var rotation_angles: Vector3 = Vector3.ZERO
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
	node.rotation_angles = rotation_angles
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
		data["rotation"] = [rotation_angles.x, rotation_angles.y, rotation_angles.z]
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
		var r: Array = data.get("rotation", data.get("position", [0, 0, 0]))
		node.rotation_angles = Vector3(r[0], r[1], r[2])
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


### Rotation helpers


# Build rotation Basis from angles (degrees): R = Ry(rot.x) * Rx(rot.y) * Rz(rot.z)
static func _build_rotation_basis(rot: Vector3) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(rot.x)) \
		* Basis(Vector3.RIGHT, deg_to_rad(rot.y)) \
		* Basis(Vector3.BACK, deg_to_rad(rot.z))


# Extract (α, β, γ) in degrees from M = Ry(α) * Rx(β) * Rz(γ)
# Note: Godot Basis uses m[column][row], so standard M[row][col] = m[col][row]
static func _decompose_rotation_degrees(m: Basis) -> Vector3:
	var sin_beta := clampf(-m[2][1], -1.0, 1.0)
	var beta := asin(sin_beta)
	var cos_beta := cos(beta)

	var alpha: float
	var gamma: float
	if cos_beta > 0.0001:
		alpha = atan2(m[2][0], m[2][2])
		gamma = atan2(m[0][1], m[1][1])
	else:
		# Gimbal lock (β ≈ ±90°): set γ = 0, solve α
		gamma = 0.0
		alpha = atan2(-m[0][2], m[0][0])

	return Vector3(rad_to_deg(alpha), rad_to_deg(beta), rad_to_deg(gamma))


static func apply_rotation(verts: Array[Vector2], rot: Vector3) -> Array[Vector2]:
	if rot.is_zero_approx():
		return verts
	var m := _build_rotation_basis(rot)
	var result: Array[Vector2] = []
	result.resize(verts.size())
	for i in range(verts.size()):
		result[i] = _xyz_to_latlon_s(m * _latlon_to_xyz_s(verts[i]))
	return result


static func unapply_rotation(verts: Array[Vector2], rot: Vector3) -> Array[Vector2]:
	if rot.is_zero_approx():
		return verts
	var m_inv := _build_rotation_basis(rot).transposed()
	var result: Array[Vector2] = []
	result.resize(verts.size())
	for i in range(verts.size()):
		result[i] = _xyz_to_latlon_s(m_inv * _latlon_to_xyz_s(verts[i]))
	return result


# Compute rotation angles that move anchor_world to target_world, composing with base_rot.
# Uses great-circle delta rotation + YXZ Euler decomposition for full sphere coverage.
# Returns Vector3 of degrees or null if the points are antipodal.
static func compute_move_rotation(anchor_world: Vector3, target_world: Vector3, base_rot: Vector3) -> Variant:
	var dot_val := anchor_world.dot(target_world)
	if dot_val > 0.9999:
		return base_rot
	if dot_val < -0.9999:
		return null

	var axis := anchor_world.cross(target_world).normalized()
	var angle := acos(clampf(dot_val, -1.0, 1.0))
	var m_new := Basis(axis, angle) * _build_rotation_basis(base_rot)
	return _decompose_rotation_degrees(m_new)


static func _latlon_to_xyz_s(v: Vector2) -> Vector3:
	var lat_rad := deg_to_rad(v.x)
	var lon_rad := deg_to_rad(v.y)
	var cos_lat := cos(lat_rad)
	return Vector3(cos_lat * cos(lon_rad), sin(lat_rad), cos_lat * sin(lon_rad))


static func _xyz_to_latlon_s(p: Vector3) -> Vector2:
	return Vector2(rad_to_deg(asin(clampf(p.y, -1.0, 1.0))), rad_to_deg(atan2(p.z, p.x)))
