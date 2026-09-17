class_name Feature


# What the vertices of a feature describe. A feature holds one kind of
# geometry; drawing a second shape on it adds another part of the same kind.
#
# A topology is the odd one out: it keeps no vertices of its own but a list of
# sections borrowed from other features, and its rings are resolved from those.
# It is drawn and hit tested as a polyline, or as a polygon when it is closed;
# see drawn_as() and Logic/topology.gd.
enum GeometryKind { POLYGON, POLYLINE, MULTIPOINT, TOPOLOGY }

# The kind as it appears in a file, and back.
const KIND_NAMES := {
	GeometryKind.POLYGON: "polygon",
	GeometryKind.POLYLINE: "polyline",
	GeometryKind.MULTIPOINT: "multipoint",
	GeometryKind.TOPOLOGY: "topology",
}
const KIND_VALUES := {
	"polygon": GeometryKind.POLYGON,
	"polyline": GeometryKind.POLYLINE,
	"multipoint": GeometryKind.MULTIPOINT,
	"topology": GeometryKind.TOPOLOGY,
}

# The kinds the Draw tool can produce. A topology is built by clicking whole
# features rather than by placing vertices, so it is not among them.
const DRAWN_KINDS := [GeometryKind.POLYGON, GeometryKind.POLYLINE, GeometryKind.MULTIPOINT]

# How many vertices one part of each kind needs before it is a shape. The Draw
# tool commits nothing below it and an edit that would take a part under it
# removes the part instead. A topology is measured in sections rather than in
# vertices, but a resolved part of one is a piece of a line like any other.
const MINIMUM_VERTICES := {
	GeometryKind.POLYGON: 3,
	GeometryKind.POLYLINE: 2,
	GeometryKind.MULTIPOINT: 1,
	GeometryKind.TOPOLOGY: 2,
}

# The longest title a feature keeps; anything longer is cut down to it.
const MAX_TITLE_LENGTH := 100

# Node ID, unique only during the runtime of the application (not persisted)
var pnid: int = -1

# What this node is called in the file, kept across a save and a load. A line
# topology names the features its sections run along by this, so an id that only
# lasted one run would not do; see Docs/Editing.md#topologies. A duplicate,
# a paste and a node arriving from a file without one all get a fresh id.
var uuid: String = ""

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
# How the features under the group are colored; null on a leaf.
var style: GroupStyle = null

# Feature-only fields
# What the feature is, an id in FeatureType.CATALOG. It is picked in the
# Properties panel and says what the tools draw into the feature. A feature
# holding a shape has to have a type that holds that kind: one that does not
# reads as the kind's own.
var feature_type: String = FeatureType.NONE:
	get:
		return FeatureType.resolve(feature_type, kind_name() if has_geometry() else "")
var color: Color = FeatureType.color(FeatureType.POLYGON)

# The glyph the tree row shows, an id in FeatureIcon.CATALOG, empty for none.
# It is picked in the Properties panel and nothing but the row reads it.
var icon: String = FeatureIcon.NONE

# Geographic data. Each ring is a run of (latitude, longitude) vertices in
# degrees, in the frame of the feature itself, before the rotation its
# keyframes give it at the current time is applied. What a ring means follows
# geometry_kind: a closed boundary for a polygon, an open line for a polyline, a
# bag of separate points for a multipoint. A feature may hold several rings; for
# a polygon those are separate outlines rather than holes.
var geometry_kind: GeometryKind = GeometryKind.POLYGON
var rings: Array[PackedVector2Array] = []

# What a topology is made of: runs of vertices borrowed from other
# features, in order. Only a topology has any, and a topology has nothing in
# rings but what Topology.rebuild() resolved these into at the current time.
var sections: Array[TopologySection] = []
# Whether a topology joins its sections into one ring and is filled like a
# polygon. See Topology.rebuild().
var closed := false
# Whether a topology is the line midway between its two sections, vertex by
# vertex, the way a mid-ocean ridge lies between the plates it opens. See
# Logic/ridge.gd.
var midway := false

# What a crust is built from: the half of a split plate it lies beside, the
# ridge it opened from and how many vertices the cut had. A crust is a topology
# without sections; Crust.rebuild() gives it its rings. The lines one holds the
# isochrons and flowlines instead of the bands between them.
var crust_half := ""
var crust_ridge := ""
var crust_edge := 0
var crust_lines := false

