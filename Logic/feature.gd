class_name Feature


# What the vertices of a feature describe. A feature holds one kind of
# geometry; drawing a second shape on it adds another part of the same kind.
enum GeometryKind { POLYGON, POLYLINE, MULTIPOINT }

# The kind as it appears in a file, and back.
const KIND_NAMES := {
	GeometryKind.POLYGON: "polygon",
	GeometryKind.POLYLINE: "polyline",
	GeometryKind.MULTIPOINT: "multipoint",
}
const KIND_VALUES := {
	"polygon": GeometryKind.POLYGON,
	"polyline": GeometryKind.POLYLINE,
	"multipoint": GeometryKind.MULTIPOINT,
}

# How many vertices one part of each kind needs before it is a shape. The Draw
# tool commits nothing below it and an edit that would take a part under it
# removes the part instead.
const MINIMUM_VERTICES := {
	GeometryKind.POLYGON: 3,
	GeometryKind.POLYLINE: 2,
	GeometryKind.MULTIPOINT: 1,
}

# The longest title a feature keeps; anything longer is cut down to it.
const MAX_TITLE_LENGTH := 100

# Node ID, unique only during the runtime of the application (not persisted)
var pnid: int = -1

# For human identification
var title: String

# Flags
var enabled: bool = true

# Whether this is a group (container) or a leaf feature
var is_group: bool

# Group-only fields
var children: Array[Feature] = []
var collapsed: bool
var is_root: bool

# Feature-only fields
# What the feature is, an id in FeatureType.CATALOG. The type says which
# geometry kinds the feature may hold and which colour it starts in.
var feature_type: String = FeatureType.UNCLASSIFIED
var color: Color = FeatureType.color(FeatureType.UNCLASSIFIED)

# Geographic data. Each ring is a run of (latitude, longitude) vertices in
# degrees, in the frame of the feature itself, before the rotation its
# keyframes give it at the current time is applied. What a ring means follows
# geometry_kind: a closed boundary for a polygon, an open line for a polyline, a
# bag of separate points for a multipoint. A feature may hold several rings; for
# a polygon those are separate outlines rather than holes.
var geometry_kind: GeometryKind = GeometryKind.POLYGON
var rings: Array[PackedVector2Array] = []

# Triangles covering the polygon rings, 3 vertices each, wound so that they face
# outwards. Derived from rings by rebuild_triangles(), never read from a file.
var triangles := PackedVector2Array()

# How the node turns over time, sorted by time. A group has these too: its
# children inherit its motion, which is what takes the place of a GPlates plate
# circuit. An empty list means the node does not move at all.
var keyframes: Array[Keyframe] = []

# The ages between which a feature exists, in millions of years before present.
# A feature outside it at the current time is neither drawn nor hit tested. Only
# a leaf feature has one; a group is there whenever its children are.
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


static func create_feature(title_: String = "Feature",
		color_: Color = FeatureType.color(FeatureType.UNCLASSIFIED)) -> Feature:
	var feature := Feature.new()
	feature.init_pnid()
	feature.title = title_
	feature.color = color_
	feature.is_group = false
	return feature


# A title as a feature keeps it: trimmed, and cut down to MAX_TITLE_LENGTH.
static func clamp_title(value: String) -> String:
	var title_ := value.strip_edges()
	return title_ if title_.length() <= MAX_TITLE_LENGTH else title_.left(MAX_TITLE_LENGTH) + "..."


func init_pnid():
	pnid = next_pnid
	next_pnid += 1


### Geometry


# The geometry kind under the name the file and the type catalog use.
func kind_name() -> String:
	return str(KIND_NAMES[geometry_kind])


func minimum_vertices() -> int:
	return int(MINIMUM_VERTICES[geometry_kind])


func has_geometry() -> bool:
	for ring in rings:
		if not ring.is_empty():
			return true
	return false


# Whether anything under this node can be drawn, the node itself included. A
# group is worth dragging exactly when something inside it would move with it.
func holds_geometry() -> bool:
	if not is_group:
		return has_geometry()
	for child in children:
		if child.holds_geometry():
			return true
	return false


func vertex_count() -> int:
	var total := 0
	for ring in rings:
		total += ring.size()
	return total


# Recompute the cached triangles from the rings. Only a polygon has any; the
# other kinds are drawn and hit tested from their vertices directly.
func rebuild_triangles() -> void:
	triangles = PackedVector2Array()
	if geometry_kind != GeometryKind.POLYGON:
		return
	for ring in rings:
		var ring_triangles := ear_clip(ring)
		for i in range(0, ring_triangles.size() - 2, 3):
			ensure_front_winding(ring_triangles, i)
		triangles.append_array(ring_triangles)


