extends SubViewportContainer
class_name PlanetView

signal move_started(anchor_lat: float, anchor_lon: float)
signal move_to(lat: float, lon: float)
signal move_ended()
signal move_cancelled()
signal craton_clicked(lat: float, lon: float)
signal craton_hovered(lat: float, lon: float)
signal rotate_started()
signal rotate_by(delta: Vector2)
signal rotate_ended()
signal lasso_started()
signal lasso_finished(path: PackedVector2Array)

@onready var viewport: SubViewport = %SubViewport
@onready var planet: Planet = %Planet
@onready var camera: Camera3D = %Camera3D
@onready var rotation_handler: PlanetViewRotation = PlanetViewRotation.new(planet, camera)

var drawing_mode: bool = false
var editing_mode: bool = false
var lasso_mode: bool = false
var move_enabled: bool = false
var is_moving: bool = false
var move_rotating: bool = false
var move_on_globe: bool = false
var is_rotating_craton: bool = false

# Lasso input state — path collected in container-local pixels.
var _lasso_active: bool = false
var _lasso_path: PackedVector2Array = PackedVector2Array()

# Toast overlay for validation failures.
var _toast_label: Label = null
var _toast_timer: Timer = null
const TOAST_DURATION_SECONDS: float = 2.0


func start_moving(anchor_lat: float, anchor_lon: float) -> void:
	is_moving = true
	move_rotating = false
	move_on_globe = true
	move_started.emit(anchor_lat, anchor_lon)


func stop_moving() -> void:
	is_moving = false
	move_rotating = false
	move_ended.emit()


func cancel_moving() -> void:
	is_moving = false
	move_rotating = false
	move_cancelled.emit()


func _on_planet_input_event_outside(event: InputEvent) -> void:
	if is_moving:
		if event is InputEventMouseMotion:
			move_on_globe = false
		return
	if event is InputEventMouseMotion:
		craton_hovered.emit(NAN, NAN)
	if event is InputEventMouseButton:
		var p = event.position
		print("Outside click: x=%+d, y=%+d" % [roundi(p.x), roundi(p.y)])


func _on_planet_input_event_globe(lat: float, lon: float, event: InputEvent) -> void:
	if is_moving:
		if event is InputEventMouseMotion and not move_rotating:
			move_on_globe = true
			move_to.emit(lat, lon)
		return
	if event is InputEventMouseButton:
		print("Globe click: lat=%+d, lon=%+d" % [roundi(lat), roundi(lon)])
		if (drawing_mode or editing_mode or lasso_mode) and event.button_index != MOUSE_BUTTON_MIDDLE:
			return
		if not drawing_mode and not editing_mode and not lasso_mode and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT and not Input.is_key_pressed(KEY_CTRL):
			craton_clicked.emit(lat, lon)
			return
		if event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_CTRL):
			rotation_handler.start_dragging(lat, lon)
		elif event.is_pressed() and event.button_index == MOUSE_BUTTON_MIDDLE:
			rotation_handler.start_rotating(lat, lon, event.position)
	if event is InputEventMouseMotion:
		if rotation_handler.is_dragging:
			rotation_handler.handle_dragging(lat, lon)
		elif not drawing_mode and not editing_mode and not lasso_mode:
			craton_hovered.emit(lat, lon)