# What a Circle is built from: its center, the point its axis comes out of, as
# (latitude, longitude) in degrees in the feature's own frame, its radius in
# degrees, how many segments it is cut into, and whether the circle around the
# antipode is drawn as well. No other type reads them; rebuild_circle() makes
# the rings. The defaults are the auroral ovals, which lie about 23 degrees
# from the geomagnetic poles.
const DEFAULT_AXIS := Vector2(90.0, 0.0)
const DEFAULT_RADIUS := 23.0
var axis: Vector2 = DEFAULT_AXIS
var radius: float = DEFAULT_RADIUS
var circle_segments: int = Circle.DEFAULT_SEGMENTS
var polar := false

# What a Hotspot feature is built from: where the hotspot is, as (latitude,
# longitude) in degrees in the world frame, NO_HOTSPOT until the Draw tool
# places it, and the uuid of the feature it burns through, empty for none. The
# track is sampled at the timeline's Skip. No other type reads them;
# Hotspot.rebuild() makes the rings.
const NO_HOTSPOT := Vector2(INF, INF)
var hotspot := NO_HOTSPOT
var plate_uuid := ""

# Triangles covering the polygon rings, 3 vertices each, wound so that they face
# outwards. Derived from rings by rebuild_triangles(), never read from a file.
var triangles := PackedVector2Array()

# How the feature turns over time, sorted by time. An empty list means it does
# not move at all. Only a leaf has any: a group is organization and carries no
# motion, since 0.8.0; what follows what is a coupling between two features
# (GP-0046), not the tree.
var keyframes: Array[Keyframe] = []

# The spans of the timeline over which the feature follows another, youngest
# first. Inside one its keyframes are relative to that parent; see
# Logic/coupling.gd. Only a leaf has any, and the tree has nothing to do with it.
var couplings: Array[Coupling] = []

# The ages between which a feature exists, in millions of years before present.
# A feature outside it at the current time is neither drawn nor hit tested. Only
# a leaf feature has one; a group is there whenever its children are. The order
# is (younger, older), which is what the file keeps; the Properties panel reads
# the older end as From and the younger one as To.
const DEFAULT_TIME_RANGE := Vector2i(0, 2000)
var time_range: Vector2i = DEFAULT_TIME_RANGE

# Numbering
static var next_pnid: int = 1


func _init():
	pass


static func create_group(title_: String = "Group") -> Feature:
	var group := Feature.new()
	group.init_pnid()
	group.init_uuid()
	group.title = title_
	group.is_group = true
	group.style = GroupStyle.new()
	return group


static func create_feature(title_: String = "Feature",
		color_: Color = FeatureType.color(FeatureType.POLYGON),
		time_range_: Vector2i = DEFAULT_TIME_RANGE) -> Feature:
	var feature := Feature.new()
	feature.init_pnid()
	feature.init_uuid()
	feature.title = title_
	feature.color = color_
	feature.is_group = false
	feature.time_range = time_range_
	# A new feature is a Polygon, which is what most of them turn out to be and
	# what the Draw tool then produces. The panel changes it before the first
	# shape is drawn.
	feature.feature_type = FeatureType.POLYGON
	return feature


# A title as a feature keeps it: trimmed, and cut down to MAX_TITLE_LENGTH.
static func clamp_title(value: String) -> String:
	var title_ := value.strip_edges()
	return title_ if title_.length() <= MAX_TITLE_LENGTH else title_.left(MAX_TITLE_LENGTH) + "..."


func init_pnid():
	pnid = next_pnid
	next_pnid += 1


func init_uuid() -> void:
	uuid = Helpers.generate_uuid_v4()


### Geometry


# The geometry kind under the name the file and the type catalog use.
func kind_name() -> String:
	return str(KIND_NAMES[geometry_kind])


# The kind this feature is drawn, hit tested and measured as. A topology
# resolves into one run of vertices per section, which is a polyline in every
# way that matters below this point, or into one ring when it is closed, which
# is a polygon; so nothing downstream has to know the kind exists at all.
func drawn_as() -> GeometryKind:
	if geometry_kind != GeometryKind.TOPOLOGY:
		return geometry_kind
	return GeometryKind.POLYGON if closed else GeometryKind.POLYLINE


func minimum_vertices() -> int:
	return int(MINIMUM_VERTICES[geometry_kind])