# Add one drawn shape to the feature, adopting the kind when it is the first.
func add_ring(ring: PackedVector2Array, kind: GeometryKind) -> void:
	if not has_geometry():
		geometry_kind = kind
		rings.clear()
	rings.append(ring)
	rebuild_triangles()


### Clone (preserves pnid) and Duplicate (new pnid)


func clone() -> Feature:
	var node := Feature.new()
	node.pnid = pnid
	node.title = title
	node.enabled = enabled
	node.is_group = is_group
	node.collapsed = collapsed
	node.is_root = is_root
	node.feature_type = feature_type
	node.color = color
	node.geometry_kind = geometry_kind
	for ring in rings:
		node.rings.append(ring.duplicate())
	# Copied rather than recomputed: every undo step clones the whole tree.
	node.triangles = triangles.duplicate()
	node.keyframes = Keyframe.clone_list(keyframes)
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
		"is_group": is_group,
		"keyframes": Keyframe.list_to_json(keyframes),
	}
	if is_group:
		data["type"] = "Group"
		var children_data: Array[Variant] = []
		for child in children:
			children_data.append(child.to_json())
		data["children"] = children_data
	else:
		data["type"] = "Feature"
		data["feature_type"] = feature_type
		data["color"] = [color.r, color.g, color.b, color.a]
		data["geometry_kind"] = KIND_NAMES[geometry_kind]
		data["rings"] = rings_to_json(rings)
		data["time_range"] = [time_range.x, time_range.y]
	return data


static func from_json(data: Variant) -> Feature:
	var node := Feature.new()
	node.init_pnid()
	node.title = data["title"]
	node.enabled = data.get("enabled", true)
	node.is_group = data.get("is_group", data.get("type") == "Group")
	node.keyframes = Keyframe.list_from_json(data.get("keyframes", []))
	if node.is_group:
		node.collapsed = true
		for child_data in data.get("children", []):
			node.children.append(Feature.from_json(child_data))
	else:
		node.feature_type = FeatureType.normalize(str(data.get("feature_type", FeatureType.UNCLASSIFIED)))
		var c: Array = data.get("color", [0.82, 0.41, 0.12, 1.0])
		node.color = Color(c[0], c[1], c[2], c[3])
		node.geometry_kind = KIND_VALUES.get(data.get("geometry_kind", "polygon"), GeometryKind.POLYGON)
		node.rings = rings_from_json(data.get("rings", []))
		node.rebuild_triangles()
		var tr: Array = data.get("time_range", [0, 2000])
		node.time_range = Vector2i(tr[0], tr[1])
	return node


static func rings_to_json(value: Array[PackedVector2Array]) -> Array:
	var result: Array = []
	for ring in value:
		var vertices: Array = []
		for v in ring:
			vertices.append([v.x, v.y])
		result.append(vertices)
	return result


static func rings_from_json(data: Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for ring_data in data:
		var ring := PackedVector2Array()
		for v in ring_data:
			ring.append(Vector2(v[0], v[1]))
		result.append(ring)
	return result


### Triangulation


# Ear clipping in the (latitude, longitude) plane. Returns a flat list of
# triangles, 3 vertices each, wound the same way as the polygon that went in.
# Self-intersecting polygons are not supported.
static func ear_clip(polygon: PackedVector2Array) -> PackedVector2Array:
	var n := polygon.size()
	var result := PackedVector2Array()
	if n < 3:
		return result

	# Build mutable index list
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

		# Check if this vertex forms a convex ear (matches polygon winding)
		var cross_val := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
		if cross_val * winding_sign <= 0.0:
			i = (i + 1) % sz
			continue

		# Check no other polygon vertex falls inside this triangle
		var is_ear := true
		for k in range(sz):
			if k == prev or k == i or k == next:
				continue
			if point_in_triangle(polygon[idx[k]], a, b, c):
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

	# Output the final remaining triangle
	if idx.size() == 3:
		result.append(polygon[idx[0]])
		result.append(polygon[idx[1]])
		result.append(polygon[idx[2]])

	return result


static func point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)


# Turn the triangle starting at index start so that it faces away from the
# centre of the sphere, which is what the shader and the hit test require.
static func ensure_front_winding(verts: PackedVector2Array, start: int) -> void:
	var a := _latlon_to_xyz_s(verts[start])
	var b := _latlon_to_xyz_s(verts[start + 1])
	var c := _latlon_to_xyz_s(verts[start + 2])

	if (b - a).cross(c - a).dot((a + b + c) / 3.0) < 0.0:
		var tmp := verts[start + 1]
		verts[start + 1] = verts[start + 2]
		verts[start + 2] = tmp


