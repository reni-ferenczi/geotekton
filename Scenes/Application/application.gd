extends VBoxContainer
class_name Application


static var DEBUG: bool = true
static var VERSION: String = ProjectSettings.get_setting("application/config/version")
const ui_scale: float = 1.0

enum Tool { MOVE, DRAW }

@onready var features: Features = %Features
@onready var planet_view: PlanetView = %PlanetView
@onready var move_button: Button = %Move
@onready var draw_button: Button = %Draw

var active_tool: Tool = Tool.MOVE
var last_triangles: Array = []
var hovered_feature: Feature = null


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var root := get_tree().root
	root.content_scale_factor = Application.ui_scale

	# Connect tool buttons
	move_button.pressed.connect(_on_move_pressed)
	draw_button.pressed.connect(_on_draw_pressed)

	# Connect feature selection from the features panel
	features.feature_tree.feature_selected.connect(_on_feature_selected)

	# Connect planet click events for drawing
	planet_view.planet.input_event_globe.connect(_on_planet_input_for_drawing)
	planet_view.planet.input_event_map.connect(_on_planet_input_for_drawing)

	# Connect program changes to refresh cratons
	features.feature_tree.program_changed.connect(_on_program_changed)

	# Connect File menu
	var file_menu: MenuButton = %MenuButton
	file_menu.get_popup().id_pressed.connect(_on_file_menu_id_pressed)

	# Connect move tool signals
	planet_view.move_started.connect(_on_move_started)
	planet_view.move_to.connect(_on_move_to)
	planet_view.move_ended.connect(_on_move_ended)
	planet_view.move_cancelled.connect(_on_move_cancelled)

	# Connect craton interaction signals
	planet_view.craton_clicked.connect(_on_craton_clicked)
	planet_view.craton_hovered.connect(_on_craton_hovered)


### File menu


func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		0: features._on_load_pressed()   # Open...
		1: features._on_save_pressed()   # Save As..
		2: features._on_save_pressed()   # Save (same as Save As for now)


### Tool button group


func _on_move_pressed() -> void:
	set_active_tool(Tool.MOVE)


func _on_draw_pressed() -> void:
	set_active_tool(Tool.DRAW)


func set_active_tool(tool: Tool) -> void:
	if active_tool == Tool.DRAW and tool != Tool.DRAW:
		_outline_cancel()
	active_tool = tool
	move_button.button_pressed = (tool == Tool.MOVE)
	draw_button.button_pressed = (tool == Tool.DRAW)
	planet_view.drawing_mode = (tool == Tool.DRAW)
	_update_move_enabled()


### Feature selection


func _on_feature_selected(node: Feature) -> void:
	# Clear any in-progress outline when switching features
	if not outline_vertices.is_empty():
		_outline_cancel()

	var is_leaf := node != null and not node.is_group
	draw_button.disabled = not is_leaf

	if is_leaf:
		# Auto-select Draw if the feature has no craton (no vertices)
		if node.vertices.is_empty():
			set_active_tool(Tool.DRAW)
	else:
		# Can't draw on groups or nothing — force Move
		if active_tool == Tool.DRAW:
			set_active_tool(Tool.MOVE)

	_update_move_enabled()
	refresh_cratons()


### Move tool


func _update_move_enabled() -> void:
	var selected := features.feature_tree.get_selected_node()
	var can_move := active_tool == Tool.MOVE and selected != null and not selected.is_group and not selected.vertices.is_empty()
	planet_view.move_enabled = can_move


var move_anchor_world: Vector3
var move_base_rot: Vector3


func _on_move_started(anchor_lat: float, anchor_lon: float) -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return
	move_base_rot = selected.rotation_angles
	move_anchor_world = Feature._latlon_to_xyz_s(Vector2(anchor_lat, anchor_lon))


func _on_move_to(lat: float, lon: float) -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return
	var target_world := Feature._latlon_to_xyz_s(Vector2(lat, lon))
	var new_rot: Variant = Feature.compute_move_rotation(move_anchor_world, target_world, move_base_rot)
	if new_rot != null:
		selected.rotation_angles = new_rot
		refresh_cratons()


func _on_move_ended() -> void:
	features.save_version()
	features.reload()
	refresh_cratons()


func _on_move_cancelled() -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected != null and not selected.is_group:
		selected.rotation_angles = move_base_rot
	refresh_cratons()


### Drawing — Polygon outline mode


var outline_vertices: Array[Vector2] = []