func has_geometry() -> bool:
	# A topology is there as soon as it names a section, whether or not the
	# feature that section runs along can still be found.
	if geometry_kind == GeometryKind.TOPOLOGY:
		return not sections.is_empty() or is_crust()
	for ring in rings:
		if not ring.is_empty():
			return true
	return false


# Whether the feature holds vertices someone can take hold of. A topology holds
# geometry but borrows every vertex of it from the features its sections run
# along, so there is nothing there to drag, insert, delete or split.
# A hotspot's rings are rebuilt from its parameters, so it has none either.
func has_own_vertices() -> bool:
	return has_geometry() and geometry_kind != GeometryKind.TOPOLOGY and not is_hotspot()


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
	if drawn_as() != GeometryKind.POLYGON:
		return

	for ring in rings:
		var corners := ear_clip(ring)
		for i in range(0, corners.size() - 2, 3):
			var a := corners[i]
			var b := corners[i + 1]
			var c := corners[i + 2]
			if not faces_outwards(a, b, c):
				var swapped := b
				b = c
				c = swapped
			triangles.append(a)
			triangles.append(b)
			triangles.append(c)


# Whether a triangle is visible from outside the planet: its normal points away
# from the centre of the sphere. Both Planet.hit_test and the geometry shader
# require it, and rebuild_triangles() swaps two vertices of any triangle ear
# clipping produced the other way round.
static func faces_outwards(a: Vector2, b: Vector2, c: Vector2) -> bool:
	var pa := _latlon_to_xyz_s(a)
	var pb := _latlon_to_xyz_s(b)
	var pc := _latlon_to_xyz_s(c)
	return (pb - pa).cross(pc - pa).dot((pa + pb + pc) / 3.0) >= 0.0


# Add one drawn shape to the feature, adopting the kind when it is the first.
func add_ring(ring: PackedVector2Array, kind: GeometryKind) -> void:
	if not has_geometry():
		geometry_kind = kind
		rings.clear()
	rings.append(ring)
	rebuild_triangles()


func is_circle() -> bool:
	return not is_group and feature_type == FeatureType.CIRCLE


# Replace the rings with the circle the parameters describe, and with the one
# around the antipode too when the circle is polar. A circle is an outline; one
# filled in a file written before outlines were the rule stays filled.
func rebuild_circle() -> void:
	var filled := has_geometry() and geometry_kind == GeometryKind.POLYGON
	geometry_kind = GeometryKind.POLYGON if filled else GeometryKind.POLYLINE
	var centers := [axis]
	if polar:
		centers.append(Vector2(-axis.x, wrapf(axis.y + 180.0, -180.0, 180.0)))
	rings.assign(centers.map(func(center: Vector2) -> PackedVector2Array:
		return Circle.vertices(center, radius, circle_segments, filled)))
	rebuild_triangles()


func is_hotspot() -> bool:
	return not is_group and feature_type == FeatureType.HOTSPOT


func is_crust() -> bool:
	return not is_group and not crust_half.is_empty()


# How wide the feature's lines are drawn, against the shader's
# geometry_line_width. A hotspot track is thin so the dots at its samples stand
# out, and a circle is thinner than a line someone drew. A per feature setting
# would go here.
const HOTSPOT_LINE_SCALE := 0.35
const CIRCLE_LINE_SCALE := 0.5
const CRUST_LINES_LINE_SCALE := 0.5


func line_scale() -> float:
	if is_hotspot():
		return HOTSPOT_LINE_SCALE
	if is_circle():
		return CIRCLE_LINE_SCALE
	if is_crust() and crust_lines:
		return CRUST_LINES_LINE_SCALE
	return 1.0


### Clone (preserves pnid) and Duplicate (new pnid)


func clone() -> Feature:
	var node := Feature.new()
	node.pnid = pnid
	node.uuid = uuid
	node.title = title
	node.enabled = enabled
	node.is_group = is_group
	node.collapsed = collapsed
	node.is_root = is_root
	node.style = style.clone() if style != null else null
	node.feature_type = feature_type
	node.color = color
	node.icon = icon
	node.geometry_kind = geometry_kind
	node.sections = TopologySection.clone_list(sections)
	node.closed = closed
	node.midway = midway
	node.crust_half = crust_half
	node.crust_ridge = crust_ridge
	node.crust_edge = crust_edge
	node.crust_lines = crust_lines
	for ring in rings:
		node.rings.append(ring.duplicate())
	# Copied rather than recomputed: every undo step clones the whole tree.
	node.triangles = triangles.duplicate()
	node.keyframes = Keyframe.clone_list(keyframes)
	node.couplings = Coupling.clone_list(couplings)
	node.time_range = time_range
	node.axis = axis
	node.radius = radius
	node.circle_segments = circle_segments
	node.polar = polar
	node.hotspot = hotspot
	node.plate_uuid = plate_uuid
	for child in children:
		node.children.append(child.clone())
	return node