### Motion in time


# The rotation this node applies of its own at the given time, from its own
# keyframes. What the world sees is this composed with every ancestor's; see
# world_basis().
func rotation_at(time: float) -> Vector3:
	return Keyframe.interpolate(keyframes, time)


func basis_at(time: float) -> Basis:
	return build_rotation_basis(rotation_at(time))


# Whether this node is there at the given time. A group is there whenever its
# children are, so only a leaf feature is limited by a time range. Both ends
# count as inside, and the range is an age span, so the larger number is the
# older end.
func exists_at(time: float) -> bool:
	if is_group:
		return true
	return time >= float(time_range.x) and time <= float(time_range.y)


# The rotation that carries a node's own frame into world space at the given
# time: its own rotation with every ancestor's applied outside it, root first.
# A group's motion therefore reaches everything under it, which is how a terrane
# rides on the craton it sits on. The identity when the node is not in the tree.
static func world_basis(root: Feature, node: Feature, time: float) -> Basis:
	var chain: Array[Feature] = []
	if root == null or node == null or not _path_to(root, node, chain):
		return Basis()
	var m := Basis()
	for step in chain:
		m = m * step.basis_at(time)
	return m


# Fill chain with the nodes from this one down to the target, both included.
static func _path_to(node: Feature, target: Feature, chain: Array[Feature]) -> bool:
	chain.append(node)
	if is_same(node, target):
		return true
	for child in node.children:
		if _path_to(child, target, chain):
			return true
	chain.pop_back()
	return false


### Rotation helpers


# Build rotation Basis from angles (degrees): R = Ry(rot.x) * Rx(rot.y) * Rz(rot.z)
static func build_rotation_basis(rot: Vector3) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(rot.x)) \
		* Basis(Vector3.RIGHT, deg_to_rad(rot.y)) \
		* Basis(Vector3.BACK, deg_to_rad(rot.z))


# Extract the three angles in degrees from M = Ry(alpha) * Rx(beta) * Rz(gamma)
# Note: Godot Basis uses m[column][row], so standard M[row][col] = m[col][row]
static func decompose_rotation_degrees(m: Basis) -> Vector3:
	var sin_beta := clampf(-m[2][1], -1.0, 1.0)
	var beta := asin(sin_beta)
	var cos_beta := cos(beta)

	var alpha: float
	var gamma: float
	if cos_beta > 0.0001:
		alpha = atan2(m[2][0], m[2][2])
		gamma = atan2(m[0][1], m[1][1])
	else:
		# Gimbal lock (beta near +-90 degrees): set gamma to 0 and solve alpha
		gamma = 0.0
		alpha = atan2(-m[0][2], m[0][0])

	return Vector3(rad_to_deg(alpha), rad_to_deg(beta), rad_to_deg(gamma))


static func apply_rotation(verts: PackedVector2Array, rot: Vector3) -> PackedVector2Array:
	if rot.is_zero_approx():
		return verts
	return apply_basis(verts, build_rotation_basis(rot))


static func unapply_rotation(verts: PackedVector2Array, rot: Vector3) -> PackedVector2Array:
	if rot.is_zero_approx():
		return verts
	return apply_basis(verts, build_rotation_basis(rot).transposed())


# Carry latitude and longitude vertices through a rotation already built. The
# rotation of a node is composed from its own and its ancestors', so most
# callers have the Basis rather than the three angles that made it.
static func apply_basis(verts: PackedVector2Array, m: Basis) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(verts.size())
	for i in range(verts.size()):
		result[i] = _xyz_to_latlon_s(m * _latlon_to_xyz_s(verts[i]))
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
	var m_new := Basis(axis, angle) * build_rotation_basis(base_rot)
	return decompose_rotation_degrees(m_new)


static func _latlon_to_xyz_s(v: Vector2) -> Vector3:
	var lat_rad := deg_to_rad(v.x)
	var lon_rad := deg_to_rad(v.y)
	var cos_lat := cos(lat_rad)
	return Vector3(cos_lat * cos(lon_rad), sin(lat_rad), cos_lat * sin(lon_rad))


static func _xyz_to_latlon_s(p: Vector3) -> Vector2:
	return Vector2(rad_to_deg(asin(clampf(p.y, -1.0, 1.0))), rad_to_deg(atan2(p.z, p.x)))
