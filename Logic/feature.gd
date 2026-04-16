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
#
# Source of truth: user-drawn polygon outlines, stored as ordered vertex loops
# in local (unrotated) space. Each loop is a PackedVector2Array of (lat_deg, lon_deg).
var outlines: Array[PackedVector2Array] = []
# Derived triangle soup: every 3 consecutive vertices form one front-facing
# triangle. Rebuilt from `outlines` via ear clipping whenever outlines change.
# Rendering reads this field directly.
var triangles: Array[Vector2] = []
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
	node.outlines.clear()
	for loop in outlines:
		node.outlines.append(loop.duplicate())
	node.triangles = triangles.duplicate()
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


### Outline mutation


func has_craton() -> bool:
	return not outlines.is_empty()


func set_outlines(new_outlines: Array[PackedVector2Array]) -> void:
	outlines = new_outlines
	_rebuild_triangles()


func add_outline(loop: PackedVector2Array) -> void:
	outlines.append(loop)
	_rebuild_triangles()


func clear_outlines() -> void:
	outlines.clear()
	triangles.clear()


# Flat list of all vertices across every outline loop (useful for centroid).
func all_outline_points() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for loop in outlines:
		for v in loop:
			result.append(v)
	return result


func _rebuild_triangles() -> void:
	triangles.clear()
	for loop in outlines:
		var loop_arr: Array[Vector2] = []
		for v in loop:
			loop_arr.append(v)
		var tris := _ear_clip(loop_arr)
		for i in range(0, tris.size() - 2, 3):
			_ensure_front_winding(tris, i)
		triangles.append_array(tris)


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
		data["outlines"] = _outlines_to_json()
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
		if data.has("outlines"):
			node._outlines_from_json(data["outlines"])
		else:
			# Legacy format (pre-outlines): a flat triangle soup stored under
			# "vertices". The original polygons are gone, so each triangle
			# becomes its own 3-vertex outline loop — re-triangulation then
			# yields the same triangles back.
			node._outlines_from_legacy_vertices(data.get("vertices", []))
		node._rebuild_triangles()
		var r: Array = data.get("rotation", data.get("position", [0, 0, 0]))
		node.rotation_angles = Vector3(r[0], r[1], r[2])
		var tr: Array = data.get("time_range", [0, 2000])
		node.time_range = Vector2i(tr[0], tr[1])
	return node


func _outlines_to_json() -> Array:
	var result: Array = []
	for loop in outlines:
		var loop_data: Array = []
		for v in loop:
			loop_data.append([v.x, v.y])
		result.append(loop_data)
	return result


func _outlines_from_json(data: Array) -> void:
	outlines.clear()
	for loop_data in data:
		var loop := PackedVector2Array()
		for v in loop_data:
			loop.append(Vector2(v[0], v[1]))
		outlines.append(loop)


func _outlines_from_legacy_vertices(data: Array) -> void:
	outlines.clear()
	var i := 0
	while i + 2 < data.size():
		var a: Array = data[i]
		var b: Array = data[i + 1]
		var c: Array = data[i + 2]
		var loop := PackedVector2Array()
		loop.append(Vector2(a[0], a[1]))
		loop.append(Vector2(b[0], b[1]))
		loop.append(Vector2(c[0], c[1]))
		outlines.append(loop)
		i += 3


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


# Compute rotation angles that rotate anchor_world toward target_world around a fixed axis.
# Only the rotation component around `axis_world` is applied to base_rot.
# Returns Vector3 of degrees or null if anchor or target lies on the axis (undefined angle).
static func compute_axis_rotation(axis_world: Vector3, anchor_world: Vector3, target_world: Vector3, base_rot: Vector3) -> Variant:
	var axis := axis_world.normalized()
	var a_perp := anchor_world - axis * axis.dot(anchor_world)
	var t_perp := target_world - axis * axis.dot(target_world)
	if a_perp.length() < 1e-4 or t_perp.length() < 1e-4:
		return null
	a_perp = a_perp.normalized()
	t_perp = t_perp.normalized()
	var cos_a := clampf(a_perp.dot(t_perp), -1.0, 1.0)
	var sin_a := axis.dot(a_perp.cross(t_perp))
	var angle := atan2(sin_a, cos_a)
	var m_new := Basis(axis, angle) * _build_rotation_basis(base_rot)
	return _decompose_rotation_degrees(m_new)


### Ear-clipping triangulation