func duplicate() -> Feature:
	var node := clone()
	node.init_pnid()
	node.init_uuid()
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


# The node a uuid names, or null when the tree no longer holds it. This is how a
# topology reaches the features its sections run along, so a section left
# dangling by a deletion is a null here rather than a missing key.
func get_node_by_uuid(uuid_: String) -> Feature:
	if uuid_.is_empty():
		return null
	var stack: Array[Feature] = [self]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if node.uuid == uuid_:
			return node
		stack.append_array(node.children)
	return null


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
		"uuid": uuid,
		"title": title,
		"enabled": enabled,
		"is_group": is_group,
	}
	if is_group:
		data["type"] = "Group"
		data["style"] = (style if style != null else GroupStyle.new()).to_json()
		var children_data: Array[Variant] = []
		for child in children:
			children_data.append(child.to_json())
		data["children"] = children_data
	else:
		data["type"] = "Feature"
		data["keyframes"] = Keyframe.list_to_json(keyframes)
		data["couplings"] = Coupling.list_to_json(couplings)
		data["feature_type"] = feature_type
		data["color"] = [color.r, color.g, color.b, color.a]
		# Written only when there is one, so a file of features nobody gave an
		# icon reads the same as it did before there were any.
		if not icon.is_empty():
			data["icon"] = icon
		data["geometry_kind"] = KIND_NAMES[geometry_kind]
		# A topology's rings are resolved from its sections whenever the tree or
		# the time moves, so writing them would be writing down a derived value.
		if geometry_kind == GeometryKind.TOPOLOGY:
			data["sections"] = TopologySection.list_to_json(sections)
			# Written only when set, so an open topology reads as it did before
			# 0.20.0.
			if closed:
				data["closed"] = true
			# Both 0.23.0, and written only when set, like closed.
			if midway:
				data["midway"] = true
			if is_crust():
				data["crust"] = {"half": crust_half, "ridge": crust_ridge, "edge": crust_edge}
				if crust_lines:
					data["crust"]["lines"] = true
		else:
			data["rings"] = rings_to_json(rings)
		data["time_range"] = [time_range.x, time_range.y]
		# Only a circle writes its parameters, and only a drawn one, so a missing
		# key means some other type or a circle not drawn yet. The rings above are
		# written anyway, for a reader that knows nothing about them.
		if is_circle() and has_geometry():
			data["axis"] = [axis.x, axis.y]
			data["radius"] = radius
			data["circle_segments"] = circle_segments
			if polar:
				data["polar"] = true
		# A hotspot not placed yet writes no place, the way a circle not drawn
		# yet writes no center.
		if is_hotspot():
			if Hotspot.placed(self):
				data["hotspot"] = [hotspot.x, hotspot.y]
			data["plate"] = plate_uuid
	return data


