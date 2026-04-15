extends VBoxContainer
class_name Application


static var DEBUG: bool = true
static var VERSION: String = ProjectSettings.get_setting("application/config/version")
const ui_scale: float = 1.0

enum Tool { MOVE, DRAW }

@onready var features: Features = %Features
@onready var planet_view: PlanetView = %PlanetView
@onready var move_button: Button = %Move
@onready var axis_button: Button = %Axis
@onready var draw_button: Button = %Draw

var active_tool: Tool = Tool.MOVE
var last_triangles: Array = []
var hovered_feature: Feature = null

# Axis toggle (independent of the active tool). When enabled, the Move tool
# rotates the selected craton around this axis instead of moving it freely.
var axis_enabled: bool = false
var axis_point: Vector2 = Vector2(0.0, 0.0)
# On-sphere distance threshold (chord length) for grabbing the axis handle.
const AXIS_GRAB_RADIUS: float = 0.06


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var root := get_tree().root
	root.content_scale_factor = Application.ui_scale

	# Connect tool buttons
	move_button.pressed.connect(_on_move_pressed)
	axis_button.pressed.connect(_on_axis_pressed)
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

	# Connect rotate tool signals
	planet_view.rotate_started.connect(_on_rotate_started)
	planet_view.rotate_by.connect(_on_rotate_by)
	planet_view.rotate_ended.connect(_on_rotate_ended)


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


func _on_axis_pressed() -> void:
	axis_enabled = axis_button.button_pressed
	if axis_enabled and axis_point == Vector2.ZERO:
		# First activation: seed axis position at the selected craton's centroid if possible.
		var selected := features.feature_tree.get_selected_node()
		if selected != null and not selected.is_group and selected.has_craton():
			axis_point = _compute_craton_centroid_latlon(selected)
	planet_view.planet.set_axis(axis_point.x, axis_point.y, axis_enabled)
	_update_move_enabled()


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


func _compute_craton_centroid_latlon(f: Feature) -> Vector2:
	var base := Feature._build_rotation_basis(f.rotation_angles)
	var c := Vector3.ZERO
	for v in f.all_outline_points():
		c += base * Feature._latlon_to_xyz_s(v)
	if c.length() < 1e-6:
		return Vector2.ZERO
	return Feature._xyz_to_latlon_s(c.normalized())


### Feature selection


func _on_feature_selected(node: Feature) -> void:
	# Clear any in-progress outline when switching features
	if not outline_vertices.is_empty():
		_outline_cancel()

	var is_leaf := node != null and not node.is_group
	draw_button.disabled = not is_leaf

	if is_leaf:
		# Auto-select Draw if the feature has no craton (no vertices)
		if not node.has_craton():
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
	var has_craton := selected != null and not selected.is_group and selected.has_craton()
	# Allow starting a "move" gesture whenever a craton is selected OR the axis is enabled
	# (so the axis handle is draggable even without a craton).
	planet_view.move_enabled = active_tool == Tool.MOVE and (has_craton or axis_enabled)


var move_anchor_world: Vector3
var move_base_rot: Vector3
var move_dragging_axis: bool = false


func _on_move_started(anchor_lat: float, anchor_lon: float) -> void:
	move_dragging_axis = false
	# Axis handle drag takes priority when the axis is visible and the click is near it.
	if axis_enabled:
		var click_vec := Feature._latlon_to_xyz_s(Vector2(anchor_lat, anchor_lon))
		var axis_vec := Feature._latlon_to_xyz_s(axis_point)
		var d_near := (click_vec - axis_vec).length()
		var d_far := (click_vec + axis_vec).length()
		if min(d_near, d_far) < AXIS_GRAB_RADIUS:
			move_dragging_axis = true
			return

	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return
	move_base_rot = selected.rotation_angles
	move_anchor_world = Feature._latlon_to_xyz_s(Vector2(anchor_lat, anchor_lon))


func _on_move_to(lat: float, lon: float) -> void:
	if move_dragging_axis:
		axis_point = Vector2(lat, lon)
		planet_view.planet.set_axis(axis_point.x, axis_point.y, true)
		return

	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return
	var target_world := Feature._latlon_to_xyz_s(Vector2(lat, lon))
	var new_rot: Variant
	if axis_enabled:
		var axis_world := Feature._latlon_to_xyz_s(axis_point)
		new_rot = Feature.compute_axis_rotation(axis_world, move_anchor_world, target_world, move_base_rot)
	else:
		new_rot = Feature.compute_move_rotation(move_anchor_world, target_world, move_base_rot)
	if new_rot != null:
		selected.rotation_angles = new_rot
		refresh_cratons()


func _on_move_ended() -> void:
	if move_dragging_axis:
		move_dragging_axis = false
		return
	features.save_version()
	features.reload()
	refresh_cratons()


func _on_move_cancelled() -> void:
	if move_dragging_axis:
		move_dragging_axis = false
		return
	var selected := features.feature_tree.get_selected_node()
	if selected != null and not selected.is_group:
		selected.rotation_angles = move_base_rot
	refresh_cratons()


### Rotate craton with right mouse button


const ROTATE_SENSITIVITY: float = 0.3

var rotate_base_rot: Vector3


func _on_rotate_started() -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return
	rotate_base_rot = selected.rotation_angles


func _on_rotate_by(delta: Vector2) -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group or not selected.has_craton():
		return
	var spin_deg := (delta.x + delta.y) * ROTATE_SENSITIVITY
	var base := Feature._build_rotation_basis(selected.rotation_angles)
	# Compute craton center as centroid of world-space outline vertices
	var centroid := Vector3.ZERO
	for v in selected.all_outline_points():
		centroid += base * Feature._latlon_to_xyz_s(v)
	var center_axis := centroid.normalized()
	var m_new := Basis(center_axis, deg_to_rad(spin_deg)) * base
	selected.rotation_angles = Feature._decompose_rotation_degrees(m_new)
	refresh_cratons()


func _on_rotate_ended() -> void:
	features.save_version()
	features.reload()
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

	# The user draws in world space. Convert the loop to local (unrotated)
	# space before storing — triangulation happens inside Feature.
	var loop_world: Array[Vector2] = outline_vertices.duplicate()
	var loop_local: Array[Vector2] = Feature.unapply_rotation(loop_world, selected.rotation_angles)

	var packed := PackedVector2Array()
	for v in loop_local:
		packed.append(v)
	selected.add_outline(packed)

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
	if selected != null and not selected.is_group and selected.has_craton():
		var verts := Feature.apply_rotation(selected.triangles, selected.rotation_angles)
		planet_view.planet.set_outline(verts, false, true)
	else:
		var empty: Array[Vector2] = []
		planet_view.planet.set_outline(empty)


func _on_program_changed() -> void:
	refresh_cratons()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