func _on_planet_input_for_drawing(lat: float, lon: float, event: InputEvent) -> void:
	if active_tool != Tool.DRAW:
		return
	if event is not InputEventMouseButton or not event.is_pressed():
		return

	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		outline_vertices.append(Vector2(lat, lon))
		_refresh_outline()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if not outline_vertices.is_empty():
			outline_vertices.pop_back()
			_refresh_outline()


func _unhandled_key_input(event: InputEvent) -> void:
	if active_tool != Tool.DRAW:
		return
	if event is not InputEventKey or not event.is_pressed():
		return

	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_outline_commit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		_outline_cancel()
		get_viewport().set_input_as_handled()


func _outline_commit() -> void:
	if outline_vertices.size() < 3:
		return
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return

	var triangles := _ear_clip(outline_vertices)

	# Ensure front-facing winding on world-space triangles before storing
	for i in range(0, triangles.size() - 2, 3):
		_ensure_front_winding(triangles, i)

	# Convert from world space to local (unrotated) space
	if not selected.rotation_angles.is_zero_approx():
		triangles = Feature.unapply_rotation(triangles, selected.rotation_angles)

	selected.vertices.append_array(triangles)

	outline_vertices.clear()
	_refresh_outline()
	features.save_version()
	features.reload()
	refresh_cratons()
	set_active_tool(Tool.MOVE)


func _outline_cancel() -> void:
	outline_vertices.clear()
	_refresh_selection_outline()


func _refresh_outline() -> void:
	planet_view.planet.set_outline(outline_vertices, outline_vertices.size() >= 3)


### Ear-clipping triangulation


static func _ear_clip(polygon: Array[Vector2]) -> Array[Vector2]:
	var n := polygon.size()
	if n < 3:
		return []

	var result: Array[Vector2] = []

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

	# Output the final remaining triangle
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


### Winding and coordinate helpers


func _ensure_front_winding(verts: Array[Vector2], start: int) -> void:
	var a := _latlon_to_xyz(verts[start])
	var b := _latlon_to_xyz(verts[start + 1])
	var c := _latlon_to_xyz(verts[start + 2])

	var normal := (b - a).cross(c - a)
	var center := (a + b + c) / 3.0

	if normal.dot(center) < 0:
		var tmp := verts[start + 1]
		verts[start + 1] = verts[start + 2]
		verts[start + 2] = tmp


func _latlon_to_xyz(v: Vector2) -> Vector3:
	var lat_rad := deg_to_rad(v.x)
	var lon_rad := deg_to_rad(v.y)
	var cos_lat := cos(lat_rad)
	return Vector3(
		cos_lat * cos(lon_rad),
		sin(lat_rad),
		cos_lat * sin(lon_rad)
	)


### Craton interaction


func _on_craton_clicked(lat: float, lon: float) -> void:
	var hit := Planet.hit_test_craton(lat, lon, last_triangles)
	var selected := features.feature_tree.get_selected_node()
	print("Craton click: hit=%s (pnid=%d), selected=%s (pnid=%d)" % [
		hit.title if hit else "null", hit.pnid if hit else -1,
		selected.title if selected else "null", selected.pnid if selected else -1])
	if hit != null and hit != selected:
		# Clicked a different craton — select it (deferred to avoid Tree UI update issues)
		features.feature_tree.select_node.call_deferred(hit)
	elif planet_view.move_enabled:
		# Clicked on the same craton or empty space — start moving
		planet_view.start_moving(lat, lon)


func _on_craton_hovered(lat: float, lon: float) -> void:
	var new_hovered: Feature = null
	if not is_nan(lat):
		new_hovered = Planet.hit_test_craton(lat, lon, last_triangles)
	if new_hovered != hovered_feature:
		hovered_feature = new_hovered
		planet_view.planet.set_cratons(last_triangles, hovered_feature)


### Craton rendering


func refresh_cratons() -> void:
	last_triangles = Planet.collect_triangles(features.root)
	planet_view.planet.set_cratons(last_triangles, hovered_feature)
	_refresh_selection_outline()


func _refresh_selection_outline() -> void:
	# Don't overwrite the drawing outline
	if not outline_vertices.is_empty():
		return
	var selected := features.feature_tree.get_selected_node()
	if selected != null and not selected.is_group and not selected.vertices.is_empty():
		var verts := Feature.apply_rotation(selected.vertices, selected.rotation_angles)
		planet_view.planet.set_outline(verts, false, true)
	else:
		var empty: Array[Vector2] = []
		planet_view.planet.set_outline(empty)


func _on_program_changed() -> void:
	refresh_cratons()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