static func from_json(data: Variant) -> Feature:
	var node := Feature.new()
	node.init_pnid()
	# A file written before 0.5.0 carries no id, and neither does one written by
	# hand; a fresh one then stands in, which is safe because nothing in such a
	# file can be naming it.
	node.uuid = str(data.get("uuid", ""))
	if node.uuid.is_empty():
		node.init_uuid()
	node.title = data["title"]
	node.enabled = data.get("enabled", true)
	node.is_group = data.get("is_group", data.get("type") == "Group")
	# A group carries no motion. A file written before 0.8.0 had keyframes on
	# groups; Document.migrate() folds those into the leaves before this runs.
	if not node.is_group:
		node.keyframes = Keyframe.list_from_json(data.get("keyframes", []))
		node.couplings = Coupling.list_from_json(data.get("couplings", []))
	if node.is_group:
		node.collapsed = true
		node.style = GroupStyle.from_json(data.get("style"))
		for child_data in data.get("children", []):
			node.children.append(Feature.from_json(child_data))
	else:
		if str(data.get("feature_type", "")) == FeatureType.CIRCLE and not data.has("axis"):
			data = data.duplicate()
			fit_circle_json(data)
		node.feature_type = str(data.get("feature_type", FeatureType.NONE))
		var fallback: Color = FeatureType.CATALOG[FeatureType.POLYGON]["color"]
		var c: Array = data.get("color", [fallback.r, fallback.g, fallback.b, fallback.a])
		node.color = Color(c[0], c[1], c[2], c[3])
		node.icon = str(data.get("icon", FeatureIcon.NONE))
		node.geometry_kind = KIND_VALUES.get(data.get("geometry_kind", "polygon"), GeometryKind.POLYGON)
		node.sections = TopologySection.list_from_json(data.get("sections", []))
		node.closed = bool(data.get("closed", false))
		node.midway = bool(data.get("midway", false))
		var crust: Variant = data.get("crust")
		if crust is Dictionary:
			node.crust_half = str(crust.get("half", ""))
			node.crust_ridge = str(crust.get("ridge", ""))
			node.crust_edge = int(crust.get("edge", 0))
			node.crust_lines = bool(crust.get("lines", false))
		node.rings = rings_from_json(data.get("rings", []))
		node.rebuild_triangles()
		var tr: Array = data.get("time_range", [0, 2000])
		node.time_range = Vector2i(tr[0], tr[1])
		var a: Array = data.get("axis", [DEFAULT_AXIS.x, DEFAULT_AXIS.y])
		node.axis = Vector2(a[0], a[1])
		node.radius = float(data.get("radius", DEFAULT_RADIUS))
		node.circle_segments = int(data.get("circle_segments", Circle.DEFAULT_SEGMENTS))
		node.polar = bool(data.get("polar", false))
		if data.has("hotspot"):
			var h: Array = data["hotspot"]
			node.hotspot = Vector2(h[0], h[1])
		node.plate_uuid = str(data.get("plate", ""))
		# The parameters win over the rings the file holds. A hotspot's track
		# needs the whole tree, so Hotspot.rebuild_all() redoes it before the
		# geometry is collected.
		if node.is_circle() and data.has("axis"):
			node.rebuild_circle()
	return node