static func _ear_clip(polygon: Array[Vector2]) -> Array[Vector2]:
	var n := polygon.size()
	if n < 3:
		return []

	var result: Array[Vector2] = []

	var idx: Array[int] = []
	for i in range(n):
		idx.append(i)

	# Determine winding direction using signed area (shoelace formula)
	var area := 0.0
	for i in range(n):
		var j := (i + 1) % n
		area += polygon[i].x * polygon[j].y - polygon[j].x * polygon[i].y
	var winding_sign := 1.0 if area > 0.0 else -1.0

	var max_iterations := n * n
	var iter := 0
	var i := 0

	while idx.size() > 3 and iter < max_iterations:
		iter += 1
		var sz := idx.size()
		var prev := (i - 1 + sz) % sz
		var next := (i + 1) % sz

		var a := polygon[idx[prev]]
		var b := polygon[idx[i]]
		var c := polygon[idx[next]]

		var cross_val := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
		if cross_val * winding_sign <= 0.0:
			i = (i + 1) % sz
			continue

		var is_ear := true
		for k in range(sz):
			if k == prev or k == i or k == next:
				continue
			if _point_in_triangle(polygon[idx[k]], a, b, c):
				is_ear = false
				break

		if is_ear:
			result.append(a)
			result.append(b)
			result.append(c)
			idx.remove_at(i)
			if i >= idx.size():
				i = 0
		else:
			i = (i + 1) % idx.size()

	if idx.size() == 3:
		result.append(polygon[idx[0]])
		result.append(polygon[idx[1]])
		result.append(polygon[idx[2]])

	return result


static func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)


static func _ensure_front_winding(verts: Array[Vector2], start: int) -> void:
	var a := _latlon_to_xyz_s(verts[start])
	var b := _latlon_to_xyz_s(verts[start + 1])
	var c := _latlon_to_xyz_s(verts[start + 2])

	var normal := (b - a).cross(c - a)
	var center := (a + b + c) / 3.0

	if normal.dot(center) < 0:
		var tmp := verts[start + 1]
		verts[start + 1] = verts[start + 2]
		verts[start + 2] = tmp


### Great-circle segment helpers (for EDIT tool hit-testing)


# Returns chord distance from point p to the great-circle arc a→b, plus the
# projected world-space point on the arc (or the nearest endpoint if p is
# outside the arc's perpendicular slab).
# All arguments are unit-length xyz vectors. Result keys: "dist", "proj", "on_arc".
static func great_circle_edge_distance(p: Vector3, a: Vector3, b: Vector3) -> Dictionary:
	var n := a.cross(b)
	if n.length() < 1e-9:
		return {"dist": (p - a).length(), "proj": a, "on_arc": false}
	n = n.normalized()
	var perp_a := n.cross(a)
	var perp_b := b.cross(n)
	var on_arc := perp_a.dot(p) >= 0.0 and perp_b.dot(p) >= 0.0
	if on_arc:
		var proj := (p - n * n.dot(p))
		if proj.length() < 1e-9:
			return {"dist": 1.0, "proj": a, "on_arc": false}
		proj = proj.normalized()
		var dist := sqrt(2.0 * max(0.0, 1.0 - proj.dot(p)))
		return {"dist": dist, "proj": proj, "on_arc": true}
	var da := sqrt(2.0 * max(0.0, 1.0 - a.dot(p)))
	var db := sqrt(2.0 * max(0.0, 1.0 - b.dot(p)))
	if da < db:
		return {"dist": da, "proj": a, "on_arc": false}
	return {"dist": db, "proj": b, "on_arc": false}


# Test whether two great-circle arcs (a→b and c→d) cross on the sphere.
# Endpoints are not treated as intersections.
static func great_circle_arcs_intersect(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
	var n1 := a.cross(b)
	var n2 := c.cross(d)
	if n1.length() < 1e-9 or n2.length() < 1e-9:
		return false
	var dir := n1.cross(n2)
	if dir.length() < 1e-9:
		return false
	dir = dir.normalized()
	return _arc_contains(dir, a, b, n1) and _arc_contains(dir, c, d, n2) \
		or _arc_contains(-dir, a, b, n1) and _arc_contains(-dir, c, d, n2)


static func _arc_contains(p: Vector3, a: Vector3, b: Vector3, n: Vector3) -> bool:
	# Strictly inside: reject endpoints to avoid flagging shared corners.
	var perp_a := n.cross(a)
	var perp_b := b.cross(n)
	return perp_a.dot(p) > 1e-6 and perp_b.dot(p) > 1e-6


# Test whether a closed polygon (array of world-space xyz unit vectors) has any
# pair of non-adjacent great-circle edges that cross.
static func polygon_self_intersects(verts_world: Array) -> bool:
	var n := verts_world.size()
	if n < 4:
		return false
	for i in range(n):
		var a: Vector3 = verts_world[i]
		var b: Vector3 = verts_world[(i + 1) % n]
		for j in range(i + 2, n):
			# Skip adjacency (edges sharing a vertex)
			if i == 0 and j == n - 1:
				continue
			var c: Vector3 = verts_world[j]
			var d: Vector3 = verts_world[(j + 1) % n]
			if great_circle_arcs_intersect(a, b, c, d):
				return true
	return false


static func _latlon_to_xyz_s(v: Vector2) -> Vector3:
	var lat_rad := deg_to_rad(v.x)
	var lon_rad := deg_to_rad(v.y)
	var cos_lat := cos(lat_rad)
	return Vector3(cos_lat * cos(lon_rad), sin(lat_rad), cos_lat * sin(lon_rad))


static func _xyz_to_latlon_s(p: Vector3) -> Vector2:
	return Vector2(rad_to_deg(asin(clampf(p.y, -1.0, 1.0))), rad_to_deg(atan2(p.z, p.x)))