func _on_planet_input_event_map(lat: float, lon: float, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print("Map click: lat=%+d, lon=%+d" % [roundi(lat), roundi(lon)])
		if not drawing_mode and not editing_mode and not lasso_mode and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT and not Input.is_key_pressed(KEY_CTRL):
			craton_clicked.emit(lat, lon)
			return
	if event is InputEventMouseMotion:
		if not drawing_mode and not editing_mode and not lasso_mode:
			craton_hovered.emit(lat, lon)


func _on_gui_input(event: InputEvent) -> void:
	# Mouse wheel always works (zoom)
	if event is InputEventMouseButton and event.is_pressed():
		rotation_handler.handle_mouse_wheel(event.button_index)

	# Lasso tool captures LMB drag in screen space. MMB/wheel fall through
	# so pan/zoom still work while this tool is active.
	if lasso_mode:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				_lasso_active = true
				_lasso_path.clear()
				_lasso_path.append(event.position)
				lasso_started.emit()
				queue_redraw()
				accept_event()
				return
			elif _lasso_active:
				_lasso_active = false
				var path := _lasso_path.duplicate()
				_lasso_path.clear()
				queue_redraw()
				lasso_finished.emit(path)
				accept_event()
				return
		elif event is InputEventMouseMotion and _lasso_active:
			_lasso_path.append(event.position)
			queue_redraw()
			accept_event()
			return

	if is_rotating_craton:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_released():
			is_rotating_craton = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			rotate_ended.emit()
		elif event is InputEventMouseMotion:
			rotate_by.emit(event.relative)
		return

	if is_moving:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_MIDDLE:
				if event.is_pressed():
					move_rotating = true
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				else:
					move_rotating = false
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif event.button_index == MOUSE_BUTTON_LEFT and event.is_released():
				if move_on_globe:
					stop_moving()
				else:
					cancel_moving()
		elif event is InputEventMouseMotion:
			if move_rotating:
				rotation_handler.handle_rotating(event.relative)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed() and move_enabled:
		is_rotating_craton = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		rotate_started.emit()
		return

	if event is InputEventMouseMotion:
		rotation_handler.handle_mouse_motion(event.relative)
	if event is InputEventMouseButton and event.is_released():
		rotation_handler.handle_mouse_button_released()


### Lasso overlay drawing + projection helpers


func _draw() -> void:
	if _lasso_path.size() < 2:
		return
	# Yellow semi-transparent polyline; draws on top of the subviewport output.
	var col := Color(1.0, 0.95, 0.2, 0.9)
	var pts := _lasso_path
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], col, 2.0, true)
	# Closing line at reduced opacity so the user sees the implied polygon.
	var closing := Color(1.0, 0.95, 0.2, 0.35)
	draw_line(pts[pts.size() - 1], pts[0], closing, 2.0, true)


func clear_lasso_path() -> void:
	if _lasso_active or _lasso_path.size() > 0:
		_lasso_active = false
		_lasso_path.clear()
		queue_redraw()


# Project a lat/lon point (degrees) to container-local screen space.
# Returns {"screen": Vector2, "visible": bool}. `visible` is false when the
# point sits on the far hemisphere of the globe (camera can't see it) or is
# outside the camera's frustum.
func project_latlon_to_screen(lat: float, lon: float) -> Dictionary:
	var is_globe := not planet.show_map
	var host: Node3D
	var local_pos: Vector3
	if is_globe:
		host = planet.globe
		local_pos = _latlon_to_xyz(lat, lon)
	else:
		host = planet.map
		local_pos = Vector3(lon / 180.0, lat / 90.0, 0.0)
	var world_pos: Vector3 = host.global_transform * local_pos
	var visible := true
	if is_globe:
		var outward := (world_pos - host.global_position).normalized()
		var to_cam := camera.global_position - world_pos
		if outward.dot(to_cam) <= 0.0:
			visible = false
	if visible and not camera.is_position_in_frustum(world_pos):
		visible = false
	if camera.is_position_behind(world_pos):
		visible = false
	var sub_pos: Vector2 = camera.unproject_position(world_pos)
	var vp_size := Vector2(viewport.size)
	var c_size := size
	var screen := Vector2(
		sub_pos.x * c_size.x / vp_size.x,
		sub_pos.y * c_size.y / vp_size.y,
	)
	return {"screen": screen, "visible": visible}


static func _latlon_to_xyz(lat_deg: float, lon_deg: float) -> Vector3:
	var lat_rad := deg_to_rad(lat_deg)
	var lon_rad := deg_to_rad(lon_deg)
	var cos_lat := cos(lat_rad)
	return Vector3(cos_lat * cos(lon_rad), sin(lat_rad), cos_lat * sin(lon_rad))


### Toast overlay


func show_toast(text: String) -> void:
	if _toast_label == null:
		_build_toast()
	_toast_label.text = text
	_toast_label.visible = true
	_toast_timer.start(TOAST_DURATION_SECONDS)


func _build_toast() -> void:
	_toast_label = Label.new()
	_toast_label.name = "Toast"
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.anchor_left = 0.5
	_toast_label.anchor_right = 0.5
	_toast_label.anchor_top = 1.0
	_toast_label.anchor_bottom = 1.0
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_label.offset_bottom = -24.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_toast_label.add_theme_constant_override("outline_size", 6)
	_toast_label.visible = false
	add_child(_toast_label)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): _toast_label.visible = false)
	add_child(_toast_timer)