# Give a circle leaf of a file the parameters it lacks, in place. A circle with
# one ring and no center, which is what a file written before 0.21.0 or by a
# script holds, takes the circle Circle.fit() finds in that ring. One holding
# several rings was drawn more than once and is no single circle, so it keeps
# its rings under the type its kind gives. See Docs/Persistence.md.
static func fit_circle_json(data: Dictionary) -> void:
	var rings: Array = data.get("rings", [])
	if data.has("axis") or rings.is_empty():
		return
	if rings.size() > 1:
		data["feature_type"] = FeatureType.OF_KIND.get(str(data.get("geometry_kind", "polygon")),
			FeatureType.NONE)
		return
	var circle := Circle.fit(rings_from_json(rings)[0])
	if circle.is_empty():
		return
	data["axis"] = [circle[0].x, circle[0].y]
	data["radius"] = circle[1]
	data["circle_segments"] = circle[2]


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
#
# A ring whose longitude winds a full turn goes round a pole, and has no shape
# in that plane to clip: it becomes a fan of triangles from the pole on the
# side most of the ring lies on, which the pole is added to as a vertex.
static func ear_clip(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	var n := polygon.size()
	if n >= 3 and absf(_longitude_winding(polygon)) > 180.0:
		var latitude_sum := 0.0
		for v in polygon:
			latitude_sum += v.x
		var pole := Vector2(-90.0 if latitude_sum < 0.0 else 90.0, 0.0)
		for i in range(n):
			result.append(pole)
			result.append(polygon[i])
			result.append(polygon[(i + 1) % n])
		return result

	for index in ear_clip_indices(polygon):
		result.append(polygon[index])
	return result


# The sum of the longitude steps round a ring, each taken the short way: plus
# or minus 360 for a ring round a pole, zero for any other.
static func _longitude_winding(ring: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(ring.size()):
		total += wrapf(ring[(i + 1) % ring.size()].y - ring[i].y, -180.0, 180.0)
	return total


# The same triangulation as vertex indices into the ring, three per triangle.
# The longitudes are unwrapped first, so that each step from one vertex to the
# next is under 180 degrees and a ring across the date line keeps its shape.
static func ear_clip_indices(ring: PackedVector2Array) -> PackedInt32Array:
	var n := ring.size()
	var result := PackedInt32Array()
	if n < 3:
		return result

	var polygon := ring.duplicate()
	for i in range(1, n):
		var step := wrapf(ring[i].y - ring[i - 1].y, -180.0, 180.0)
		polygon[i] = Vector2(ring[i].x, polygon[i - 1].y + step)

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
			result.append(idx[prev])
			result.append(idx[i])
			result.append(idx[next])
			idx.remove_at(i)
			if i >= idx.size():
				i = 0
		else:
			i = (i + 1) % idx.size()

	# Output the final remaining triangle
	if idx.size() == 3:
		result.append(idx[0])
		result.append(idx[1])
		result.append(idx[2])

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


### Motion in time


# The rotation this node has at the given time, from its keyframes.
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
# time. That is the node's own rotation, composed with the parent's while a
# coupling holds (Logic/coupling.gd); the groups above it are organization and
# carry no motion. The identity when the node is not in the tree.
static func world_basis(root: Feature, node: Feature, time: float) -> Basis:
	if root == null or node == null or not root.contains_node_at_any_depth(node):
		return Basis()
	if node.couplings.is_empty():
		return node.basis_at(time)
	return Coupling.world_basis(node, time, Coupling.index(root))


# The rotation a keyframe at this time has to hold to keep the node where it
# stands: its own interpolation when it follows nothing, and otherwise its
# world rotation put into the frame in effect at the time.
static func keyframe_rotation(root: Feature, node: Feature, time: float) -> Vector3:
	if node.couplings.is_empty():
		return node.rotation_at(time)
	return Coupling.rotation_for(node, time, world_basis(root, node, time), Coupling.index(root))


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


# Carry latitude and longitude vertices through a rotation already built, which
# is what most callers have rather than the three angles that made it.
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


### Turning about an axis
#
# What the Rotate and Pole tools do: spin a feature about an axis through the
# sphere rather than carry a grabbed point along a great circle. See
# Docs/Moving.md#rotating.


# How far off the axis a point has to be before the direction to it means
# anything: the length of what is left of it once the axis component is taken
# away, 0.05 being a little under three degrees. Nearer than that, to the axis
# or to its antipode, and a turn about the axis is undefined, the way an
# antipodal drag is in compute_move_rotation().
const MIN_AXIS_OFFSET := 0.05


# The axis a feature turns about when it is spun in place: the direction of the
# sum of its world vertices at the given time. Vector3.ZERO when there are no
# vertices, or when they cancel each other out.
static func centroid_axis(root: Feature, node: Feature, time: float) -> Vector3:
	var m := world_basis(root, node, time)
	var sum := Vector3.ZERO
	for ring in node.rings:
		for vertex in ring:
			sum += m * _latlon_to_xyz_s(vertex)
	return Vector3.ZERO if sum.is_zero_approx() else sum.normalized()


# The angle from one world point to another measured about an axis, in radians,
# counterclockwise seen from the far end of the axis. Both points are projected
# onto the plane normal to the axis first; null when either projection is too
# short for its direction to mean anything.
static func angle_about_axis(axis: Vector3, from_world: Vector3, to_world: Vector3) -> Variant:
	var from_flat := from_world - axis * axis.dot(from_world)
	var to_flat := to_world - axis * axis.dot(to_world)
	if from_flat.length() < MIN_AXIS_OFFSET or to_flat.length() < MIN_AXIS_OFFSET:
		return null
	return atan2(axis.dot(from_flat.cross(to_flat)), from_flat.dot(to_flat))


# The angles that turn a feature by an angle in radians about a world axis,
# composed onto the rotation it already has, the way compute_move_rotation()
# composes a great circle move onto it.
static func compute_spin_rotation(axis: Vector3, angle: float, base_rot: Vector3) -> Vector3:
	return decompose_rotation_degrees(Basis(axis, angle) * build_rotation_basis(base_rot))


static func _latlon_to_xyz_s(v: Vector2) -> Vector3:
	var lat_rad := deg_to_rad(v.x)
	var lon_rad := deg_to_rad(v.y)
	var cos_lat := cos(lat_rad)
	return Vector3(cos_lat * cos(lon_rad), sin(lat_rad), cos_lat * sin(lon_rad))


static func _xyz_to_latlon_s(p: Vector3) -> Vector2:
	return Vector2(rad_to_deg(asin(clampf(p.y, -1.0, 1.0))), rad_to_deg(atan2(p.z, p.x)))
